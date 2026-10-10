#import "VGOverlay.h"
#import "VGEngine.h"
#import "VGTheme.h"
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <signal.h>
#import <errno.h>


// Talks to the bubble helper (VidGrabHUD) with Darwin notifications and one 64-bit state value.
// On a jailbreak the helper runs all the time as a small service and stays hidden until needed.
// On TrollStore, VidGrab starts it when you leave the app with downloads running.
#define N_STATE  "com.t4mag0.vidgrab.hud.state"
#define N_UPDATE "com.t4mag0.vidgrab.hud.update"
#define N_THEME  "com.t4mag0.vidgrab.hud.theme"
#define N_THEME2 "com.t4mag0.vidgrab.hud.theme2"
#define N_HIDE   "com.t4mag0.vidgrab.hud.exit"
#define N_PID    "com.t4mag0.vidgrab.hud.pid"
#define N_ALIVE  "com.t4mag0.vidgrab.hud.alive"
#define N_HUDPID "com.t4mag0.vidgrab.hud.hudpid"
#define N_DIAG   "com.t4mag0.vidgrab.hud.diag"


static NSString *const kEnabledKey = @"vgOverlayBubble";
static BOOL gInBackground, gPending, gShowing;
static NSInteger gSaved, gFailed;
static NSMutableString *gLog;

static int Token(const char *name) {
    static NSMutableDictionary *tokens;
    if (!tokens) tokens = [NSMutableDictionary dictionary];
    NSString *k = @(name);
    if (!tokens[k]) { int t = 0; notify_register_check(name, &t); tokens[k] = @(t); }
    return [tokens[k] intValue];
}

static void SetState(const char *name, uint64_t v) { notify_set_state(Token(name), v); }
static uint64_t GetState(const char *name) { uint64_t v = 0; notify_get_state(Token(name), &v); return v; }

static uint64_t Rgb24(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [c getRed:&r green:&g blue:&b alpha:&a];
    return ((uint64_t)lround(r * 255) << 16) | ((uint64_t)lround(g * 255) << 8) | (uint64_t)lround(b * 255);
}

@implementation VGOverlay

/// Gives the bubble service the colors of the chosen theme.
+ (void)pushTheme {
    VGPalette *p = VGPalette.current;
    SetState(N_THEME, (1ULL << 63) | Rgb24(p.accent) | (Rgb24(p.surface2) << 24));
    SetState(N_THEME2, Rgb24(p.stroke) | (Rgb24(p.background) << 24));
}

+ (BOOL)enabled {
    if (!self.bubbleAllowed) return NO;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    return [d objectForKey:kEnabledKey] ? [d boolForKey:kEnabledKey] : YES;
}

+ (void)setEnabled:(BOOL)on {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kEnabledKey];
    if (!on) [self hide];
}

+ (NSString *)helperPath { return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"VidGrabHUD"]; }

+ (BOOL)supported { return [NSFileManager.defaultManager fileExistsAtPath:[self helperPath]]; }

/// The jailbreak service answered within the last few seconds.
+ (BOOL)serviceAlive {
    uint64_t t = GetState(N_ALIVE);
    return t > 0 && llabs((long long)time(NULL) - (long long)t) < 4;
}

+ (BOOL)isJailbreakInstall {
    NSString *b = NSBundle.mainBundle.bundlePath;
    if ([b containsString:@"/.jbroot-"] || [b hasPrefix:@"/Applications/"] || [b hasPrefix:@"/var/jb/"] || [b hasPrefix:@"/private/var/jb/"]) return YES;
    // Rootless jailbreaks often report the real location of /var/jb, e.g. /private/preboot/<id>/dopamine-<id>/procursus/Applications/VidGrab.app
    if ([b hasPrefix:@"/private/preboot/"] || [b containsString:@"/procursus/"] || [b containsString:@"/dopamine-"] || [b containsString:@"/jb/"]) return YES;
    // Anything installed outside the normal app folders (App Store, sideload and TrollStore apps all live in .../containers/Bundle/Application/) with the helper inside is a package install.
    BOOL inContainers = [b containsString:@"/containers/Bundle/Application/"];
    return !inContainers && [b.lastPathComponent isEqualToString:@"VidGrab.app"] && [b.stringByDeletingLastPathComponent.lastPathComponent isEqualToString:@"Applications"] && [self supported];
}

