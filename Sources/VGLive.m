#import "VGLive.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <Network/Network.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <stdatomic.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>

#pragma mark - Reading a web address for FFmpeg

/// Lets FFmpeg read a file on the web in blocks (HTTP range requests), with the headers the site wants.
@interface VGHTTPSource : NSObject
@property (nonatomic, readonly) int64_t length;
@property (atomic) BOOL cancelled;
- (instancetype)initWithURL:(NSURL *)url headers:(NSDictionary *)headers;
- (BOOL)open;
- (int)read:(uint8_t *)buf size:(int)size;
- (int64_t)seek:(int64_t)offset whence:(int)whence;
@end

static const int64_t kBlock = 2 * 1024 * 1024;

@implementation VGHTTPSource {
    NSURL *_url;
    NSDictionary *_headers;
    NSURLSession *_session;
    int64_t _pos;
    NSData *_block;          // the bytes starting at _blockStart
    int64_t _blockStart;
    NSData *_next;           // already fetched, starts at _nextStart
    int64_t _nextStart;
    dispatch_queue_t _prefetchQueue;
    dispatch_semaphore_t _prefetchDone;
    BOOL _prefetching;
    BOOL _queryRange;        // the site wants ?range=a-b instead of the Range header
}

- (instancetype)initWithURL:(NSURL *)url headers:(NSDictionary *)headers {
    if ((self = [super init])) {
        _url = url; _headers = headers ?: @{};
        NSURLSessionConfiguration *c = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        c.timeoutIntervalForRequest = 25;
        c.HTTPMaximumConnectionsPerHost = 4;
        _session = [NSURLSession sessionWithConfiguration:c];
        _prefetchQueue = dispatch_queue_create("vg.live.prefetch", DISPATCH_QUEUE_SERIAL);
        _blockStart = -1; _nextStart = -1;
    }
    return self;
}

- (void)dealloc { [_session invalidateAndCancel]; }

- (NSData *)fetchFrom:(int64_t)start length:(int64_t *)total {
    for (int attempt = 0; attempt < 3 && !self.cancelled; attempt++) {
        int64_t end = start + kBlock - 1;
        NSURL *u = _url;
        if (_queryRange) {
            NSURLComponents *c = [NSURLComponents componentsWithURL:_url resolvingAgainstBaseURL:NO];
            NSMutableArray *q = [c.queryItems mutableCopy] ?: [NSMutableArray array];
            [q addObject:[NSURLQueryItem queryItemWithName:@"range" value:[NSString stringWithFormat:@"%lld-%lld", start, end]]];
            c.queryItems = q;
            u = c.URL ?: _url;
        }
        NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u];
        [_headers enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s) { [r setValue:v forHTTPHeaderField:k]; }];
        if (!_queryRange) [r setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", start, end] forHTTPHeaderField:@"Range"];
        __block NSData *out = nil;
        __block NSHTTPURLResponse *resp = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [[_session dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *rs, NSError *e) {
            if (!e) { out = d; resp = (NSHTTPURLResponse *)rs; }
            dispatch_semaphore_signal(sem);
        }] resume];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        if (!resp) continue;
        NSInteger code = resp.statusCode;
        if (code == 206 || (code == 200 && out.length <= kBlock + 1024 && start == 0)) {
            if (total) {
                NSString *cr = resp.allHeaderFields[@"Content-Range"] ?: resp.allHeaderFields[@"content-range"];
                NSRange slash = [cr rangeOfString:@"/" options:NSBackwardsSearch];
                if (slash.location != NSNotFound) *total = [[cr substringFromIndex:slash.location + 1] longLongValue];
                else if (code == 200) *total = (int64_t)out.length;
            }
            return out;
        }
        if (code == 200 || code == 403 || code == 416) {
            if (!_queryRange && start == 0) { _queryRange = YES; attempt = -1; continue; }   // try the other way once
        }
    }
    return nil;
}

- (BOOL)open {
    int64_t total = 0;
    NSData *d = [self fetchFrom:0 length:&total];
    if (!d.length || total <= 0) return NO;
    _length = total; _block = d; _blockStart = 0; _pos = 0;
    return YES;
}

