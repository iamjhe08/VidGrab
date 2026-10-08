#import "VGSubtitles.h"
#import <AVFoundation/AVFoundation.h>
#include <math.h>
#include "whisper.h"

NSString *const VGSubtitleModelDidChange = @"VGSubtitleModelDidChange";

static NSString *const kEnabledKey = @"vgSubsEnabled";
static NSString *const kQualityKey = @"vgSubsQuality";
static NSString *const kStartOnKey = @"vgSubsStartOn";

static NSString *const kModelBase = @"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/";

// The speech models are OpenAI's Whisper, converted for whisper.cpp (MIT license) and shrunk (q5_1).
static NSArray<NSDictionary *> *Models(void) {
    return @[
        @{@"name": @"Fast",     @"file": @"ggml-tiny-q5_1.bin", @"mb": @32,  @"min": @30000000,
          @"hint": @"Quickest, but less accurate. The best choice for older phones."},
        @{@"name": @"Balanced", @"file": @"ggml-base-q5_1.bin", @"mb": @60,  @"min": @55000000,
          @"hint": @"A good mix of speed and accuracy."},
        @{@"name": @"Best",     @"file": @"ggml-small-q5_1.bin", @"mb": @190, @"min": @180000000,
          @"hint": @"Most accurate. Needs a recent phone, and uses more battery."},
    ];
}

static NSString *SupportDir(NSString *sub) {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [[base stringByAppendingPathComponent:@"VidGrab"] stringByAppendingPathComponent:sub];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

#pragma mark - Model download

@interface VGModelDownloader : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic) VGSubtitleQuality quality;
@property (atomic) double progress;
@property (atomic, copy) NSString *error;
@property (nonatomic) NSInteger lastPercent;
+ (instancetype)shared;
@end

static void PostModelChange(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:VGSubtitleModelDidChange object:nil]; });
}

@implementation VGModelDownloader

+ (instancetype)shared {
    static VGModelDownloader *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [VGModelDownloader new]; });
    return d;
}

- (void)start:(VGSubtitleQuality)quality {
    if (self.task) return;
    self.quality = quality;
    self.progress = 0;
    self.error = nil;
    self.lastPercent = -1;
    if (!self.session)
        self.session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration delegate:self delegateQueue:nil];
    NSURL *url = [NSURL URLWithString:[kModelBase stringByAppendingString:Models()[quality][@"file"]]];
    self.task = [self.session downloadTaskWithURL:url];
    [self.task resume];
    PostModelChange();
}

- (void)cancel {
    NSURLSessionDownloadTask *t = self.task;
    self.task = nil;
    self.error = nil;
    [t cancel];
    PostModelChange();
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t didWriteData:(int64_t)n
 totalBytesWritten:(int64_t)written totalBytesExpectedToWrite:(int64_t)total {
    double expected = total > 0 ? (double)total : [Models()[self.quality][@"min"] doubleValue];
    self.progress = MIN(1, (double)written / expected);
    NSInteger pct = (NSInteger)(self.progress * 100);
    if (pct != self.lastPercent) { self.lastPercent = pct; PostModelChange(); }
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t didFinishDownloadingToURL:(NSURL *)location {
    NSHTTPURLResponse *resp = (NSHTTPURLResponse *)t.response;
    NSString *dest = [VGSubtitles pathFor:self.quality];
    NSFileManager *fm = NSFileManager.defaultManager;
    long long size = [[fm attributesOfItemAtPath:location.path error:nil][NSFileSize] longLongValue];
    if ([resp isKindOfClass:NSHTTPURLResponse.class] && resp.statusCode != 200) {
        self.error = [NSString stringWithFormat:@"The server said no (%ld). Try again later.", (long)resp.statusCode];
    } else if (size < [Models()[self.quality][@"min"] longLongValue]) {
        self.error = @"The download was cut short. Try again.";
    } else {
        [fm removeItemAtPath:dest error:nil];
        NSError *err = nil;
        if ([fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:dest] error:&err]) {
            [[NSURL fileURLWithPath:dest] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        } else {
            self.error = err.localizedDescription ?: @"Couldn't save the model.";
        }
    }
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)error {
    if (error && error.code != NSURLErrorCancelled) {
        self.error = error.code == NSURLErrorNotConnectedToInternet ? @"No internet connection." : error.localizedDescription;
    }
    self.task = nil;
    self.progress = 0;
    PostModelChange();
}

@end

#pragma mark - Settings and models

@implementation VGSubtitles

+ (BOOL)enabled { return [NSUserDefaults.standardUserDefaults boolForKey:kEnabledKey]; }
+ (void)setEnabled:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:kEnabledKey]; }

