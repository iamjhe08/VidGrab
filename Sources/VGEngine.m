#import "VGEngine.h"
#import <objc/runtime.h>
#import "VGPython.h"
#import <AVFoundation/AVFoundation.h>
#import "VGTranscoder.h"
#import "VGConvert.h"
#import "VGCrash.h"
#import <WebKit/WebKit.h>

NSString *const VGLibraryDidChangeNotification = @"VGLibraryDidChangeNotification";
NSString *const VGTasksDidChangeNotification = @"VGTasksDidChangeNotification";
NSString *const VGTaskFinishedNotification = @"VGTaskFinishedNotification";

@implementation VGOption
@end

@implementation VGVideo
@end

@interface VGTask ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, strong) VGVideo *video;
@property (nonatomic, readwrite, strong) VGOption *option;
@property (nonatomic, readwrite) VGTaskState state;
@property (nonatomic, readwrite) double fraction;
@property (nonatomic, readwrite, copy) NSString *stage;
@property (nonatomic, readwrite, copy) NSString *detail;
@property (nonatomic, readwrite, copy, nullable) NSString *error;
@property (nonatomic, readwrite, strong, nullable) VGItem *item;
@property (nonatomic, strong, nullable) AVAssetExportSession *export;
@property (nonatomic, strong, nullable) VGTranscoder *transcoder;
@property (nonatomic, strong, nullable) VGConvert *converter;
@property (nonatomic) CFAbsoluteTime lastPost;
@end

@implementation VGTask
@end

static NSString *documentsDir(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

static NSString *supportPath(NSString *name) {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"library"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:name];
}

#pragma mark - Item

@implementation VGItem

- (NSURL *)fileURL {
    return [NSURL fileURLWithPath:[documentsDir() stringByAppendingPathComponent:self.fileName]];
}

- (NSString *)thumbPath {
    return supportPath([[self.fileName stringByDeletingPathExtension] stringByAppendingString:@".thumb.jpg"]);
}

- (UIImage *)thumbnailImage {
    return [UIImage imageWithContentsOfFile:[self thumbPath]];
}

- (NSDictionary *)dict {
    return @{@"file": self.fileName, @"title": self.title, @"site": self.site ?: @"", @"res": self.res ?: @"",
             @"duration": @(self.duration), @"bytes": @(self.bytes), @"audio": @(self.audio),
             @"photos": @(self.photos), @"date": @(self.date.timeIntervalSince1970)};
}

+ (instancetype)fromDict:(NSDictionary *)d {
    VGItem *i = [VGItem new];
    i.fileName = d[@"file"];
    i.title = d[@"title"] ?: i.fileName;
    i.site = [d[@"site"] length] ? d[@"site"] : nil;
    i.res = d[@"res"] ?: @"";
    i.duration = [d[@"duration"] doubleValue];
    i.bytes = [d[@"bytes"] longLongValue];
    i.audio = [d[@"audio"] boolValue];
    i.photos = [d[@"photos"] boolValue];
    i.date = [NSDate dateWithTimeIntervalSince1970:[d[@"date"] doubleValue]];
    return i;
}

@end

#pragma mark - Engine

@interface VGEngine ()
@property (nonatomic, strong) NSMutableArray<VGItem *> *library;
@property (nonatomic, strong) NSMutableArray<VGTask *> *queue;
@property (nonatomic) NSUInteger nextTaskID;
@property (nonatomic, strong) NSMutableString *convLog;   // recent conversion steps, for Copy details
@property (nonatomic) NSUInteger heavyRunning;             // re-encodes in progress (they share the phone's video encoder)
@property (nonatomic, strong) NSMutableArray *heavyWaiting;
@end

@implementation VGEngine

+ (instancetype)shared {
    static VGEngine *e;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [VGEngine new]; });
    return e;
}

- (void)start {
    [self loadLibrary];
    [[VGPython shared] start];
    // Clear temp work folders from earlier runs.
    NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:@"work"];
    [NSFileManager.defaultManager removeItemAtPath:work error:nil];
}

- (NSString *)engineVersion { return [VGPython shared].engineVersion ?: @"starting…"; }

#pragma mark Library

- (NSArray<VGItem *> *)items { return [self.library copy]; }

- (void)loadLibrary {
    self.library = [NSMutableArray array];
    NSData *d = [NSData dataWithContentsOfFile:supportPath(@"library.json")];
    NSArray *arr = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSDictionary *x in ([arr isKindOfClass:NSArray.class] ? arr : @[])) {
        VGItem *i = [VGItem fromDict:x];
        // Drop entries whose files were removed in the Files app.
        if (i.fileName && [fm fileExistsAtPath:i.fileURL.path]) [self.library addObject:i];
    }
}

- (void)saveLibrary {
    NSMutableArray *arr = [NSMutableArray array];
    for (VGItem *i in self.library) [arr addObject:[i dict]];
    [[NSJSONSerialization dataWithJSONObject:arr options:0 error:nil] writeToFile:supportPath(@"library.json") atomically:YES];
    [NSNotificationCenter.defaultCenter postNotificationName:VGLibraryDidChangeNotification object:nil];
}

- (void)deleteItem:(VGItem *)item {
    [NSFileManager.defaultManager removeItemAtURL:item.fileURL error:nil];
    [NSFileManager.defaultManager removeItemAtPath:[item thumbPath] error:nil];
    [self.library removeObject:item];
    [self saveLibrary];
}

- (long long)totalBytes {
    long long t = 0;
    for (VGItem *i in self.library) t += i.bytes;
    return t;
}

#pragma mark Cookies