- (void)prefetchFrom:(int64_t)start {
    if (_prefetching || start >= _length) return;
    _prefetching = YES;
    __weak typeof(self) ws = self;
    dispatch_async(_prefetchQueue, ^{
        VGHTTPSource *s = ws; if (!s) return;
        NSData *d = [s fetchFrom:start length:NULL];
        @synchronized (s) { if (d) { s->_next = d; s->_nextStart = start; } s->_prefetching = NO; }
    });
}

- (int)read:(uint8_t *)buf size:(int)size {
    if (self.cancelled) return AVERROR_EXIT;
    if (_pos >= _length) return AVERROR_EOF;
    int done = 0;
    while (done < size && _pos < _length) {
        if (self.cancelled) return AVERROR_EXIT;
        if (_blockStart < 0 || _pos < _blockStart || _pos >= _blockStart + (int64_t)_block.length) {
            NSData *d = nil; int64_t st = (_pos / kBlock) * kBlock;
            @synchronized (self) {
                if (_next && _nextStart == st) { d = _next; _next = nil; }
            }
            if (!d) {
                // a prefetch for this block may be running: wait for it instead of asking twice
                for (int i = 0; i < 400 && !d; i++) {
                    BOOL busy; @synchronized (self) { busy = _prefetching; if (_next && _nextStart == st) { d = _next; _next = nil; } }
                    if (d || !busy) break;
                    usleep(25000);
                }
            }
            if (!d) d = [self fetchFrom:st length:NULL];
            if (!d.length) return done > 0 ? done : AVERROR(EIO);
            _block = d; _blockStart = st;
            [self prefetchFrom:st + kBlock];
        }
        int64_t off = _pos - _blockStart;
        int64_t n = MIN((int64_t)size - done, (int64_t)_block.length - off);
        if (n <= 0) break;
        memcpy(buf + done, (const uint8_t *)_block.bytes + off, (size_t)n);
        done += (int)n; _pos += n;
    }
    return done > 0 ? done : AVERROR_EOF;
}

- (int64_t)seek:(int64_t)offset whence:(int)whence {
    if (whence == AVSEEK_SIZE) return _length;
    int64_t np = _pos;
    switch (whence & ~AVSEEK_FORCE) {
        case SEEK_SET: np = offset; break;
        case SEEK_CUR: np = _pos + offset; break;
        case SEEK_END: np = _length + offset; break;
        default: return -1;
    }
    if (np < 0) return -1;
    _pos = np;
    return np;
}
@end

static int vgRead(void *opaque, uint8_t *buf, int size) { return [(__bridge VGHTTPSource *)opaque read:buf size:size]; }
static int64_t vgSeek(void *opaque, int64_t off, int whence) { return [(__bridge VGHTTPSource *)opaque seek:off whence:whence]; }

#pragma mark - One FFmpeg input

@interface VGLiveInput : NSObject
@property (nonatomic, readonly) AVFormatContext *fmt;
@property (nonatomic, readonly) AVCodecContext *dec;
@property (nonatomic, readonly) int stream;
- (NSString *)openURL:(NSURL *)url headers:(NSDictionary *)h type:(enum AVMediaType)type;
- (void)cancel;
- (BOOL)nextFrame:(AVFrame *)frame;   // NO at the end
@end

@implementation VGLiveInput {
    VGHTTPSource *_src;
    AVIOContext *_io;
    AVFormatContext *_fmt;
    AVCodecContext *_dec;
    AVPacket *_pkt;
    int _stream;
    BOOL _flushing;
}
@synthesize fmt = _fmt, dec = _dec, stream = _stream;

- (void)cancel { _src.cancelled = YES; }

- (void)dealloc {
    if (_pkt) av_packet_free(&_pkt);
    if (_dec) avcodec_free_context(&_dec);
    if (_fmt) avformat_close_input(&_fmt);
    if (_io) { av_freep(&_io->buffer); avio_context_free(&_io); }
}

