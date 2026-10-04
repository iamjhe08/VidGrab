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
    return @{@"video": @(p.video), @"audio": @(p.audio), @"container": @(p.container)};
}

+ (NSString *)describe:(NSString *)path {
    char buf[2048];
    vg_describe(path.fileSystemRepresentation, buf, sizeof buf);
    return @(buf);
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