static NSString *baseDomain(NSString *host) {
    host = host.lowercaseString;
    if ([host isEqualToString:@"youtu.be"] || [host hasSuffix:@".youtu.be"]) return @"youtube.com";
    NSArray *parts = [host componentsSeparatedByString:@"."];
    if (parts.count <= 2) return host;
    NSString *last2 = [[parts subarrayWithRange:NSMakeRange(parts.count - 2, 2)] componentsJoinedByString:@"."];
    // Handle two-part country suffixes like co.uk, com.ph.
    NSSet *second = [NSSet setWithArray:@[@"co", @"com", @"net", @"org", @"gov", @"edu", @"ac"]];
    if ([second containsObject:parts[parts.count - 2]] && parts.count >= 3) {
        return [[parts subarrayWithRange:NSMakeRange(parts.count - 3, 3)] componentsJoinedByString:@"."];
    }
    return last2;
}

/// Writes the browser's cookies for this link's site to a Netscape cookie file for the engine.
- (void)cookiesFor:(NSString *)url completion:(void (^)(NSString *path))completion {
    NSString *host = [NSURL URLWithString:url].host;
    if (!host) { completion(@""); return; }
    NSString *domain = baseDomain(host);
    dispatch_async(dispatch_get_main_queue(), ^{
        [WKWebsiteDataStore.defaultDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
            NSMutableString *out = [NSMutableString stringWithString:@"# Netscape HTTP Cookie File\n"];
            NSUInteger n = 0;
            for (NSHTTPCookie *c in cookies) {
                NSString *d = c.domain.lowercaseString;
                NSString *bare = [d hasPrefix:@"."] ? [d substringFromIndex:1] : d;
                if (!([bare isEqualToString:domain] || [bare hasSuffix:[@"." stringByAppendingString:domain]])) continue;
                long long exp = c.expiresDate ? (long long)c.expiresDate.timeIntervalSince1970 : 0;
                [out appendFormat:@"%@\t%@\t%@\t%@\t%lld\t%@\t%@\n", d, [d hasPrefix:@"."] ? @"TRUE" : @"FALSE",
                    c.path ?: @"/", c.isSecure ? @"TRUE" : @"FALSE", exp, c.name, c.value];
                n++;
            }
            if (!n) { completion(@""); return; }
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"cookies.txt"];
            [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            completion(path);
        }];
    });
}

#pragma mark Fetch

- (void)fetch:(NSString *)url completion:(void (^)(VGVideo *, NSString *))completion {
    [self cookiesFor:url completion:^(NSString *cookies) {
    [[VGPython shared] call:@"vgbridge" function:@"fetch" args:@[url, [VGPython shared].cacheDir, cookies]
                 completion:^(NSDictionary *r, NSString *error) {
        if (!r) { completion(nil, error); return; }
        VGVideo *v = [VGVideo new];
        v.url = url;
        v.title = r[@"title"] ?: @"Untitled video";
        v.uploader = [r[@"uploader"] isKindOfClass:NSString.class] ? r[@"uploader"] : nil;
        v.site = [r[@"site"] isKindOfClass:NSString.class] ? r[@"site"] : nil;
        v.thumbnail = [r[@"thumbnail"] isKindOfClass:NSString.class] ? r[@"thumbnail"] : nil;
        v.duration = [r[@"duration"] isKindOfClass:NSNumber.class] ? [r[@"duration"] doubleValue] : 0;
        NSMutableArray *opts = [NSMutableArray array];
        for (NSDictionary *o in r[@"options"]) {
            VGOption *x = [VGOption new];
            x.identifier = o[@"id"];
            x.res = o[@"res"] ?: @"";
            x.sizeText = o[@"size_text"] ?: @"";
            x.format = o[@"fmt"] ?: @"";
            x.photos = [o[@"photos"] boolValue];
            x.audio = [o[@"audio"] boolValue];
            x.convert = [o[@"convert"] boolValue];
            [opts addObject:x];
        }
        v.options = opts;
        completion(v, nil);
    }];
    }];
}

#pragma mark Download queue

static const NSUInteger kMaxRunning = 10;   // downloads at the same time
static const NSUInteger kMaxHeavy = 2;      // re-encodes at the same time

static NSString *formatSpeed(double bps) {
    if (bps <= 0) return nil;
    return [[NSByteCountFormatter stringFromByteCount:(long long)bps countStyle:NSByteCountFormatterCountStyleFile]
            stringByAppendingString:@"/s"];
}

static NSString *formatETA(double s) {
    if (s < 0) return nil;
    int t = (int)s;
    if (t >= 3600) return [NSString stringWithFormat:@"%d:%02d:%02d left", t / 3600, t / 60 % 60, t % 60];
    return [NSString stringWithFormat:@"%d:%02d left", t / 60, t % 60];
}

- (NSArray<VGTask *> *)tasks { return [self.queue copy] ?: @[]; }

- (NSUInteger)activeCount {
    NSUInteger n = 0;
    for (VGTask *t in self.queue) if (t.state == VGTaskQueued || t.state == VGTaskRunning) n++;
    return n;
}

- (VGTask *)leadTask {
    for (VGTask *t in self.queue) if (t.state == VGTaskRunning) return t;
    for (VGTask *t in self.queue) if (t.state == VGTaskQueued) return t;
    return nil;
}

- (void)post:(VGTask *)task force:(BOOL)force {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!force && task && now - task.lastPost < 0.2) return;  // keep the UI smooth
    task.lastPost = now;
    [NSNotificationCenter.defaultCenter postNotificationName:VGTasksDidChangeNotification object:task];
}

- (void)update:(VGTask *)task fraction:(double)f stage:(NSString *)stage detail:(NSString *)detail {
    task.fraction = MAX(0, MIN(1, f));
    if (stage) task.stage = stage;
    if (detail) task.detail = detail;
    if (task.progressHandler) task.progressHandler(task.fraction, task.stage, task.detail);
    [self post:task force:NO];
}

- (VGTask *)download:(VGVideo *)video option:(VGOption *)option progress:(VGProgress)progress
          completion:(void (^)(VGItem *, NSString *))completion {
    if (!self.queue) self.queue = [NSMutableArray array];
    VGTask *t = [VGTask new];
    t.identifier = [NSString stringWithFormat:@"t%lu", (unsigned long)++self.nextTaskID];
    t.video = video;
    t.option = option;
    t.state = VGTaskQueued;
    t.stage = @"Waiting…";
    t.detail = [NSString stringWithFormat:@"%@ · %@", option.res, option.sizeText.length ? option.sizeText : option.format];
    t.progressHandler = progress;
    t.completionHandler = completion;
    [self.queue addObject:t];
    [self post:t force:YES];
    [self pump];
    return t;
}