- (NSString *)openURL:(NSURL *)url headers:(NSDictionary *)h type:(enum AVMediaType)type {
    _src = [[VGHTTPSource alloc] initWithURL:url headers:h];
    if (![_src open]) return @"Couldn't reach the video.";
    unsigned char *buf = av_malloc(64 * 1024);
    _io = avio_alloc_context(buf, 64 * 1024, 0, (__bridge void *)_src, vgRead, NULL, vgSeek);
    if (!_io) return @"Out of memory.";
    _fmt = avformat_alloc_context();
    _fmt->pb = _io;
    _fmt->flags |= AVFMT_FLAG_CUSTOM_IO;
    if (avformat_open_input(&_fmt, "stream", NULL, NULL) < 0) return @"Couldn't read the video.";
    _fmt->probesize = 8 * 1024 * 1024;
    if (avformat_find_stream_info(_fmt, NULL) < 0) return @"Couldn't read the video.";
    const AVCodec *codec = NULL;
    _stream = av_find_best_stream(_fmt, type, -1, -1, &codec, 0);
    if (_stream < 0 || !codec) return @"VidGrab can't convert this one.";
    _dec = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(_dec, _fmt->streams[_stream]->codecpar);
    _dec->thread_count = 0;
    _dec->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
    if (avcodec_open2(_dec, codec, NULL) < 0) return @"Couldn't start the decoder.";
    _pkt = av_packet_alloc();
    return nil;
}

- (BOOL)nextFrame:(AVFrame *)frame {
    while (YES) {
        int r = avcodec_receive_frame(_dec, frame);
        if (r == 0) return YES;
        if (r != AVERROR(EAGAIN)) return NO;
        if (_flushing) return NO;
        while (YES) {
            int rr = av_read_frame(_fmt, _pkt);
            if (rr < 0) { avcodec_send_packet(_dec, NULL); _flushing = YES; break; }
            if (_pkt->stream_index == _stream) {
                avcodec_send_packet(_dec, _pkt);
                av_packet_unref(_pkt);
                break;
            }
            av_packet_unref(_pkt);
        }
    }
}
@end

#pragma mark - The live stream