// VidGrab opened from inside LiveContainer: it only gets LiveContainer's permissions.
+ (BOOL)insideLiveContainer {
    if (getenv("LC_HOME_PATH") || getenv("LC_CONTAINER_PATH") || NSClassFromString(@"LCSharedUtils")) return YES;
    NSString *b = NSBundle.mainBundle.bundlePath;
    return [b containsString:@"/Data/Application/"] || [b.lowercaseString containsString:@"livecontainer"];
}

/// TrollStore: the separate "VidGrab Bubble" helper app is installed (it starts the bubble service as root).
+ (BOOL)starterPresent {
    return [NSFileManager.defaultManager fileExistsAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"PlugIns/VGBubbleStarter.appex"]];
}

/// The .tipa carries the small Bubble app inside; Settings can hand it to TrollStore to install.
+ (NSString *)bundledHelperPath { return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"VidGrabBubble.tipa"]; }

+ (BOOL)canInstallHelper {
    return ![self isJailbreakInstall] && ![self insideLiveContainer] && ![self helperInstalled]
        && [NSFileManager.defaultManager fileExistsAtPath:[self bundledHelperPath]];
}

static UIDocumentInteractionController *gDoc;

+ (void)installHelperFrom:(UIViewController *)vc {
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"VidGrab-Bubble.tipa"];
    [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
    [NSFileManager.defaultManager copyItemAtPath:[self bundledHelperPath] toPath:tmp error:nil];
    gDoc = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:tmp]];
    CGRect r = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 1, 1);
    if (![gDoc presentOpenInMenuFromRect:r inView:vc.view animated:YES]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Can't open the installer" message:@"No app on this phone can open the helper file. Install TrollStore first." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    }
}

+ (BOOL)helperInstalled {
    if ([self starterPresent]) return YES;
    return [UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:@"vidgrabbubble://ping"]];
}

/// Installed with TrollStore (it leaves a marker file in the app).
+ (BOOL)trollStoreInstall {
    return [NSFileManager.defaultManager fileExistsAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"_TrollStore"]];
}

// Floating progress (bubble over other apps and Sound when done): jailbreak packages, and TrollStore with the helper app.
+ (BOOL)fullInstall { return ([self isJailbreakInstall] || [self trollStoreInstall] || [self helperInstalled]) && ![self insideLiveContainer]; }

+ (BOOL)finishSound { return self.fullInstall && [NSUserDefaults.standardUserDefaults boolForKey:@"vgFinishSound"]; }
+ (void)setFinishSound:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:@"vgFinishSound"]; }

+ (BOOL)bubbleAllowed {
    if ([self insideLiveContainer]) return NO;
    if ([self isJailbreakInstall]) return [self supported];
    return [self helperInstalled];
}

+ (BOOL)realBubbleAvailable { return [self bubbleAllowed] && [self serviceAlive]; }

+ (void)start {
    SetState(N_PID, (uint64_t)getpid());
    [self pushTheme];
    [NSNotificationCenter.defaultCenter addObserverForName:VGThemeDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        [self pushTheme];
        if ([self serviceAlive]) notify_post(N_UPDATE);
    }];
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    NSOperationQueue *main = NSOperationQueue.mainQueue;
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        gInBackground = YES;
        gSaved = gFailed = 0;
        if (self.enabled && [VGEngine shared].activeCount > 0 && [self bubbleAllowed]) [self show:NO];
    }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        gInBackground = NO;
        [self hide];
        // make sure the bubble outside the app is gone, even if the first message was missed
        for (NSNumber *d in @[@0.3, @1.0, @2.5]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (!gInBackground) [self hide]; });
    }];
    [nc addObserverForName:VGTaskFinishedNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        if (!gInBackground) return;
        VGTask *t = n.object;
        if (t.state == VGTaskDone) gSaved++;
        else if (t.state == VGTaskFailed) gFailed++;
        [self update];
    }];
    [nc addObserverForName:VGTasksDidChangeNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        if (!gInBackground && [VGEngine shared].activeCount > 0) [self launchHelperIfNeeded];
        if (!gInBackground || !gShowing || gPending) return;
        gPending = YES;   // at most a few updates a second
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            gPending = NO;
            [self update];
        });
    }];
    [self hide];   // left over from last time
}