- (void)pump {
    NSUInteger running = 0;
    for (VGTask *t in self.queue) if (t.state == VGTaskRunning) running++;
    for (VGTask *t in self.queue) {
        if (running >= kMaxRunning) break;
        if (t.state != VGTaskQueued) continue;
        running++;
        [self run:t];
    }
    UIApplication.sharedApplication.idleTimerDisabled = self.activeCount > 0;
}

- (void)cancelTask:(VGTask *)task {
    if (task.state == VGTaskQueued) {
        [self finish:task item:nil error:@"Cancelled." work:nil];
        return;
    }
    [[VGPython shared] cancelTask:task.identifier];
    [self dropWaitingHeavy:task];
    [task.export cancelExport];
    [task.transcoder cancel];
    [task.converter cancel];
}

- (void)retryTask:(VGTask *)task {
    if (task.state != VGTaskFailed) return;
    task.state = VGTaskQueued;
    task.error = nil;
    task.fraction = 0;
    task.stage = @"Waiting…";
    [self post:task force:YES];
    [self pump];
}

- (void)dismissTask:(VGTask *)task {
    if (task.state == VGTaskQueued || task.state == VGTaskRunning) return;
    [self.queue removeObject:task];
    [self post:nil force:YES];
}

- (void)finish:(VGTask *)task item:(VGItem *)item error:(NSString *)err work:(NSString *)work {
    [[VGPython shared] forgetTask:task.identifier];
    if (work) [NSFileManager.defaultManager removeItemAtPath:work error:nil];
    task.export = nil;
    task.transcoder = nil;
    task.converter = nil;
    task.item = item;
    task.error = err;
    if (item) task.state = VGTaskDone;
    else if ([err isEqualToString:@"Cancelled."]) task.state = VGTaskCancelled;
    else task.state = VGTaskFailed;
    if (task.state != VGTaskFailed) [self.queue removeObject:task];  // failed ones stay so they can be retried
    if (task.completionHandler) task.completionHandler(item, err);
    [NSNotificationCenter.defaultCenter postNotificationName:VGTaskFinishedNotification object:task];
    [self post:task force:YES];
    [self pump];
}

- (void)run:(VGTask *)task {
    task.state = VGTaskRunning;
    task.stage = @"Starting…";
    [self post:task force:YES];
    VGPython *py = [VGPython shared];
    VGVideo *video = task.video;
    VGOption *option = task.option;
    BOOL heavy = option.convert;
    double share = heavy ? 0.45 : (option.audio ? 0.7 : 0.9);  // part of the bar used by the download itself

    NSString *work = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"work"] stringByAppendingPathComponent:task.identifier];
    [NSFileManager.defaultManager removeItemAtPath:work error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];

    __weak typeof(self) ws = self;
    [py setProgressHandler:^(int part, int parts, double frac, NSString *stage, double speed, double eta) {
        if ([stage isEqualToString:@"retry"]) {
            [ws update:task fraction:0 stage:@"YouTube blocked it, trying another way…" detail:@"This can take a few extra seconds"];
            return;
        }
        double overall = parts > 1 ? (part + frac) / parts : frac;
        NSString *what = [stage isEqualToString:@"audio"] ? @"Downloading audio" : @"Downloading video";
        if (parts > 1) what = [what stringByAppendingFormat:@" (%d of %d)", part + 1, parts];
        NSMutableArray *bits = [NSMutableArray array];
        if (formatSpeed(speed)) [bits addObject:formatSpeed(speed)];
        if (formatETA(eta)) [bits addObject:formatETA(eta)];
        [ws update:task fraction:overall * share stage:what detail:[bits componentsJoinedByString:@" · "]];
    } forTask:task.identifier];

    [self cookiesFor:video.url completion:^(NSString *cookies) {
        [py call:@"vgbridge" function:@"download" args:@[task.identifier, video.url, option.identifier, work, py.cacheDir, cookies]
      completion:^(NSDictionary *r, NSString *error) {
            if (!r) { [ws finish:task item:nil error:error work:work]; return; }
            [ws postProcess:task result:r work:work share:share];
        }];
    }];
}

/// Re-encoding uses the phone's video encoder, which only handles a couple of jobs well at once.
/// Extra jobs wait their turn; call heavyDone when finished.
- (void)heavy:(VGTask *)task work:(void (^)(void))work {
    if (!self.heavyWaiting) self.heavyWaiting = [NSMutableArray array];
    if (self.heavyRunning < kMaxHeavy) { self.heavyRunning++; work(); }
    else [self.heavyWaiting addObject:@[task, [work copy]]];
}

- (void)heavyDone {
    if (self.heavyRunning) self.heavyRunning--;
    if (self.heavyWaiting.count && self.heavyRunning < kMaxHeavy) {
        void (^next)(void) = self.heavyWaiting.firstObject[1];
        [self.heavyWaiting removeObjectAtIndex:0];
        self.heavyRunning++;
        next();
    }
}

/// A cancelled task that is still waiting for its turn to convert: let it finish right away.
- (void)dropWaitingHeavy:(VGTask *)task {
    for (NSArray *e in [self.heavyWaiting copy]) {
        if (e[0] != task) continue;
        [self.heavyWaiting removeObject:e];
        self.heavyRunning++;          // the block calls heavyDone itself
        ((void (^)(void))e[1])();
    }
}

- (NSString *)uniqueName:(NSString *)base ext:(NSString *)ext {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *name = [NSString stringWithFormat:@"%@.%@", base, ext];
    for (int n = 2; [fm fileExistsAtPath:[documentsDir() stringByAppendingPathComponent:name]]; n++) {
        name = [NSString stringWithFormat:@"%@ (%d).%@", base, n, ext];
    }
    return name;
}