static void fillNV12(AVFrame *f, CVPixelBufferRef pb) {
    CVPixelBufferLockBaseAddress(pb, 0);
    int w = f->width, h = f->height;
    BOOL tenBit = f->format == AV_PIX_FMT_YUV420P10LE || f->format == AV_PIX_FMT_YUV420P10BE;
    uint8_t *dy = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
    size_t dys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
    for (int y = 0; y < h; y++) {
        uint8_t *dst = dy + y * dys;
        if (tenBit) { const uint16_t *src = (const uint16_t *)(f->data[0] + y * f->linesize[0]); for (int x = 0; x < w; x++) dst[x] = (uint8_t)(src[x] >> 2); }
        else memcpy(dst, f->data[0] + y * f->linesize[0], (size_t)w);
    }
    uint8_t *duv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
    size_t duvs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
    int cw = (w + 1) / 2, ch = (h + 1) / 2;
    for (int y = 0; y < ch; y++) {
        uint8_t *dst = duv + y * duvs;
        if (tenBit) {
            const uint16_t *u = (const uint16_t *)(f->data[1] + y * f->linesize[1]);
            const uint16_t *v = (const uint16_t *)(f->data[2] + y * f->linesize[2]);
            for (int x = 0; x < cw; x++) { dst[2 * x] = (uint8_t)(u[x] >> 2); dst[2 * x + 1] = (uint8_t)(v[x] >> 2); }
        } else {
            const uint8_t *u = f->data[1] + y * f->linesize[1];
            const uint8_t *v = f->data[2] + y * f->linesize[2];
            for (int x = 0; x < cw; x++) { dst[2 * x] = u[x]; dst[2 * x + 1] = v[x]; }
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
}

static CMSampleBufferRef makePCM(const int16_t *data, int frames, int channels, int rate, CMTime pts) {
    AudioStreamBasicDescription asbd = {0};
    asbd.mSampleRate = rate; asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    asbd.mBytesPerPacket = 2 * channels; asbd.mFramesPerPacket = 1; asbd.mBytesPerFrame = 2 * channels;
    asbd.mChannelsPerFrame = channels; asbd.mBitsPerChannel = 16;
    CMAudioFormatDescriptionRef fd = NULL;
    if (CMAudioFormatDescriptionCreate(NULL, &asbd, 0, NULL, 0, NULL, NULL, &fd) != noErr) return NULL;
    size_t len = (size_t)frames * 2 * channels;
    CMBlockBufferRef bb = NULL;
    if (CMBlockBufferCreateWithMemoryBlock(NULL, NULL, len, NULL, NULL, 0, len, kCMBlockBufferAssureMemoryNowFlag, &bb) != noErr) { CFRelease(fd); return NULL; }
    CMBlockBufferReplaceDataBytes(data, bb, 0, len);
    CMSampleBufferRef sb = NULL;
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(NULL, bb, fd, frames, pts, NULL, &sb);
    CFRelease(bb); CFRelease(fd);
    return sb;
}

@interface VGLiveStream () <AVAssetWriterDelegate>
@end

@implementation VGLiveStream {
    NSDictionary *_video, *_audio;
    double _fps, _duration;
    NSString *_dir;
    NSLock *_lock;
    NSMutableArray<NSNumber *> *_segDurations;
    BOOL _haveInit, _ended, _stopped, _readyFired;
    void (^_ready)(NSURL *);
    void (^_failed)(NSString *);
    nw_listener_t _listener;
    uint16_t _port;
    AVAssetWriter *_writer;
    VGLiveInput *_vin, *_ain;
    atomic_bool _cancel;
    atomic_llong _producedMs;
}

- (instancetype)initWithVideo:(NSDictionary *)video audio:(NSDictionary *)audio fps:(double)fps duration:(double)duration {
    if ((self = [super init])) {
        _video = video; _audio = audio; _fps = fps > 0 ? fps : 30; _duration = duration;
        _lock = [NSLock new];
        _segDurations = [NSMutableArray array];
        _dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"vglive-%@", NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:_dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

- (double)duration { return _duration; }
- (void)dealloc { [self stop]; }

- (void)stop {
    if (_stopped) return;
    _stopped = YES;
    atomic_store(&_cancel, true);
    [_vin cancel]; [_ain cancel];
    if (_listener) { nw_listener_cancel(_listener); _listener = nil; }
    NSString *d = _dir;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSFileManager.defaultManager removeItemAtPath:d error:nil];
    });
}

- (void)fail:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_stopped) return;
        void (^f)(NSString *) = self->_failed;
        self->_failed = nil; self->_ready = nil;
        [self stop];
        if (f) f(msg);
    });
}

- (void)startWithReady:(void (^)(NSURL *))ready failed:(void (^)(NSString *))failed {
    _ready = ready; _failed = failed;
    [self startServer];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *e = [self run];
        if (e && !self->_stopped) [self fail:e];
    });
}

#pragma mark Segments

- (void)assetWriter:(AVAssetWriter *)writer didOutputSegmentData:(NSData *)data segmentType:(AVAssetSegmentType)type segmentReport:(AVAssetSegmentReport *)report {
    [_lock lock];
    if (type == AVAssetSegmentTypeInitialization) {
        [data writeToFile:[_dir stringByAppendingPathComponent:@"init.mp4"] atomically:YES];
        _haveInit = YES;
    } else {
        NSUInteger n = _segDurations.count;
        [data writeToFile:[_dir stringByAppendingPathComponent:[NSString stringWithFormat:@"seg%lu.m4s", (unsigned long)n]] atomically:YES];
        double dur = 4;
        for (AVAssetSegmentTrackReport *tr in report.trackReports) {
            if (tr.mediaType == AVMediaTypeVideo) { double s = CMTimeGetSeconds(tr.duration); if (s > 0) dur = s; }
        }
        [_segDurations addObject:@(dur)];
    }
    BOOL fire = _haveInit && _segDurations.count >= 1 && !_readyFired;
    if (fire) _readyFired = YES;
    [_lock unlock];
    if (fire && _port) [self fireReady];
}