+ (VGSubtitleQuality)quality {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSInteger q = [d objectForKey:kQualityKey] ? [d integerForKey:kQualityKey] : VGSubtitleBalanced;
    return (VGSubtitleQuality)MIN(MAX(q, 0), (NSInteger)Models().count - 1);
}
+ (void)setQuality:(VGSubtitleQuality)q { [NSUserDefaults.standardUserDefaults setInteger:q forKey:kQualityKey]; }

+ (BOOL)startOn { return [NSUserDefaults.standardUserDefaults boolForKey:kStartOnKey]; }
+ (void)setStartOn:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:kStartOnKey]; }

+ (NSString *)nameFor:(VGSubtitleQuality)q { return Models()[q][@"name"]; }
+ (NSInteger)megabytesFor:(VGSubtitleQuality)q { return [Models()[q][@"mb"] integerValue]; }
+ (NSString *)detailFor:(VGSubtitleQuality)q {
    return [NSString stringWithFormat:@"About %ld MB. %@", (long)[self megabytesFor:q], Models()[q][@"hint"]];
}

+ (NSString *)pathFor:(VGSubtitleQuality)q { return [SupportDir(@"models") stringByAppendingPathComponent:Models()[q][@"file"]]; }

+ (BOOL)modelReady:(VGSubtitleQuality)q {
    long long size = [[[NSFileManager.defaultManager attributesOfItemAtPath:[self pathFor:q] error:nil] objectForKey:NSFileSize] longLongValue];
    return size >= [Models()[q][@"min"] longLongValue];
}
+ (BOOL)currentModelReady { return [self modelReady:self.quality]; }

+ (BOOL)downloading { return VGModelDownloader.shared.task != nil; }
+ (double)downloadProgress { return VGModelDownloader.shared.progress; }
+ (NSString *)lastError { return VGModelDownloader.shared.error; }

+ (void)downloadModel:(VGSubtitleQuality)q { [VGModelDownloader.shared start:q]; }
+ (void)cancelDownload { [VGModelDownloader.shared cancel]; }

+ (void)deleteModel:(VGSubtitleQuality)q {
    [NSFileManager.defaultManager removeItemAtPath:[self pathFor:q] error:nil];
    PostModelChange();
}

@end

#pragma mark - Engine

static const double kWindow = 30;   // seconds of sound per piece (what Whisper takes at a time)
static const double kAhead = 75;    // how far ahead of the playhead to stay

@interface VGSubtitleEngine ()
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, copy) NSString *key;
@property (nonatomic) VGSubtitleQuality quality;
@property (atomic) BOOL stopped;
@property (nonatomic) double playhead;
@property (atomic, copy) NSString *status;
@property (nonatomic) double duration;
@property (nonatomic, strong) NSMutableArray<NSArray *> *cues;   // @[start, end, text], sorted by start
@property (nonatomic, strong) NSMutableIndexSet *done;           // pieces already listened to
@property (nonatomic, strong) NSCondition *wake;
@property (nonatomic) NSInteger lastWindow;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

static bool VGAbortCallback(void *user) {
    VGSubtitleEngine *e = (__bridge VGSubtitleEngine *)user;
    return e.stopped;
}

@implementation VGSubtitleEngine

- (instancetype)initWithURL:(NSURL *)url key:(NSString *)key quality:(VGSubtitleQuality)quality {
    if ((self = [super init])) {
        _url = url;
        _key = key;
        _quality = quality;
        _cues = [NSMutableArray array];
        _done = [NSMutableIndexSet indexSet];
        _wake = [NSCondition new];
        _lastWindow = -1;
        _queue = dispatch_queue_create("com.t4mag0.vidgrab.subtitles", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        [self loadCache];
    }
    return self;
}

#pragma mark Saved lines

- (NSString *)cachePath {
    unsigned long h = 5381;
    for (const char *c = self.key.UTF8String; c && *c; c++) h = h * 33 + (unsigned char)*c;
    return [SupportDir(@"subtitles") stringByAppendingPathComponent:[NSString stringWithFormat:@"%lx-%ld.json", h, (long)self.quality]];
}

- (void)loadCache {
    NSData *d = [NSData dataWithContentsOfFile:[self cachePath]];
    NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    if (![j isKindOfClass:NSDictionary.class]) return;
    for (NSNumber *n in j[@"done"]) [self.done addIndex:n.unsignedIntegerValue];
    for (NSArray *c in j[@"cues"]) if (c.count == 3) [self.cues addObject:c];
}

- (void)saveCache {
    NSDictionary *j;
    @synchronized (self) {
        NSMutableArray *done = [NSMutableArray array];
        [self.done enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [done addObject:@(i)]; }];
        j = @{@"done": done, @"cues": [self.cues copy]};
    }
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:0 error:nil];
    [d writeToFile:[self cachePath] atomically:YES];
}