#pragma mark Checking converted videos

- (void)note:(NSString *)line {
    if (!self.convLog) self.convLog = [NSMutableString string];
    [self.convLog appendFormat:@"%@ %@\n", [NSDate date], line];
    if (self.convLog.length > 6000) [self.convLog deleteCharactersInRange:NSMakeRange(0, self.convLog.length - 6000)];
    [VGCrash breadcrumb:[@"convert: " stringByAppendingString:line]];
}

/// Average brightness (0-255) of an image, from a tiny downscaled copy.
static double brightness(CGImageRef img) {
    uint8_t px[16 * 16 * 4] = {0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(px, 16, 16, 8, 16 * 4, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!c) return 255;
    CGContextDrawImage(c, CGRectMake(0, 0, 16, 16), img);
    CGContextRelease(c);
    double sum = 0;
    for (int i = 0; i < 16 * 16; i++) sum += (px[i * 4] + px[i * 4 + 1] + px[i * 4 + 2]) / 3.0;
    return sum / (16 * 16);
}

/// Returns nil if the file plays as a real video on this iPhone, otherwise what's wrong.
- (NSString *)problemWithVideo:(NSString *)path checkBlack:(BOOL)checkBlack {
    AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetTrack *vt = [a tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!vt) return @"no video track";
    double secs = CMTimeGetSeconds(a.duration);
    if (!(secs > 0)) return @"zero length";
    if (!vt.isPlayable && !a.isPlayable) return @"iPhone can't play it";
    AVAssetImageGenerator *g = [AVAssetImageGenerator assetImageGeneratorWithAsset:a];
    g.appliesPreferredTrackTransform = YES;
    g.maximumSize = CGSizeMake(160, 160);
    g.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(2, 600);
    g.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(2, 600);
    int got = 0;
    double maxBright = 0;
    for (NSNumber *f in @[@0.15, @0.5, @0.85]) {
        NSError *e = nil;
        CGImageRef img = [g copyCGImageAtTime:CMTimeMakeWithSeconds(secs * f.doubleValue, 600) actualTime:NULL error:&e];
        if (!img) continue;
        got++;
        maxBright = MAX(maxBright, brightness(img));
        CGImageRelease(img);
    }
    if (!got) return @"no picture could be read";
    if (checkBlack && maxBright < 6) return [NSString stringWithFormat:@"picture is black (brightness %.1f)", maxBright];
    return nil;
}

- (void)verify:(NSString *)path black:(BOOL)black completion:(void (^)(NSString *problem))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *p = [self problemWithVideo:path checkBlack:black];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(p); });
    });
}

