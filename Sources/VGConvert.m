#import "VGConvert.h"
#include "vgconvert.h"

@interface VGConvert ()
@property (atomic) BOOL cancelled;
@property (atomic) CFAbsoluteTime lastProgress;
@property (nonatomic, copy, nullable) void (^progressBlock)(double);
@end

static int cancel_cb(void *ctx) {
    VGConvert *c = (__bridge VGConvert *)ctx;
    return c.cancelled ? 1 : 0;
}

static void progress_cb(void *ctx, double f) {
    VGConvert *c = (__bridge VGConvert *)ctx;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (f < 1.0 && now - c.lastProgress < 0.25) return;  // a few updates per second is plenty
    c.lastProgress = now;
    void (^p)(double) = c.progressBlock;
    if (p) dispatch_async(dispatch_get_main_queue(), ^{ p(f); });
}

@implementation VGConvert

+ (NSDictionary<NSString *, NSString *> *)probe:(NSString *)path {
    VGProbe p;
    if (vg_probe(path.fileSystemRepresentation, &p) != VG_OK) return @{@"video": @"", @"audio": @"", @"container": @""};
    return @{@"video": @(p.video), @"audio": @(p.audio), @"container": @(p.container),
             @"width": [NSString stringWithFormat:@"%d", p.width], @"height": [NSString stringWithFormat:@"%d", p.height],
             @"duration": [NSString stringWithFormat:@"%.1f", p.duration]};
}

+ (NSString *)describe:(NSString *)path {
    char buf[2048];
    vg_describe(path.fileSystemRepresentation, buf, sizeof buf);
    return @(buf);
}

+ (NSDictionary<NSString *, id> *)tsScan:(NSString *)path {
    char buf[2048];
    long scrambled = 0;
    int isTS = 0;
    vg_ts_scan(path.fileSystemRepresentation, buf, sizeof buf, &scrambled, &isTS);
    return @{@"text": @(buf), @"scrambled": @(scrambled), @"isTS": @(isTS)};
}

+ (NSDictionary<NSString *, id> *)tsClean:(NSString *)path to:(NSString *)output {
    long long junk = 0;
    long pieces = 0;
    int needed = 0;
    char err[256] = "";
    int r = vg_ts_clean(path.fileSystemRepresentation, NULL, &junk, &pieces, &needed, NULL, NULL, NULL, err, sizeof err);
    if (r != VG_OK || !needed) return nil;
    r = vg_ts_clean(path.fileSystemRepresentation, output.fileSystemRepresentation, &junk, &pieces, &needed, NULL, NULL, NULL, err, sizeof err);
    if (r != VG_OK) return @{@"error": err[0] ? @(err) : @"clean failed", @"junk": @0, @"pieces": @0};
    return @{@"path": output, @"junk": @(junk), @"pieces": @(pieces)};
}

- (void)cancel { self.cancelled = YES; }

- (void)run:(int (^)(char *err, size_t n))work completion:(void (^)(NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char err[512] = "";
        int r = work(err, sizeof err);
        NSString *msg = nil;
        if (r == VG_CANCELLED) msg = @"Cancelled.";
        else if (r != VG_OK) msg = err[0] ? @(err) : @"Conversion failed.";
        dispatch_async(dispatch_get_main_queue(), ^{ completion(msg); });
    });
}

- (void)remux:(NSString *)input to:(NSString *)output progress:(void (^)(double))progress completion:(void (^)(NSString *))completion {
    self.progressBlock = progress;
    void *ctx = (__bridge void *)self;
    const char *in = strdup(input.fileSystemRepresentation), *out = strdup(output.fileSystemRepresentation);
    [self run:^int(char *err, size_t n) {
        int r = vg_remux_mp4(in, out, progress_cb, cancel_cb, ctx, err, n);
        free((void *)in);
        free((void *)out);
        return r;
    } completion:completion];
}

- (void)mux:(NSString *)video audio:(NSString *)audio to:(NSString *)output progress:(void (^)(double))progress
 completion:(void (^)(NSString *, NSDictionary<NSString *, id> *))completion {
    self.progressBlock = progress;
    void *ctx = (__bridge void *)self;
    const char *v = strdup(video.fileSystemRepresentation), *out = strdup(output.fileSystemRepresentation);
    const char *a = audio.length ? strdup(audio.fileSystemRepresentation) : NULL;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char err[512] = "", verr[512] = "", summary[256] = "";
        VGMuxInfo mi;
        int r = vg_mux_mp4_ex(v, a, out, &mi, progress_cb, cancel_cb, ctx, err, sizeof err);
        NSString *msg = nil;
        NSString *validation = @"not run";
        if (r == VG_CANCELLED) msg = @"Cancelled.";
        else if (r != VG_OK) msg = err[0] ? @(err) : @"Conversion failed.";
        else {
            // Making the file isn't enough: it is only good if it opens, starts on a keyframe and decodes.
            int vr = vg_validate_mp4(out, mi.expectedDuration, mi.hadAudio, summary, sizeof summary, verr, sizeof verr);
            if (vr == VG_OK) validation = [NSString stringWithFormat:@"OK (%s)", summary];
            else {
                msg = verr[0] ? @(verr) : @"The converted file failed its check.";
                validation = [@"failed: " stringByAppendingString:msg];
                remove(out);
            }
        }
        NSDictionary *info = @{@"strategy": @(mi.strategy), @"validation": validation, @"expectedDuration": @(mi.expectedDuration),
                               @"discontinuities": @(mi.discontinuities), @"leadingDropped": @(mi.leadingDropped),
                               @"videoIn": @(mi.videoIn), @"videoOut": @(mi.videoOut), @"videoLost": @(mi.videoLost),
                               @"hadAudio": @(mi.hadAudio), @"audioCodec": @(mi.audioIn), @"gapSeconds": @(mi.gapSeconds), @"width": @(mi.width), @"height": @(mi.height)};
        free((void *)v); free((void *)out); if (a) free((void *)a);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(msg, info); });
    });
}

- (void)merge:(NSString *)video audio:(NSString *)audio to:(NSString *)output progress:(void (^)(double))progress completion:(void (^)(NSString *))completion {
    self.progressBlock = progress;
    void *ctx = (__bridge void *)self;
    const char *v = strdup(video.fileSystemRepresentation), *a = strdup(audio.fileSystemRepresentation), *out = strdup(output.fileSystemRepresentation);
    [self run:^int(char *err, size_t n) {
        int r = vg_mux_mp4(v, a, out, progress_cb, cancel_cb, ctx, err, n);
        free((void *)v); free((void *)a); free((void *)out);
        return r;
    } completion:completion];
}

- (void)audio:(NSString *)input to:(NSString *)output mp3:(BOOL)mp3 title:(NSString *)title artist:(NSString *)artist
     progress:(void (^)(double))progress completion:(void (^)(NSString *))completion {
    self.progressBlock = progress;
    void *ctx = (__bridge void *)self;
    const char *in = strdup(input.fileSystemRepresentation), *out = strdup(output.fileSystemRepresentation);
    const char *t = strdup(title.UTF8String ?: ""), *a = strdup(artist.UTF8String ?: "");
    [self run:^int(char *err, size_t n) {
        int r = vg_audio(in, out, mp3 ? 1 : 0, mp3 ? 256000 : 192000, t, a, progress_cb, cancel_cb, ctx, err, n);
        free((void *)in); free((void *)out); free((void *)t); free((void *)a);
        return r;
    } completion:completion];
}

@end