- (void)fireReady {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_stopped || !self->_ready) return;
        void (^r)(NSURL *) = self->_ready; self->_ready = nil;
        r([NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/live.m3u8", self->_port]]);
    });
}

- (NSString *)playlist {
    [_lock lock];
    NSMutableString *s = [NSMutableString stringWithString:@"#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n"];
    double maxd = 4; for (NSNumber *d in _segDurations) maxd = MAX(maxd, d.doubleValue);
    [s appendFormat:@"#EXT-X-TARGETDURATION:%d\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:EVENT\n#EXT-X-MAP:URI=\"init.mp4\"\n", (int)ceil(maxd)];
    for (NSUInteger i = 0; i < _segDurations.count; i++) [s appendFormat:@"#EXTINF:%.5f,\nseg%lu.m4s\n", _segDurations[i].doubleValue, (unsigned long)i];
    if (_ended) [s appendString:@"#EXT-X-ENDLIST\n"];
    [_lock unlock];
    return s;
}

#pragma mark Local server

- (void)startServer {
    nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_parameters_set_local_endpoint(params, nw_endpoint_create_host("127.0.0.1", "0"));
    nw_listener_t l = nw_listener_create(params);
    if (!l) { [self fail:@"Couldn't start the local player server."]; return; }
    _listener = l;
    dispatch_queue_t q = dispatch_queue_create("vg.live.server", DISPATCH_QUEUE_CONCURRENT);
    nw_listener_set_queue(l, q);
    __weak typeof(self) ws = self;
    nw_listener_set_state_changed_handler(l, ^(nw_listener_state_t st, nw_error_t err) {
        VGLiveStream *s = ws; if (!s) return;
        if (st == nw_listener_state_ready) {
            s->_port = nw_listener_get_port(l);
            [s->_lock lock]; BOOL fire = s->_haveInit && s->_segDurations.count >= 1 && !s->_readyFired; if (fire) s->_readyFired = YES; [s->_lock unlock];
            if (fire) [s fireReady];
        } else if (st == nw_listener_state_failed) {
            [s fail:@"Couldn't start the local player server."];
        }
    });
    nw_listener_set_new_connection_handler(l, ^(nw_connection_t c) {
        VGLiveStream *s = ws; if (!s) { nw_connection_cancel(c); return; }
        nw_connection_set_queue(c, q);
        nw_connection_start(c);
        [s receiveOn:c accumulated:[NSMutableData data]];
    });
    nw_listener_start(l);
}

- (void)receiveOn:(nw_connection_t)c accumulated:(NSMutableData *)acc {
    __weak typeof(self) ws = self;
    nw_connection_receive(c, 1, 8192, ^(dispatch_data_t content, nw_content_context_t ctx, bool complete, nw_error_t err) {
        VGLiveStream *s = ws;
        if (!s || err) { nw_connection_cancel(c); return; }
        if (content) {
            dispatch_data_apply(content, ^bool(dispatch_data_t r, size_t o, const void *buf, size_t sz) { [acc appendBytes:buf length:sz]; return true; });
        }
        NSData *end = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        if ([acc rangeOfData:end options:0 range:NSMakeRange(0, acc.length)].location != NSNotFound) { [s respondOn:c request:acc]; return; }
        if (complete || acc.length > 16384) { nw_connection_cancel(c); return; }
        [s receiveOn:c accumulated:acc];
    });
}

- (void)send:(nw_connection_t)c status:(NSString *)status type:(NSString *)type body:(NSData *)body extra:(NSString *)extra {
    NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %@\r\nContent-Type: %@\r\nContent-Length: %lu\r\nAccept-Ranges: bytes\r\nCache-Control: no-cache\r\nConnection: close\r\n%@\r\n", status, type, (unsigned long)body.length, extra ?: @""];
    NSMutableData *out = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [out appendData:body];
    dispatch_data_t dd = dispatch_data_create(out.bytes, out.length, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [out length]; });
    nw_connection_send(c, dd, NW_CONNECTION_FINAL_MESSAGE_CONTEXT, true, ^(nw_error_t e) { nw_connection_cancel(c); });
}