/// Turns the downloaded file(s) into the final MP4 / M4A / MP3 in Documents.
- (void)postProcess:(VGTask *)task result:(NSDictionary *)r work:(NSString *)work share:(double)share {
    NSArray<NSString *> *files = r[@"files"];
    NSString *kind = r[@"kind"];
    NSString *base = r[@"name"] ?: @"video";
    NSString *first = files.firstObject;
    VGVideo *video = task.video;
    VGOption *option = task.option;
    __weak typeof(self) ws = self;
    NSFileManager *fm = NSFileManager.defaultManager;

    void (^store)(NSString *, BOOL) = ^(NSString *path, BOOL photos) {
        if ([[VGPython shared] isTaskCancelled:task.identifier]) {
            [fm removeItemAtPath:path error:nil];
            [ws finish:task item:nil error:@"Cancelled." work:work];
            return;
        }
        VGItem *item = [VGItem new];
        item.fileName = path.lastPathComponent;
        item.title = video.title;
        item.site = video.site;
        item.res = option.res;
        item.duration = video.duration;
        item.audio = option.audio;
        item.photos = photos && !option.audio;
        item.date = [NSDate date];
        item.bytes = [[fm attributesOfItemAtPath:path error:nil][NSFileSize] longLongValue];
        [ws makeThumbnailFor:item fallbackURL:video.thumbnail];
        [ws.library insertObject:item atIndex:0];
        [ws saveLibrary];
        [ws finish:task item:item error:nil work:work];
    };
    void (^fail)(NSString *) = ^(NSString *err) { [ws finish:task item:nil error:err work:work]; };
    void (^keepOriginal)(void) = ^{
        NSString *c = [VGConvert probe:first][@"container"] ?: @"";
        NSString *ext = first.pathExtension.lowercaseString.length ? first.pathExtension.lowercaseString : @"mp4";
        if ([c isEqualToString:@"mpegts"]) ext = @"ts";
        else if ([c hasPrefix:@"matroska"]) ext = [ext isEqualToString:@"webm"] ? @"webm" : @"mkv";
        else if ([c isEqualToString:@"flv"]) ext = @"flv";
        NSString *dest = [documentsDir() stringByAppendingPathComponent:[ws uniqueName:base ext:ext]];
        NSError *e = nil;
        [fm moveItemAtPath:first toPath:dest error:&e];
        if (e) fail(e.localizedDescription); else store(dest, NO);
    };
    NSString *mp4 = [documentsDir() stringByAppendingPathComponent:[self uniqueName:base ext:@"mp4"]];
    void (^stageP)(NSString *) = ^(NSString *what) { [ws update:task fraction:share stage:what detail:@""]; };
    void (^(^convertProgress)(NSString *))(double) = ^(NSString *what) {
        return ^(double f) { [ws update:task fraction:share + f * (0.99 - share) stage:what detail:[NSString stringWithFormat:@"%d%% done", (int)(f * 100)]]; };
    };

    // VP9/VP8 → HEVC (needs an AAC track to copy; make one from the file's own sound if needed).
    void (^reencode)(NSString *, NSString *) = ^(NSString *videoPath, NSString *audioPath) {
        void (^go)(NSString *) = ^(NSString *aac) {
          if (ws.heavyRunning >= kMaxHeavy) [ws update:task fraction:share stage:@"Waiting to convert" detail:@"Other videos are converting"];
          [ws heavy:task work:^{
            if ([[VGPython shared] isTaskCancelled:task.identifier]) { [ws heavyDone]; fail(@"Cancelled."); return; }
            stageP(@"Converting for iPhone");
            task.transcoder = [VGTranscoder new];
            [task.transcoder convertVideo:[NSURL fileURLWithPath:videoPath] audio:aac ? [NSURL fileURLWithPath:aac] : nil to:[NSURL fileURLWithPath:mp4]
                                 progress:convertProgress(@"Converting for iPhone · keep the app open")
                               completion:^(NSString *err) {
                [ws heavyDone];
                if (err) { [ws note:[@"re-encode failed: " stringByAppendingString:err]]; fail(err); return; }
                stageP(@"Checking the video");
                [ws verify:mp4 black:YES completion:^(NSString *problem) {
                    if (!problem) { [ws note:@"re-encode ok"]; store(mp4, YES); return; }
                    [ws note:[@"re-encode check failed: " stringByAppendingString:problem]];
                    [fm removeItemAtPath:mp4 error:nil];
                    fail(@"This quality couldn't be converted on your iPhone (the picture came out blank). Please pick 1080p or lower, and tap Copy details to send the developer what happened.");
                }];
            }];
          }];
        };
        NSDictionary *pa = audioPath ? [VGConvert probe:audioPath] : [VGConvert probe:videoPath];
        NSString *src = audioPath ?: videoPath;
        if (![pa[@"audio"] length]) { go(nil); return; }
        if ([pa[@"audio"] isEqualToString:@"aac"] && audioPath) { go(audioPath); return; }
        NSString *aac = [work stringByAppendingPathComponent:@"sound.m4a"];
        stageP(@"Preparing sound");
        task.converter = [VGConvert new];
        [task.converter audio:src to:aac mp3:NO title:nil artist:nil progress:nil completion:^(NSString *err) {
            if (err) { fail(err); return; }
            go(aac);
        }];
    };

    // A video download that came out with no picture at all: say so instead of saving a black file.
    if (!option.audio && ![kind isEqualToString:@"mp3"] && ![kind isEqualToString:@"audio"] && first) {
        NSString *vfile = first;
        NSDictionary *vp = [VGConvert probe:vfile];
        if ([vp[@"container"] length] && ![vp[@"video"] length]) {   // only when FFmpeg could read the file
            [self note:[NSString stringWithFormat:@"no picture in %@ (%@):\n%@", vfile.lastPathComponent, vp[@"container"], [VGConvert describe:vfile]]];
            for (NSString *f in files) [fm removeItemAtPath:f error:nil];
            fail(@"This video came through with sound only, no picture. The site may lock its video so it can't be saved, or it sends picture and sound separately in a way VidGrab can't read yet. Try another quality, and tap Copy details to send the developer the link.");
            return;
        }
    }

    if ([kind isEqualToString:@"merge"] && files.count >= 2) {
        stageP(@"Joining video and sound");
        NSString *vPath = files[0], *aPath = files[1];
        void (^appleBackup)(NSString *) = ^(NSString *why) {
            [ws note:[@"join: FFmpeg route failed, trying Apple's: " stringByAppendingString:why]];
            [fm removeItemAtPath:mp4 error:nil];
            [ws mergeVideo:[NSURL fileURLWithPath:vPath] audio:[NSURL fileURLWithPath:aPath] to:[NSURL fileURLWithPath:mp4] task:task completion:^(NSString *err) {
                if (err) { [ws note:[@"join: Apple's route failed: " stringByAppendingString:err]]; fail(err); return; }
                [ws verify:mp4 black:NO completion:^(NSString *problem) {
                    if (!problem) { [ws note:@"join ok (Apple)"]; store(mp4, YES); return; }
                    [ws note:[@"join: Apple's result failed check: " stringByAppendingString:problem]];
                    [fm removeItemAtPath:mp4 error:nil];
                    fail(@"The video and sound couldn't be joined into a playable file. Tap Copy details and send them to the developer.");
                }];
            }];
        };
        task.converter = [VGConvert new];
        [task.converter merge:vPath audio:aPath to:mp4 progress:convertProgress(@"Joining video and sound") completion:^(NSString *err) {
            if ([err isEqualToString:@"Cancelled."]) { fail(err); return; }
            if (err) { appleBackup(err); return; }
            stageP(@"Checking the video");
            [ws verify:mp4 black:NO completion:^(NSString *problem) {
                if (!problem) { [ws note:@"join ok (FFmpeg)"]; store(mp4, YES); return; }
                appleBackup(problem);
            }];
        }];
    } else if ([kind isEqualToString:@"convert"]) {
        reencode(files[0], files.count >= 2 ? files[1] : nil);
    } else if ([kind isEqualToString:@"mp3"] || [kind isEqualToString:@"audio"]) {
        BOOL mp3 = [kind isEqualToString:@"mp3"];
        NSDictionary *p = [VGConvert probe:first];
        BOOL alreadyM4A = !mp3 && [p[@"audio"] isEqualToString:@"aac"] && [p[@"container"] hasPrefix:@"mov"];
        if (alreadyM4A) {
            NSString *dest = [documentsDir() stringByAppendingPathComponent:[self uniqueName:base ext:@"m4a"]];
            NSError *e = nil;
            [fm moveItemAtPath:first toPath:dest error:&e];
            if (e) fail(e.localizedDescription); else store(dest, NO);
            return;
        }
        NSString *dest = [documentsDir() stringByAppendingPathComponent:[self uniqueName:base ext:mp3 ? @"mp3" : @"m4a"]];
        NSString *what = mp3 ? @"Making MP3" : @"Making M4A";
        stageP(what);
        task.converter = [VGConvert new];
        [task.converter audio:first to:dest mp3:mp3 title:r[@"title"] artist:r[@"uploader"] progress:convertProgress(what)
                   completion:^(NSString *err) { if (err) fail(err); else store(dest, NO); }];
    } else {
        // A single video file: make it an MP4 that Photos accepts, whatever it arrived as.
        NSDictionary *p = [VGConvert probe:first];
        NSString *vc = p[@"video"], *ac = p[@"audio"], *container = p[@"container"];
        BOOL appleCodec = [vc isEqualToString:@"h264"] || [vc isEqualToString:@"hevc"];
        if (appleCodec) {
            BOOL isMP4 = [container hasPrefix:@"mov"];
            NSString *what = isMP4 ? @"Finishing up" : [NSString stringWithFormat:@"Converting %@ to MP4", [first.pathExtension uppercaseString] ?: @"video"];
            stageP(what);
            void (^backup)(NSString *) = ^(NSString *why) {
                [ws note:[NSString stringWithFormat:@"repackage (%@ %@/%@) failed: %@", container, vc, ac, why]];
                [fm removeItemAtPath:mp4 error:nil];
                if (!isMP4) { keepOriginal(); return; }   // keep the original so nothing is lost
                [ws remux:[NSURL fileURLWithPath:first] to:[NSURL fileURLWithPath:mp4] task:task completion:^(NSString *err) {
                    [ws verify:mp4 black:NO completion:^(NSString *problem) {
                        if (!err && !problem) { [ws note:@"repackage ok (Apple)"]; store(mp4, YES); return; }
                        [fm removeItemAtPath:mp4 error:nil];
                        keepOriginal();
                    }];
                }];
            };
            task.converter = [VGConvert new];
            [task.converter remux:first to:mp4 progress:convertProgress(what) completion:^(NSString *err) {
                if ([err isEqualToString:@"Cancelled."]) { fail(err); return; }
                if (err) { backup(err); return; }
                [ws verify:mp4 black:NO completion:^(NSString *problem) {
                    if (!problem) { [ws note:@"repackage ok (FFmpeg)"]; store(mp4, YES); return; }
                    backup(problem);
                }];
            }];
        } else if ([vc isEqualToString:@"vp9"] || [vc isEqualToString:@"vp8"]) {
            reencode(first, nil);
        } else {
            keepOriginal();
        }
    }
}


