#import "VGOverlay.h"
#import "VGEngine.h"
#import <UIKit/UIKit.h>
#import <notify.h>
#import <signal.h>

// Talks to the bubble helper (VidGrabHUD) with Darwin notifications and one 64-bit state value.
// On a jailbreak the helper runs all the time as a small service and stays hidden until needed.
// On TrollStore, VidGrab starts it when you leave the app with downloads running.
#define N_STATE  "com.t4mag0.vidgrab.hud.state"
#define N_UPDATE "com.t4mag0.vidgrab.hud.update"
#define N_HIDE   "com.t4mag0.vidgrab.hud.exit"
#define N_PID    "com.t4mag0.vidgrab.hud.pid"
#define N_ALIVE  "com.t4mag0.vidgrab.hud.alive"


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

@implementation VGOverlay

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
    return [b containsString:@"/.jbroot-"] || [b hasPrefix:@"/Applications/"] || [b hasPrefix:@"/var/jb/"] || [b hasPrefix:@"/private/var/jb/"];
}

// VidGrab opened from inside LiveContainer: it only gets LiveContainer's permissions.
+ (BOOL)insideLiveContainer {
    if (getenv("LC_HOME_PATH") || getenv("LC_CONTAINER_PATH") || NSClassFromString(@"LCSharedUtils")) return YES;
    NSString *b = NSBundle.mainBundle.bundlePath;
    return [b containsString:@"/Data/Application/"] || [b.lowercaseString containsString:@"livecontainer"];
}

// Floating progress (bubble over other apps and Sound when done) is a jailbreak-only feature.
+ (BOOL)fullInstall { return [self isJailbreakInstall] && ![self insideLiveContainer]; }

+ (BOOL)finishSound { return self.fullInstall && [NSUserDefaults.standardUserDefaults boolForKey:@"vgFinishSound"]; }
+ (void)setFinishSound:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:@"vgFinishSound"]; }

+ (BOOL)bubbleAllowed { return [self isJailbreakInstall] && ![self insideLiveContainer] && [self supported]; }

+ (BOOL)realBubbleAvailable { return [self bubbleAllowed] && [self serviceAlive]; }

+ (void)start {
    SetState(N_PID, (uint64_t)getpid());
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    NSOperationQueue *main = NSOperationQueue.mainQueue;
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        gInBackground = YES;
        gSaved = gFailed = 0;
        if (self.enabled && [VGEngine shared].activeCount > 0 && [self realBubbleAvailable]) [self show:NO];
    }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        gInBackground = NO;
        [self hide];
    }];
    [nc addObserverForName:VGTaskFinishedNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        if (!gInBackground) return;
        VGTask *t = n.object;
        if (t.state == VGTaskDone) gSaved++;
        else if (t.state == VGTaskFailed) gFailed++;
        [self update];
    }];
    [nc addObserverForName:VGTasksDidChangeNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        if (!gInBackground || !gShowing || gPending) return;
        gPending = YES;   // at most a few updates a second
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            gPending = NO;
            [self update];
        });
    }];
    [self hide];   // left over from last time
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
    BOOL jb = [NSBundle.mainBundle.bundlePath containsString:@"/.jbroot-"] || [NSBundle.mainBundle.bundlePath hasPrefix:@"/Applications/"]
           || [NSBundle.mainBundle.bundlePath hasPrefix:@"/var/jb/"] || [NSBundle.mainBundle.bundlePath hasPrefix:@"/private/var/jb/"];
    [self note:[NSString stringWithFormat:@"version %@, %@", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                jb ? @"jailbreak package" : @"app install"]];
    if ([self insideLiveContainer]) {
        gLog = [NSMutableString stringWithString:@"This copy of VidGrab is running inside LiveContainer, which doesn't allow the bubble over other apps. Install VidGrab with TrollStore or as a jailbreak package to get it.\n\nThe bubble inside VidGrab, background downloads and the finish notification still work."];
        done(NO, gLog);
        return;
    }
    if (![self isJailbreakInstall] && ![NSFileManager.defaultManager fileExistsAtPath:[NSBundle.mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"]]) {
        gLog = [NSMutableString stringWithString:@"This copy was installed with TrollStore, which doesn't allow the bubble over other apps. It needs VidGrab installed as a jailbreak package.\n\nThe bubble inside VidGrab, background downloads, the finish notification and Sound when done still work."];
        done(NO, gLog);
        return;
    }
    if ([NSFileManager.defaultManager fileExistsAtPath:[NSBundle.mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"]]) {
        gLog = [NSMutableString stringWithString:@"This copy was sideloaded with an Apple ID (AltStore, Sideloadly), which doesn't allow the bubble over other apps. Install VidGrab with TrollStore or as a jailbreak package to get it.\n\nThe bubble inside VidGrab, background downloads and the finish notification still work."];
        done(NO, gLog);
        return;
    }
    if (![self supported]) { [self note:@"helper file missing"]; done(NO, gLog); return; }
    [self show:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL alive = [self serviceAlive];
        if (!alive) [self note:jb ? @"bubble service isn't running. Restart your phone (or do a userspace reboot) and try again."
                                  : @"bubble helper isn't running"];
        done(alive, [gLog stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
    });
}

+ (void)hide {
    gShowing = NO;
    SetState(N_STATE, 0);
    notify_post(N_HIDE);
}

@end