- (void)respondOn:(nw_connection_t)c request:(NSData *)req {
    NSString *text = [[NSString alloc] initWithData:req encoding:NSUTF8StringEncoding] ?: @"";
    NSArray *lines = [text componentsSeparatedByString:@"\r\n"];
    NSArray *parts = [lines.firstObject componentsSeparatedByString:@" "];
    NSString *path = parts.count > 1 ? parts[1] : @"/";
    NSString *name = [[path lastPathComponent] stringByRemovingPercentEncoding];
    NSString *rangeHeader = nil;
    for (NSString *l in lines) if ([l.lowercaseString hasPrefix:@"range:"]) rangeHeader = [[l substringFromIndex:6] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSData *body = nil; NSString *type = @"video/mp4";
    if ([name isEqualToString:@"live.m3u8"]) { body = [[self playlist] dataUsingEncoding:NSUTF8StringEncoding]; type = @"application/vnd.apple.mpegurl"; }
    else if ([name isEqualToString:@"init.mp4"] || ([name hasPrefix:@"seg"] && [name hasSuffix:@".m4s"])) {
        body = [NSData dataWithContentsOfFile:[_dir stringByAppendingPathComponent:name]];
        if (![name isEqualToString:@"init.mp4"]) type = @"video/iso.segment";
    }
    if (!body) { [self send:c status:@"404 Not Found" type:@"text/plain" body:[NSData data] extra:nil]; return; }
    if ([rangeHeader hasPrefix:@"bytes="]) {
        NSArray *r = [[rangeHeader substringFromIndex:6] componentsSeparatedByString:@"-"];
        long long a = [r.firstObject longLongValue];
        long long b = (r.count > 1 && [r[1] length]) ? [r[1] longLongValue] : (long long)body.length - 1;
        b = MIN(b, (long long)body.length - 1);
        if (a <= b) {
            NSData *slice = [body subdataWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a + 1))];
            [self send:c status:@"206 Partial Content" type:type body:slice extra:[NSString stringWithFormat:@"Content-Range: bytes %lld-%lld/%lu\r\n", a, b, (unsigned long)body.length]];
            return;
        }
    }
    [self send:c status:@"200 OK" type:type body:body extra:nil];
}

#pragma mark Conversion