#pragma mark Diagnostics and repair

static NSString *fourCC(FourCharCode c) {
    char s[5] = {(char)(c >> 24), (char)(c >> 16), (char)(c >> 8), (char)c, 0};
    for (int i = 0; i < 4; i++) if (s[i] < 32 || s[i] > 126) s[i] = '?';
    return @(s);
}

- (void)diagnose:(VGItem *)item completion:(void (^)(NSString *))completion {
    NSString *path = item.fileURL.path;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableString *r = [NSMutableString string];
        NSString *v = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        [r appendFormat:@"VidGrab %@ · iOS %@\n", v, UIDevice.currentDevice.systemVersion];
        [r appendFormat:@"File: %@ (%@)\nQuality: %@ · site: %@\n", item.fileName,
            [NSByteCountFormatter stringFromByteCount:item.bytes countStyle:NSByteCountFormatterCountStyleFile], item.res, item.site ?: @"?"];
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path];
        [r appendFormat:@"Exists: %@\n", exists ? @"yes" : @"NO"];
        NSDictionary *p = [VGConvert probe:path];
        [r appendFormat:@"FFmpeg sees: container=%@ video=%@ audio=%@\n", p[@"container"], p[@"video"], p[@"audio"]];
        if (exists) [r appendString:[VGConvert describe:path]];

        AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
        [r appendFormat:@"Apple sees: playable=%@ duration=%.2fs tracks=%lu\n", a.isPlayable ? @"yes" : @"NO",
            CMTimeGetSeconds(a.duration), (unsigned long)a.tracks.count];
        for (AVAssetTrack *t in a.tracks) {
            CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)t.formatDescriptions.firstObject;
            NSString *codec = fd ? fourCC(CMFormatDescriptionGetMediaSubType(fd)) : @"none";
            if ([t.mediaType isEqualToString:AVMediaTypeVideo]) {
                CGAffineTransform x = t.preferredTransform;
                [r appendFormat:@"  video %@ %.0fx%.0f %.2ffps %.0fkbps decodable=%@ playable=%@ start=%.3fs len=%.2fs transform=[%.0f %.0f %.0f %.0f]\n",
                    codec, t.naturalSize.width, t.naturalSize.height, t.nominalFrameRate, t.estimatedDataRate / 1000,
                    t.isDecodable ? @"yes" : @"NO", t.isPlayable ? @"yes" : @"NO",
                    CMTimeGetSeconds(t.timeRange.start), CMTimeGetSeconds(t.timeRange.duration), x.a, x.b, x.c, x.d];
            } else {
                [r appendFormat:@"  %@ %@ start=%.3fs len=%.2fs\n", t.mediaType, codec,
                    CMTimeGetSeconds(t.timeRange.start), CMTimeGetSeconds(t.timeRange.duration)];
            }
        }
        double secs = CMTimeGetSeconds(a.duration);
        if (secs > 0) {
            AVAssetImageGenerator *g = [AVAssetImageGenerator assetImageGeneratorWithAsset:a];
            g.appliesPreferredTrackTransform = YES;
            g.maximumSize = CGSizeMake(160, 160);
            for (NSNumber *f in @[@0.05, @0.25, @0.5, @0.75, @0.95]) {
                NSError *e = nil;
                CMTime got;
                CGImageRef img = [g copyCGImageAtTime:CMTimeMakeWithSeconds(secs * f.doubleValue, 600) actualTime:&got error:&e];
                if (img) {
                    [r appendFormat:@"  frame @%.1fs: brightness %.1f\n", CMTimeGetSeconds(got), brightness(img)];
                    CGImageRelease(img);
                } else {
                    [r appendFormat:@"  frame @%.1fs: unreadable (%@)\n", secs * f.doubleValue, e.localizedDescription ?: @"?"];
                }
            }
        }
        NSString *pr = [self problemWithVideo:path checkBlack:YES];
        [r appendFormat:@"Check: %@\n", pr ?: @"looks fine"];
        if (self.convLog.length) [r appendFormat:@"\nConversion notes:\n%@", self.convLog];
        NSString *out = [r copy];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(out); });
    });
}