static NSDate *gLastLaunch;

/// Starts the bubble service: through the hidden starter extension in the TrollStore .tipa, else through the Bubble helper app.
+ (void)startService {
    if ([self starterPresent]) {
        Class ext = NSClassFromString(@"NSExtension");
        NSError *err = nil;
        id (*find)(id, SEL, NSString *, NSError **) = (void *)objc_msgSend;
        id e = ext ? find(ext, NSSelectorFromString(@"extensionWithIdentifier:error:"), @"com.t4mag0.vidgrab.bubblestarter", &err) : nil;
        if (!e) { [self note:[NSString stringWithFormat:@"starter extension not found by the system (%@)", err.localizedDescription ?: @"no error"]]; return; }
        void (*begin)(id, SEL, NSArray *, void (^)(NSUUID *)) = (void *)objc_msgSend;
        void (*setCancel)(id, SEL, id) = (void *)objc_msgSend;
        SEL sc = NSSelectorFromString(@"setRequestCancellationBlock:");
        if ([e respondsToSelector:sc]) setCancel(e, sc, ^(NSUUID *u, NSError *er) { [VGOverlay note:[NSString stringWithFormat:@"extension request cancelled: %@", er]]; });
        SEL si = NSSelectorFromString(@"setRequestInterruptionBlock:");
        if ([e respondsToSelector:si]) setCancel(e, si, ^(NSUUID *u) { [VGOverlay note:@"extension request interrupted"]; });
        begin(e, NSSelectorFromString(@"beginExtensionRequestWithInputItems:completion:"), @[], ^(NSUUID *u) { [VGOverlay note:u ? @"extension request sent" : @"extension request returned no id"]; });
        return;
    }
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"vidgrabbubble://start"] options:@{} completionHandler:nil];
}

/// TrollStore: ask the helper app to start the bubble service (it flashes on screen and returns to VidGrab).
+ (void)launchHelperIfNeeded {
    if ([self isJailbreakInstall] || [self serviceAlive] || ![self helperInstalled]) return;
    pid_t hp = (pid_t)GetState(N_HUDPID);
    if (hp > 0 && (kill(hp, 0) == 0 || errno == EPERM)) return;   // a helper is still around (maybe just asleep): don't start a second one
    if (gLastLaunch && -[gLastLaunch timeIntervalSinceNow] < 120) return;
    gLastLaunch = NSDate.date;
    [self startService];
}

+ (uint64_t)packCount:(NSInteger)n fraction:(double)f waiting:(BOOL)w saved:(NSInteger)s failed:(NSInteger)x sample:(BOOL)sample {
    uint64_t v = (uint64_t)MIN(n, 0xFFFF);
    v |= (uint64_t)MIN(1000, MAX(0, (int)round(f * 1000))) << 16;
    v |= (uint64_t)(w ? 1 : 0) << 32;
    v |= (uint64_t)MIN(s, 0xFF) << 33;
    v |= (uint64_t)MIN(x, 0xFF) << 41;
    v |= (uint64_t)(sample ? 1 : 0) << 49;
    return v;
}

+ (void)writeState {
    VGEngine *e = [VGEngine shared];
    VGTask *lead = e.leadTask;
    [self pushTheme];
    SetState(N_STATE, [self packCount:e.activeCount fraction:lead ? lead.fraction : 0 waiting:lead.state == VGTaskQueued
                                saved:gSaved failed:gFailed sample:NO]);
}

+ (void)update {
    if (!gShowing) return;
    [self writeState];
    notify_post(N_UPDATE);
    if ([VGEngine shared].activeCount == 0) gShowing = NO;   // the bubble shows a check and goes away
}

