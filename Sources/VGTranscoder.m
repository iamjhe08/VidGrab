#import "VGTranscoder.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <stdatomic.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>

@interface VGTranscoder ()
@property (atomic) BOOL cancelled;
@end

@implementation VGTranscoder {
    AVFormatContext *_fmt;
    AVCodecContext *_dec;
    AVPacket *_pkt;
    AVFrame *_frame;
    int _stream;
    BOOL _flushing;
    int64_t _firstPts;
}

- (void)cancel { self.cancelled = YES; }

- (void)cleanup {
    if (_frame) av_frame_free(&_frame);
    if (_pkt) av_packet_free(&_pkt);
    if (_dec) avcodec_free_context(&_dec);
    if (_fmt) avformat_close_input(&_fmt);
}

- (void)dealloc { [self cleanup]; }

- (NSString *)openVideo:(NSURL *)url {
    if (avformat_open_input(&_fmt, url.fileSystemRepresentation, NULL, NULL) < 0) return @"Couldn't open the downloaded video.";
    if (avformat_find_stream_info(_fmt, NULL) < 0) return @"Couldn't read the downloaded video.";
    const AVCodec *codec = NULL;
    _stream = av_find_best_stream(_fmt, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    if (_stream < 0 || !codec) return @"The downloaded file has no video VidGrab can convert.";
    _dec = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(_dec, _fmt->streams[_stream]->codecpar);
    _dec->thread_count = 0;  // use all cores
    _dec->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
    if (avcodec_open2(_dec, codec, NULL) < 0) return @"Couldn't start the video decoder.";
    _pkt = av_packet_alloc();
    _frame = av_frame_alloc();
    _firstPts = AV_NOPTS_VALUE;
    return nil;
}

// Returns YES with a decoded frame in _frame, NO at the end of the stream.
- (BOOL)nextFrame {
    while (YES) {
        int r = avcodec_receive_frame(_dec, _frame);
        if (r == 0) return YES;
        if (r == AVERROR_EOF) return NO;
        if (r != AVERROR(EAGAIN)) return NO;
        if (_flushing) return NO;
        while (YES) {
            int rr = av_read_frame(_fmt, _pkt);
            if (rr < 0) {
                avcodec_send_packet(_dec, NULL);
                _flushing = YES;
                break;
            }
            if (_pkt->stream_index == _stream) {
                avcodec_send_packet(_dec, _pkt);
                av_packet_unref(_pkt);
                break;
            }
            av_packet_unref(_pkt);
        }
    }
}

// Copies a YUV 4:2:0 frame (8 or 10 bit) into an NV12 pixel buffer.
static void fillNV12(AVFrame *f, CVPixelBufferRef pb) {
    CVPixelBufferLockBaseAddress(pb, 0);
    int w = f->width, h = f->height;
    BOOL tenBit = f->format == AV_PIX_FMT_YUV420P10LE || f->format == AV_PIX_FMT_YUV420P10BE;

    uint8_t *dy = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
    size_t dys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
    for (int y = 0; y < h; y++) {
        uint8_t *dst = dy + y * dys;
        if (tenBit) {
            const uint16_t *src = (const uint16_t *)(f->data[0] + y * f->linesize[0]);
            for (int x = 0; x < w; x++) dst[x] = (uint8_t)(src[x] >> 2);
        } else {
            memcpy(dst, f->data[0] + y * f->linesize[0], (size_t)w);
        }
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

- (NSDictionary *)videoSettingsWidth:(int)w height:(int)h fps:(double)fps sourceBitrate:(int64_t)srcBitrate {
    // Aim a little above the VP9 source; HEVC at this rate looks the same.
    double pixels = (double)w * h;
    double base = pixels >= 3840.0 * 2000 ? 28e6 : (pixels >= 2560.0 * 1300 ? 14e6 : 8e6);
    if (fps > 40) base *= 1.5;
    double rate = srcBitrate > 0 ? MAX(srcBitrate * 1.3, base * 0.6) : base;
    rate = MIN(rate, 60e6);

    NSString *codec = AVVideoCodecTypeHEVC;
    NSDictionary *props = @{
        AVVideoAverageBitRateKey: @((long long)rate),
        AVVideoExpectedSourceFrameRateKey: @((int)round(fps > 0 ? fps : 30)),
        AVVideoMaxKeyFrameIntervalDurationKey: @2,
        AVVideoAllowFrameReorderingKey: @YES,
    };
    NSDictionary *color = @{
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    };
    return @{AVVideoCodecKey: codec, AVVideoWidthKey: @(w), AVVideoHeightKey: @(h),
             AVVideoCompressionPropertiesKey: props, AVVideoColorPropertiesKey: color};
}

- (void)convertVideo:(NSURL *)video audio:(NSURL *)audio to:(NSURL *)output
            progress:(void (^)(double))progress completion:(void (^)(NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = [self runVideo:video audio:audio to:output progress:progress];
        [self cleanup];
        if (err) [NSFileManager.defaultManager removeItemAtURL:output error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
    });
}

- (NSString *)runVideo:(NSURL *)video audio:(NSURL *)audio to:(NSURL *)output progress:(void (^)(double))progress {
    NSString *e = [self openVideo:video];
    if (e) return e;

    AVStream *st = _fmt->streams[_stream];
    int w = _dec->width, h = _dec->height;
    double fps = st->avg_frame_rate.den ? av_q2d(st->avg_frame_rate) : 30;
    double duration = _fmt->duration > 0 ? _fmt->duration / (double)AV_TIME_BASE : 0;
    int64_t srcBitrate = st->codecpar->bit_rate ?: _fmt->bit_rate;
    AVRational tb = st->time_base;

    [NSFileManager.defaultManager removeItemAtURL:output error:nil];
    NSError *ne = nil;
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:output fileType:AVFileTypeMPEG4 error:&ne];
    if (!writer) return ne.localizedDescription ?: @"Couldn't create the output file.";
    writer.shouldOptimizeForNetworkUse = YES;

    NSDictionary *vs = [self videoSettingsWidth:w height:h fps:fps sourceBitrate:srcBitrate];
    if (![writer canApplyOutputSettings:vs forMediaType:AVMediaTypeVideo]) {
        // Older iPhones without hardware HEVC: fall back to H.264.
        NSMutableDictionary *m = [vs mutableCopy];
        m[AVVideoCodecKey] = AVVideoCodecTypeH264;
        vs = m;
        if (![writer canApplyOutputSettings:vs forMediaType:AVMediaTypeVideo]) return @"This iPhone can't encode video at this size. Pick 1080p instead.";
    }
    AVAssetWriterInput *vin = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:vs];
    vin.expectsMediaDataInRealTime = NO;
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:vin sourcePixelBufferAttributes:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            (id)kCVPixelBufferWidthKey: @(w), (id)kCVPixelBufferHeightKey: @(h),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        }];
    [writer addInput:vin];

    // Audio: copy the AAC track as-is.
    AVURLAsset *aa = audio ? [AVURLAsset URLAssetWithURL:audio options:nil] : nil;
    AVAssetTrack *at = aa ? [aa tracksWithMediaType:AVMediaTypeAudio].firstObject : nil;
    AVAssetReader *reader = nil;
    AVAssetReaderTrackOutput *aout = nil;
    AVAssetWriterInput *ain = nil;
    if (at) {
        reader = [AVAssetReader assetReaderWithAsset:aa error:nil];
        aout = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:at outputSettings:nil];
        if (reader && [reader canAddOutput:aout]) {
            [reader addOutput:aout];
            ain = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:nil
                                                  sourceFormatHint:(__bridge CMFormatDescriptionRef)at.formatDescriptions.firstObject];
            ain.expectsMediaDataInRealTime = NO;
            if ([writer canAddInput:ain]) [writer addInput:ain]; else ain = nil;
        }
    }

    if (![writer startWriting]) return writer.error.localizedDescription ?: @"Couldn't start writing the video.";
    [writer startSessionAtSourceTime:kCMTimeZero];
    if (ain && ![reader startReading]) ain = nil;

    dispatch_group_t group = dispatch_group_create();
    __block NSString *videoErr = nil;
    __block atomic_bool videoDone = false, audioDone = false;

    dispatch_group_enter(group);
    dispatch_queue_t vq = dispatch_queue_create("vg.convert.video", DISPATCH_QUEUE_SERIAL);
    [vin requestMediaDataWhenReadyOnQueue:vq usingBlock:^{
        while (vin.isReadyForMoreMediaData && !atomic_load(&videoDone)) {
            BOOL finished = self.cancelled || ![self nextFrame];
            if (finished) {
                atomic_store(&videoDone, true);
                [vin markAsFinished];
                dispatch_group_leave(group);
                return;
            }
            int64_t pts = self->_frame->best_effort_timestamp;
            if (pts == AV_NOPTS_VALUE) pts = self->_frame->pts;
            if (self->_firstPts == AV_NOPTS_VALUE) self->_firstPts = pts;
            pts -= self->_firstPts;
            CMTime t = CMTimeMake(pts * tb.num, tb.den);

            CVPixelBufferRef pb = NULL;
            CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pb);
            if (!pb) {
                videoErr = @"Ran out of memory while converting.";
                atomic_store(&videoDone, true);
                [vin markAsFinished];
                dispatch_group_leave(group);
                return;
            }
            fillNV12(self->_frame, pb);
            CVBufferSetAttachment(pb, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pb, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
            BOOL ok = [adaptor appendPixelBuffer:pb withPresentationTime:t];
            CVPixelBufferRelease(pb);
            av_frame_unref(self->_frame);
            if (!ok) {
                videoErr = writer.error.localizedDescription ?: @"The video encoder stopped.";
                atomic_store(&videoDone, true);
                [vin markAsFinished];
                dispatch_group_leave(group);
                return;
            }
            if (duration > 0 && progress) {
                double frac = MIN(1.0, CMTimeGetSeconds(t) / duration);
                dispatch_async(dispatch_get_main_queue(), ^{ progress(frac); });
            }
        }
    }];

    if (ain) {
        dispatch_group_enter(group);
        dispatch_queue_t aq = dispatch_queue_create("vg.convert.audio", DISPATCH_QUEUE_SERIAL);
        [ain requestMediaDataWhenReadyOnQueue:aq usingBlock:^{
            while (ain.isReadyForMoreMediaData && !atomic_load(&audioDone)) {
                CMSampleBufferRef sb = self.cancelled ? NULL : [aout copyNextSampleBuffer];
                if (!sb) {
                    atomic_store(&audioDone, true);
                    [ain markAsFinished];
                    dispatch_group_leave(group);
                    return;
                }
                [ain appendSampleBuffer:sb];
                CFRelease(sb);
            }
        }];
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    [reader cancelReading];

    if (self.cancelled) { [writer cancelWriting]; return @"Cancelled."; }
    if (videoErr) { [writer cancelWriting]; return videoErr; }

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) return writer.error.localizedDescription ?: @"Couldn't finish the converted video.";
    return nil;
}

@end