- (void)repairItem:(VGItem *)item progress:(void (^)(double))progress completion:(void (^)(NSString *))completion {
    NSString *path = item.fileURL.path;
    NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:@"repair"];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:work error:nil];
    [fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *out = [work stringByAppendingPathComponent:@"fixed.mp4"];
    NSMutableArray<NSString *> *tried = [NSMutableArray array];
    NSDictionary *probe = [VGConvert probe:path];
    NSString *vc = probe[@"video"] ?: @"", *ac = probe[@"audio"] ?: @"";
    [self note:[NSString stringWithFormat:@"repair %@: container=%@ video=%@ audio=%@", item.fileName, probe[@"container"], vc, ac]];
    __weak typeof(self) ws = self;

    // Puts the fixed file in place of the original once it passes the picture check.
    void (^accept)(NSString *) = ^(NSString *how) {
        NSError *err = nil;
        [fm replaceItemAtURL:item.fileURL withItemAtURL:[NSURL fileURLWithPath:out] backupItemName:nil options:0 resultingItemURL:nil error:&err];
        [fm removeItemAtPath:work error:nil];
        if (err) { completion(err.localizedDescription); return; }
        item.bytes = [[fm attributesOfItemAtPath:path error:nil][NSFileSize] longLongValue];
        item.photos = YES;
        [ws makeThumbnailFor:item fallbackURL:nil];
        [ws saveLibrary];
        [ws note:[@"repair ok via " stringByAppendingString:how]];
        completion(nil);
    };
    void (^giveUp)(void) = ^{
        [fm removeItemAtPath:work error:nil];
        completion([NSString stringWithFormat:@"None of the repair methods worked.\n\nFile: video %@, sound %@\n%@",
                    vc.length ? vc : @"none", ac.length ? ac : @"none", [tried componentsJoinedByString:@"\n"]]);
    };

    // Method 3: FFmpeg decodes the picture, Apple's hardware encoder rebuilds it.
    void (^method3)(void) = ^{
        BOOL canDecode = [@[@"h264", @"hevc", @"vp9", @"vp8"] containsObject:vc];
        if (!canDecode) { [tried addObject:[NSString stringWithFormat:@"3. Rebuild picture: skipped (%@ not supported)", vc.length ? vc : @"no video"]]; giveUp(); return; }
        void (^encode)(NSString *) = ^(NSString *sound) {
            VGTranscoder *tx = [VGTranscoder new];
            objc_setAssociatedObject(item, "vg.repair", tx, OBJC_ASSOCIATION_RETAIN);
            [tx convertVideo:[NSURL fileURLWithPath:path] audio:sound ? [NSURL fileURLWithPath:sound] : nil to:[NSURL fileURLWithPath:out]
                    progress:^(double f) { if (progress) progress(0.5 + f * 0.5); }
                  completion:^(NSString *err) {
                objc_setAssociatedObject(item, "vg.repair", nil, OBJC_ASSOCIATION_RETAIN);
                if (err) { [tried addObject:[@"3. Rebuild picture: " stringByAppendingString:err]]; giveUp(); return; }
                [ws verify:out black:YES completion:^(NSString *problem) {
                    if (!problem) { accept(@"FFmpeg decode + Apple encode"); return; }
                    [tried addObject:[@"3. Rebuild picture: result " stringByAppendingString:problem]];
                    giveUp();
                }];
            }];
        };
        if (!ac.length) { encode(nil); return; }
        // Sound goes in as AAC: copy it out (or convert it) with FFmpeg first.
        NSString *sound = [work stringByAppendingPathComponent:@"sound.m4a"];
        VGConvert *c = [VGConvert new];
        objc_setAssociatedObject(item, "vg.repair", c, OBJC_ASSOCIATION_RETAIN);
        [c audio:path to:sound mp3:NO title:nil artist:nil progress:nil completion:^(NSString *err) {
            if (err) [tried addObject:[@"3. (sound could not be copied, continuing without it: " stringByAppendingFormat:@"%@)", err]];
            encode(err ? nil : sound);
        }];
    };

    // Method 2: FFmpeg repackages H.264/HEVC into a fresh MP4 (fast, no quality loss).
    void (^method2)(void) = ^{
        if (![vc isEqualToString:@"h264"] && ![vc isEqualToString:@"hevc"]) { [tried addObject:@"2. Repackage: skipped (not H.264/HEVC)"]; method3(); return; }
        [fm removeItemAtPath:out error:nil];
        VGConvert *c = [VGConvert new];
        objc_setAssociatedObject(item, "vg.repair", c, OBJC_ASSOCIATION_RETAIN);
        [c remux:path to:out progress:^(double f) { if (progress) progress(0.3 + f * 0.2); } completion:^(NSString *err) {
            if (err) { [tried addObject:[@"2. Repackage: " stringByAppendingString:err]]; method3(); return; }
            [ws verify:out black:YES completion:^(NSString *problem) {
                if (!problem) { accept(@"FFmpeg repackage"); return; }
                [tried addObject:[@"2. Repackage: result " stringByAppendingString:problem]];
                method3();
            }];
        }];
    };

    // Method 1: Apple re-encodes it (works when Apple can read the file).
    AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetExportSession *ex = [[AVAssetExportSession alloc] initWithAsset:a presetName:AVAssetExportPresetHighestQuality];
    if (!ex) { [tried addObject:@"1. Apple re-encode: iPhone can't open this file"]; method2(); return; }
    ex.outputURL = [NSURL fileURLWithPath:out];
    ex.outputFileType = AVFileTypeMPEG4;
    ex.shouldOptimizeForNetworkUse = YES;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { if (progress) progress(ex.progress * 0.3); }];
    [ex exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [timer invalidate];
            if (ex.status != AVAssetExportSessionStatusCompleted) {
                [tried addObject:[@"1. Apple re-encode: " stringByAppendingString:ex.error.localizedDescription ?: @"failed"]];
                method2();
                return;
            }
            [ws verify:out black:YES completion:^(NSString *problem) {
                if (!problem) { accept(@"Apple re-encode"); return; }
                [tried addObject:[@"1. Apple re-encode: result " stringByAppendingString:problem]];
                method2();
            }];
        });
    }];
}