#pragma mark Control

- (void)start { dispatch_async(self.queue, ^{ [self run]; }); }

- (void)stop {
    self.stopped = YES;
    [self.wake lock]; [self.wake broadcast]; [self.wake unlock];
}

- (void)setPlayhead:(double)seconds {
    _playhead = seconds;
    NSInteger w = (NSInteger)floor(MAX(seconds, 0) / kWindow);
    if (w != self.lastWindow) {
        self.lastWindow = w;
        [self.wake lock]; [self.wake signal]; [self.wake unlock];
    }
}

- (void)waitFor:(NSTimeInterval)seconds {
    [self.wake lock];
    if (!self.stopped) [self.wake waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
    [self.wake unlock];
}

- (void)changed {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.onChange) self.onChange(); });
}

- (void)setStatusText:(NSString *)text {
    if ((text == nil && self.status == nil) || [text isEqualToString:self.status]) return;
    self.status = text;
    [self changed];
}

#pragma mark Lines

- (NSString *)textAt:(double)t {
    @synchronized (self) {
        NSInteger lo = 0, hi = (NSInteger)self.cues.count - 1, idx = -1;
        while (lo <= hi) {
            NSInteger mid = (lo + hi) / 2;
            if ([self.cues[mid][0] doubleValue] <= t) { idx = mid; lo = mid + 1; } else hi = mid - 1;
        }
        for (NSInteger i = idx; i >= 0 && i >= idx - 1; i--) {
            NSArray *c = self.cues[i];
            if (t < [c[1] doubleValue] + 0.15) return c[2];
        }
    }
    return nil;
}

- (void)insertCueStart:(double)start end:(double)end text:(NSString *)text {
    @synchronized (self) {
        NSInteger lo = 0, hi = (NSInteger)self.cues.count;
        while (lo < hi) {
            NSInteger mid = (lo + hi) / 2;
            if ([self.cues[mid][0] doubleValue] < start) lo = mid + 1; else hi = mid;
        }
        // The same line repeated again and again is the model stuck on silence or music: keep one.
        if (lo > 0) {
            NSArray *prev = self.cues[lo - 1];
            if ([[prev[2] lowercaseString] isEqualToString:text.lowercaseString] && start - [prev[1] doubleValue] < 3) {
                self.cues[lo - 1] = @[prev[0], @(MAX(end, [prev[1] doubleValue])), prev[2]];
                return;
            }
        }
        [self.cues insertObject:@[@(start), @(end), text] atIndex:lo];
    }
}

static BOOL IsNoiseTag(NSString *t) {
    NSString *l = t.lowercaseString;
    BOOL bracketed = ([l hasPrefix:@"["] && [l hasSuffix:@"]"]) || ([l hasPrefix:@"("] && [l hasSuffix:@")"]);
    return bracketed && ([l containsString:@"blank"] || [l containsString:@"silence"]);
}

#pragma mark Listening

// The next piece of the video, from the playhead on, that hasn't been listened to yet.
- (NSInteger)nextWindow {
    double p = MAX(self.playhead, 0);
    NSInteger first = (NSInteger)floor(p / kWindow);
    double limit = p + kAhead;
    if (self.duration > 0) limit = MIN(limit, self.duration);
    @synchronized (self) {
        for (NSInteger k = first; k * kWindow < limit; k++) if (![self.done containsIndex:(NSUInteger)k]) return k;
    }
    return -1;
}

// 16 kHz mono floats for one piece of the sound.
- (NSData *)readAudio:(AVAsset *)asset from:(double)start length:(double)length {
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!track) return nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
    if (!reader) return nil;
    reader.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(start, 600), CMTimeMakeWithSeconds(length, 600));
    NSDictionary *settings = @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVLinearPCMBitDepthKey: @32, AVLinearPCMIsFloatKey: @YES,
                               AVLinearPCMIsBigEndianKey: @NO, AVLinearPCMIsNonInterleaved: @NO, AVSampleRateKey: @16000, AVNumberOfChannelsKey: @1};
    AVAssetReaderTrackOutput *out = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:settings];
    out.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:out]) return nil;
    [reader addOutput:out];
    if (![reader startReading]) return nil;
    NSMutableData *data = [NSMutableData data];
    CMSampleBufferRef sb;
    while (!self.stopped && (sb = [out copyNextSampleBuffer])) {
        CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
        size_t n = bb ? CMBlockBufferGetDataLength(bb) : 0;
        if (n) {
            NSUInteger at = data.length;
            data.length = at + n;
            CMBlockBufferCopyDataBytes(bb, 0, n, (char *)data.mutableBytes + at);
        }
        CFRelease(sb);
    }
    if (reader.status == AVAssetReaderStatusReading) [reader cancelReading];
    return data;
}