- (NSString *)run {
    // Picture
    _vin = [VGLiveInput new];
    NSString *e = [_vin openURL:[NSURL URLWithString:_video[@"url"]] headers:_video[@"headers"] type:AVMEDIA_TYPE_VIDEO];
    if (e) return e;
    AVStream *st = _vin.fmt->streams[_vin.stream];
    int w = _vin.dec->width, h = _vin.dec->height;
    double fps = st->avg_frame_rate.den ? av_q2d(st->avg_frame_rate) : _fps;
    if (fps <= 0 || fps > 120) fps = _fps;
    AVRational tb = st->time_base;
    if (_duration <= 0 && _vin.fmt->duration > 0) _duration = _vin.fmt->duration / (double)AV_TIME_BASE;

    double from = self.startAt > 1 ? self.startAt : 0;
    if (from > 0) {
        av_seek_frame(_vin.fmt, -1, (int64_t)(from * AV_TIME_BASE), AVSEEK_FLAG_BACKWARD);
        avcodec_flush_buffers(_vin.dec);
    }

    // Sound (optional: without it the picture still plays)
    NSString *ae = nil;
    if (_audio) {
        _ain = [VGLiveInput new];
        ae = [_ain openURL:[NSURL URLWithString:_audio[@"url"]] headers:_audio[@"headers"] type:AVMEDIA_TYPE_AUDIO];
        if (ae) _ain = nil;
        else if (from > 0) {
            av_seek_frame(_ain.fmt, -1, (int64_t)(from * AV_TIME_BASE), AVSEEK_FLAG_BACKWARD);
            avcodec_flush_buffers(_ain.dec);
        }
    }

    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithContentType:[UTType typeWithIdentifier:@"public.mpeg-4"]];
    writer.outputFileTypeProfile = AVFileTypeProfileMPEG4AppleHLS;
    writer.preferredOutputSegmentInterval = CMTimeMakeWithSeconds(4, 1);
    writer.initialSegmentStartTime = kCMTimeZero;
    writer.delegate = self;
    _writer = writer;

    double pixels = (double)w * h;
    double rate = pixels >= 3840.0 * 2000 ? 20e6 : (pixels >= 2560.0 * 1300 ? 11e6 : 6e6);
    if (fps > 40) rate *= 1.4;
    NSDictionary *vs = @{AVVideoCodecKey: AVVideoCodecTypeHEVC, AVVideoWidthKey: @(w), AVVideoHeightKey: @(h),
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @((long long)rate),
                                           AVVideoExpectedSourceFrameRateKey: @((int)round(fps)),
                                           AVVideoMaxKeyFrameIntervalDurationKey: @2,
                                           AVVideoAllowFrameReorderingKey: @NO},
        AVVideoColorPropertiesKey: @{AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                     AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                     AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2}};
    if (![writer canApplyOutputSettings:vs forMediaType:AVMediaTypeVideo]) {
        NSMutableDictionary *m = [vs mutableCopy]; m[AVVideoCodecKey] = AVVideoCodecTypeH264; vs = m;
        if (![writer canApplyOutputSettings:vs forMediaType:AVMediaTypeVideo]) return @"This iPhone can't convert video at this size.";
    }
    AVAssetWriterInput *vin = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:vs];
    vin.expectsMediaDataInRealTime = NO;
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:vin sourcePixelBufferAttributes:@{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (id)kCVPixelBufferWidthKey: @(w), (id)kCVPixelBufferHeightKey: @(h), (id)kCVPixelBufferIOSurfacePropertiesKey: @{}}];
    [writer addInput:vin];

    AVAssetWriterInput *ain = nil;
    int outRate = 48000, outCh = 2;
    SwrContext *swr = NULL;
    if (_ain) {
        AVCodecContext *ad = _ain.dec;
        outRate = ad->sample_rate == 44100 ? 44100 : 48000;
        NSDictionary *as = @{AVFormatIDKey: @(kAudioFormatMPEG4AAC), AVNumberOfChannelsKey: @(outCh), AVSampleRateKey: @(outRate), AVEncoderBitRateKey: @160000};
        ain = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:as];
        ain.expectsMediaDataInRealTime = NO;
        if ([writer canAddInput:ain]) [writer addInput:ain]; else ain = nil;
        AVChannelLayout out; av_channel_layout_default(&out, outCh);
        AVChannelLayout in = ad->ch_layout;
        if (in.nb_channels <= 0) av_channel_layout_default(&in, 2);
        if (swr_alloc_set_opts2(&swr, &out, AV_SAMPLE_FMT_S16, outRate, &in, ad->sample_fmt, ad->sample_rate, 0, NULL) < 0 || !swr || swr_init(swr) < 0) { ain = nil; if (swr) swr_free(&swr); }
    }

    if (![writer startWriting]) return writer.error.localizedDescription ?: @"Couldn't start the converter.";
    [writer startSessionAtSourceTime:kCMTimeZero];

    dispatch_group_t group = dispatch_group_create();
    __block NSString *videoErr = nil;
    __block atomic_bool vdone = false, adone = false;
    AVFrame *vframe = av_frame_alloc();
    AVFrame *aframe = av_frame_alloc();
    __block int64_t firstV = AV_NOPTS_VALUE;

    dispatch_group_enter(group);
    dispatch_queue_t vq = dispatch_queue_create("vg.live.video", DISPATCH_QUEUE_SERIAL);
    [vin requestMediaDataWhenReadyOnQueue:vq usingBlock:^{
        while (vin.isReadyForMoreMediaData && !atomic_load(&vdone)) {
            if (atomic_load(&self->_cancel) || ![self->_vin nextFrame:vframe]) {
                atomic_store(&vdone, true); [vin markAsFinished]; dispatch_group_leave(group); return;
            }
            int64_t pts = vframe->best_effort_timestamp;
            if (pts == AV_NOPTS_VALUE) pts = vframe->pts;
            if (from > 0 && pts != AV_NOPTS_VALUE && pts * av_q2d(tb) < from - 0.001) { av_frame_unref(vframe); continue; }   // before the chosen second
            if (firstV == AV_NOPTS_VALUE) firstV = pts;
            pts -= firstV;
            CMTime t = CMTimeMake(pts * tb.num, tb.den);
            double sec = CMTimeGetSeconds(t);
            // Far enough ahead of the viewer: wait (keeps the phone cool and the storage small)
            while (!atomic_load(&self->_cancel) && sec - self.playhead > 100) usleep(200000);
            CVPixelBufferRef pb = NULL;
            CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pb);
            if (!pb) { videoErr = @"Ran out of memory while converting."; atomic_store(&vdone, true); [vin markAsFinished]; dispatch_group_leave(group); return; }
            fillNV12(vframe, pb);
            CVBufferSetAttachment(pb, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pb, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
            BOOL ok = [adaptor appendPixelBuffer:pb withPresentationTime:t];
            CVPixelBufferRelease(pb);
            av_frame_unref(vframe);
            if (!ok) { videoErr = writer.error.localizedDescription ?: @"The video encoder stopped."; atomic_store(&vdone, true); [vin markAsFinished]; dispatch_group_leave(group); return; }
        }
    }];

    if (ain && swr) {
        dispatch_group_enter(group);
        dispatch_queue_t aq = dispatch_queue_create("vg.live.audio", DISPATCH_QUEUE_SERIAL);
        __block int64_t samples = 0;
        [ain requestMediaDataWhenReadyOnQueue:aq usingBlock:^{
            while (ain.isReadyForMoreMediaData && !atomic_load(&adone)) {
                if (atomic_load(&self->_cancel) || ![self->_ain nextFrame:aframe]) {
                    atomic_store(&adone, true); [ain markAsFinished]; dispatch_group_leave(group); return;
                }
                if (from > 0) {
                    int64_t ap = aframe->best_effort_timestamp;
                    if (ap == AV_NOPTS_VALUE) ap = aframe->pts;
                    AVRational atb = self->_ain.fmt->streams[self->_ain.stream]->time_base;
                    if (ap != AV_NOPTS_VALUE && ap * av_q2d(atb) + (double)aframe->nb_samples / MAX(1, aframe->sample_rate) <= from) { av_frame_unref(aframe); continue; }
                }
                int maxOut = swr_get_out_samples(swr, aframe->nb_samples);
                if (maxOut <= 0) { av_frame_unref(aframe); continue; }
                int16_t *pcm = av_malloc((size_t)maxOut * outCh * 2);
                uint8_t *outp[1] = {(uint8_t *)pcm};
                int n = swr_convert(swr, outp, maxOut, (const uint8_t **)aframe->extended_data, aframe->nb_samples);
                av_frame_unref(aframe);
                if (n > 0) {
                    CMSampleBufferRef sb = makePCM(pcm, n, outCh, outRate, CMTimeMake(samples, outRate));
                    if (sb) { [ain appendSampleBuffer:sb]; CFRelease(sb); }
                    samples += n;
                }
                av_free(pcm);
            }
        }];
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    av_frame_free(&vframe); av_frame_free(&aframe);
    if (swr) swr_free(&swr);

    if (atomic_load(&_cancel)) { [writer cancelWriting]; return nil; }
    if (videoErr) { [writer cancelWriting]; return videoErr; }

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) return writer.error.localizedDescription ?: @"Couldn't finish the converted video.";
    [_lock lock]; _ended = YES; [_lock unlock];
    return nil;
}

@end