#pragma mark AVFoundation

- (void)export:(AVAsset *)asset to:(NSURL *)dest preset:(NSString *)preset task:(VGTask *)task completion:(void (^)(NSString *))completion {
    [NSFileManager.defaultManager removeItemAtURL:dest error:nil];
    AVAssetExportSession *ex = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!ex) { completion(@"This video format can't be processed on iPhone."); return; }
    ex.outputURL = dest;
    ex.outputFileType = AVFileTypeMPEG4;
    ex.shouldOptimizeForNetworkUse = YES;
    task.export = ex;
    [ex exportAsynchronouslyWithCompletionHandler:^{
        NSString *err = nil;
        if (ex.status == AVAssetExportSessionStatusCancelled) err = @"Cancelled.";
        else if (ex.status != AVAssetExportSessionStatusCompleted) err = ex.error.localizedDescription ?: @"Couldn't finish the video.";
        dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
    }];
}

- (void)remux:(NSURL *)src to:(NSURL *)dest task:(VGTask *)task completion:(void (^)(NSString *))completion {
    AVURLAsset *a = [AVURLAsset URLAssetWithURL:src options:nil];
    [self export:a to:dest preset:AVAssetExportPresetPassthrough task:task completion:completion];
}

- (void)mergeVideo:(NSURL *)v audio:(NSURL *)a to:(NSURL *)dest task:(VGTask *)task completion:(void (^)(NSString *))completion {
    AVURLAsset *va = [AVURLAsset URLAssetWithURL:v options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVURLAsset *aa = [AVURLAsset URLAssetWithURL:a options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetTrack *vt = [va tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVAssetTrack *at = [aa tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!vt) { completion(@"The downloaded video stream couldn't be read."); return; }

    AVMutableComposition *comp = [AVMutableComposition composition];
    NSError *e = nil;
    CMTime dur = va.duration;
    AVMutableCompositionTrack *cv = [comp addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    [cv insertTimeRange:CMTimeRangeMake(kCMTimeZero, dur) ofTrack:vt atTime:kCMTimeZero error:&e];
    cv.preferredTransform = vt.preferredTransform;
    if (at) {
        AVMutableCompositionTrack *ca = [comp addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        CMTime ad = CMTimeMinimum(aa.duration, dur);
        [ca insertTimeRange:CMTimeRangeMake(kCMTimeZero, ad) ofTrack:at atTime:kCMTimeZero error:nil];
    }
    if (e) { completion(e.localizedDescription); return; }

    [self export:comp to:dest preset:AVAssetExportPresetPassthrough task:task completion:^(NSString *err) {
        if (!err || [err isEqualToString:@"Cancelled."]) { completion(err); return; }
        // Passthrough can fail on unusual files; re-encode as a fallback (slower).
        [self export:comp to:dest preset:AVAssetExportPresetHighestQuality task:task completion:completion];
    }];
}

- (void)makeThumbnailFor:(VGItem *)item fallbackURL:(NSString *)remote {
    if (!item.audio) {
        AVAssetImageGenerator *g = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:item.fileURL options:nil]];
        g.appliesPreferredTrackTransform = YES;
        g.maximumSize = CGSizeMake(480, 480);
        CMTime t = CMTimeMakeWithSeconds(MIN(2.0, MAX(item.duration / 4, 0)), 600);
        CGImageRef img = [g copyCGImageAtTime:t actualTime:NULL error:nil];
        if (img) {
            [UIImageJPEGRepresentation([UIImage imageWithCGImage:img], 0.8) writeToFile:[item thumbPath] atomically:YES];
            CGImageRelease(img);
            return;
        }
    }
    if (remote.length) {
        NSString *path = [item thumbPath];
        [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:remote] completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            UIImage *img = d ? [UIImage imageWithData:d] : nil;
            if (!img) return;
            [UIImageJPEGRepresentation(img, 0.8) writeToFile:path atomically:YES];
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:VGLibraryDidChangeNotification object:nil];
            });
        }] resume];
    }
}

- (void)copyErrorDetails:(void (^)(void))done {
    [[VGPython shared] call:@"vgbridge" function:@"last_error" args:@[] completion:^(NSDictionary *r, NSString *error) {
        NSString *v = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"VidGrab %@ · engine %@ · iOS %@\n%@\n\nConversion notes:\n%@",
            v, self.engineVersion, UIDevice.currentDevice.systemVersion, r[@"details"] ?: error ?: @"(none)", self.convLog ?: @"(none)"];
        done();
    }];
}

#pragma mark Engine update

- (void)updateEngine:(void (^)(NSString *, NSString *))completion {
    if (self.activeCount) { completion(@"Downloads in progress", @"Wait for your downloads to finish, then update the engine."); return; }
    VGPython *py = [VGPython shared];
    [py call:@"vgboot" function:@"update_engine" args:@[py.engineDir, py.engineVersion ?: @"0"]
  completion:^(NSDictionary *r, NSString *error) {
        if (!r) { completion(@"Update failed", error ?: @"Unknown error."); return; }
        NSString *status = r[@"status"];
        if ([status isEqualToString:@"current"]) completion(@"You're up to date", [NSString stringWithFormat:@"Engine version %@ is the newest.", r[@"version"]]);
        else if ([status isEqualToString:@"updated"]) completion(@"Engine updated", [NSString stringWithFormat:@"Version %@ is ready. Close and reopen VidGrab to start using it.", r[@"version"]]);
        else completion(@"Update failed", r[@"error"] ?: @"Unknown error.");
    }];
}

@end