- (void)processWindow:(NSInteger)k context:(struct whisper_context *)ctx asset:(AVAsset *)asset {
    double start = k * kWindow;
    double length = self.duration > 0 ? MIN(kWindow, self.duration - start) : kWindow;
    NSData *pcm = length > 0.3 ? [self readAudio:asset from:start length:length] : nil;
    if (self.stopped) return;
    NSUInteger n = pcm.length / sizeof(float);
    const float *samples = (const float *)pcm.bytes;

    // Almost no sound: skip it. It saves battery, and Whisper makes things up on silence.
    BOOL quiet = YES;
    if (n >= 16000) {
        double sum = 0; float peak = 0;
        for (NSUInteger i = 0; i < n; i += 4) { float v = samples[i]; sum += (double)v * v; peak = MAX(peak, fabsf(v)); }
        double rms = sqrt(sum / ((n + 3) / 4));
        quiet = rms < 0.003 || peak < 0.02;
    }

    if (!quiet) {
        struct whisper_full_params wp = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        wp.print_progress = wp.print_special = wp.print_realtime = wp.print_timestamps = false;
        wp.translate = true;            // whatever is spoken, write it in English
        wp.language = "auto";           // find the spoken language on its own
        wp.detect_language = false;
        wp.no_context = true;           // don't let one piece's guesses leak into the next
        wp.single_segment = false;
        wp.suppress_blank = true;
        wp.suppress_non_speech_tokens = true;
        wp.temperature_inc = 0.0f;      // no slow second tries
        wp.greedy.best_of = 1;
        wp.token_timestamps = false;
        NSInteger cpus = NSProcessInfo.processInfo.activeProcessorCount;
        wp.n_threads = (int)MAX(1, MIN(4, cpus - 1));
        wp.abort_callback = VGAbortCallback;
        wp.abort_callback_user_data = (__bridge void *)self;

        int rc = whisper_full(ctx, wp, samples, (int)n);
        if (self.stopped) return;   // closed while working: don't count this piece as done
        if (rc == 0) {
            int count = whisper_full_n_segments(ctx);
            for (int i = 0; i < count; i++) {
                const char *raw = whisper_full_get_segment_text(ctx, i);
                NSString *text = raw ? [NSString stringWithUTF8String:raw] : nil;
                text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (!text.length || IsNoiseTag(text)) continue;
                double t0 = start + whisper_full_get_segment_t0(ctx, i) * 0.01;
                double t1 = start + whisper_full_get_segment_t1(ctx, i) * 0.01;
                if (t1 < t0 + 0.8) t1 = t0 + 0.8;
                [self insertCueStart:t0 end:t1 text:text];
            }
        }
    }
    @synchronized (self) { [self.done addIndex:(NSUInteger)k]; }
    [self saveCache];
    [self changed];
}

- (void)run {
    @autoreleasepool {
        [self setStatusText:@"Loading subtitles…"];
        NSString *path = [VGSubtitles pathFor:self.quality];
        struct whisper_context_params cp = whisper_context_default_params();
        cp.use_gpu = false;
        struct whisper_context *ctx = [VGSubtitles modelReady:self.quality] ? whisper_init_from_file_with_params(path.fileSystemRepresentation, cp) : NULL;
        if (!ctx) {
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];   // damaged: download it again
            [self setStatusText:@"Couldn't load the subtitle model. Download it again in Settings."];
            PostModelChange();
            return;
        }
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:self.url options:nil];
        double d = CMTimeGetSeconds(asset.duration);
        self.duration = isfinite(d) && d > 0 ? d : 0;

        while (!self.stopped) {
            NSInteger k = [self nextWindow];
            if (k < 0) { [self setStatusText:nil]; [self waitFor:1.0]; continue; }
            if (NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious) {
                [self setStatusText:@"Subtitles paused while the phone cools down"];
                [self waitFor:4.0];
                continue;
            }
            // Only say so when the video is actually waiting for this piece.
            BOOL waiting = k == (NSInteger)floor(MAX(self.playhead, 0) / kWindow);
            [self setStatusText:waiting ? @"Making subtitles…" : nil];
            @autoreleasepool { [self processWindow:k context:ctx asset:asset]; }
        }
        whisper_free(ctx);
    }
}

@end