+ (void)show:(BOOL)sample {
    gShowing = YES;
    SetState(N_PID, (uint64_t)getpid());
    if (sample) SetState(N_STATE, [self packCount:2 fraction:0.42 waiting:NO saved:0 failed:0 sample:YES]);
    else [self writeState];
    if ([self serviceAlive]) { notify_post(N_UPDATE); [self note:@"bubble service is running"]; }
}

+ (void)note:(NSString *)line {
    if (!gLog) gLog = [NSMutableString string];
    [gLog appendFormat:@"%@\n", line];
}

+ (void)testWithCompletion:(void (^)(BOOL, NSString *))done {
    gLog = [NSMutableString string];
    BOOL jb = [self isJailbreakInstall];
    [self note:[NSString stringWithFormat:@"version %@, %@", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                jb ? @"jailbreak package" : ([self trollStoreInstall] ? @"TrollStore" : @"app install")]];
    if ([self insideLiveContainer]) {
        gLog = [NSMutableString stringWithString:@"This copy of VidGrab is running inside LiveContainer, which doesn't allow the bubble over other apps. Install VidGrab with TrollStore or as a jailbreak package to get it.\n\nThe bubble inside VidGrab, background downloads and the finish notification still work."];
        done(NO, gLog);
        return;
    }
    if (!jb && ![self helperInstalled]) {
        if ([self trollStoreInstall]) gLog = [NSMutableString stringWithString:@"To get the bubble over other apps on TrollStore, go back to Settings and tap Install bubble helper, then choose TrollStore. Then try again.\n\nThe bubble inside VidGrab, background downloads, the finish notification and Sound when done still work."];
        else gLog = [NSMutableString stringWithString:@"This copy was sideloaded with an Apple ID (AltStore, Sideloadly), which doesn't allow the bubble over other apps. Install VidGrab with TrollStore (plus the VidGrab Bubble app) or as a jailbreak package to get it.\n\nThe bubble inside VidGrab, background downloads and the finish notification still work."];
        done(NO, gLog);
        return;
    }
    if (jb && ![self supported]) { [self note:@"helper file missing"]; done(NO, gLog); return; }
    if (!jb && ![self serviceAlive]) {
        [self note:[self starterPresent] ? @"starting the bubble service" : @"starting the bubble helper (the screen flashes for a second)"];
        gLastLaunch = NSDate.date;
        [self startService];
        __block int tries = 0;
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            tries++;
            if ([self serviceAlive]) { [t invalidate]; [self finishTest:done]; }
            else if (tries > 30) {
                [t invalidate];
                int tk = 0; uint64_t rv = 0; notify_register_check("com.t4mag0.vidgrab.starter.result", &tk); notify_get_state(tk, &rv);
                [self note:[self starterPresent] ? [NSString stringWithFormat:@"the bubble service did not start (starter result %llu; 0 = never ran, 3 = ran but did not finish, 1 = ok as root, 2 = ok as app, 100+ = error code)", rv]
                                                 : @"the bubble helper did not start. Open the VidGrab Bubble app once and read what it says."];
                done(NO, [gLog stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
            }
        }];
        return;
    }
    [self finishTest:done];
}

+ (void)finishTest:(void (^)(BOOL, NSString *))done {
    BOOL jb = [self isJailbreakInstall];
    [self show:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL alive = [self serviceAlive];
        uint64_t dg = GetState(N_DIAG);
        if (dg >> 63) [self note:[NSString stringWithFormat:@"bubble service: window id %u, shown %llu time(s), last count it saw %llu", (unsigned)(dg & 0xFFFFFFFF), (dg >> 32) & 0xFF, (dg >> 40) & 0xFF]];
        else [self note:@"bubble service: old version still running (restart your phone or do a userspace reboot so the new one starts)"];
        if (!alive) [self note:jb ? @"bubble service isn't running. Restart your phone (or do a userspace reboot) and try again."
                                  : @"bubble service stopped answering"];
        done(alive, [gLog stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
    });
}

+ (void)hide {
    gShowing = NO;
    SetState(N_STATE, 0);
    notify_post(N_HIDE);
}

@end
