#import "VGKeepAlive.h"
#import "VGEngine.h"
#import "VGOverlay.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <UserNotifications/UserNotifications.h>

static NSString *const kEnabledKey = @"vgKeepDownloading";
static AVAudioPlayer *gSilence;
static UIBackgroundTaskIdentifier gTask;   // 0 is UIBackgroundTaskInvalid
static BOOL gInBackground;
static NSInteger gDone, gFailed;
static NSString *gLastTitle;
BOOL VGPlayerIsActive(void);

@implementation VGKeepAlive

+ (BOOL)enabled {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    return [d objectForKey:kEnabledKey] ? [d boolForKey:kEnabledKey] : YES;
}

+ (void)setEnabled:(BOOL)on {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kEnabledKey];
    if (!on) [self stopKeeping];
}

+ (void)start {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    NSOperationQueue *main = NSOperationQueue.mainQueue;
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        gInBackground = YES;
        gDone = gFailed = 0;
        if (self.enabled && [VGEngine shared].activeCount > 0) [self startKeeping];
    }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        gInBackground = NO;
        [self stopKeeping];
    }];
    [nc addObserverForName:VGTaskFinishedNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        VGTask *t = n.object;
        if (!gInBackground) return;
        if (t.state == VGTaskDone) { gDone++; gLastTitle = t.video.title; }
        else if (t.state == VGTaskFailed) gFailed++;
        if ([VGEngine shared].activeCount == 0) {
            BOOL sound = [self notify];
            // Stay awake a moment so the sound can finish playing.
            if (sound) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (gInBackground && [VGEngine shared].activeCount == 0) [self stopKeeping];
            });
            else [self stopKeeping];
        }
    }];
    // Ask once, the first time you download something, so we can tell you when it's done.
    [nc addObserverForName:VGTasksDidChangeNotification object:nil queue:main usingBlock:^(NSNotification *n) {
        static BOOL asked;
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        if (asked || [ud boolForKey:@"vgAskedNotif"] || [VGEngine shared].activeCount == 0) return;
        asked = YES;
        [ud setBool:YES forKey:@"vgAskedNotif"];   // ask once ever, never again on later launches
        [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge
                                                                          completionHandler:^(BOOL g, NSError *e) {}];
    }];
}

// One second of silence, played on a loop. Mixed with other apps, so it never stops your music.
+ (NSData *)silentWav {
    const uint32_t rate = 8000, samples = rate;
    NSMutableData *d = [NSMutableData data];
    uint32_t dataLen = samples * 2, riffLen = 36 + dataLen, fmtLen = 16, byteRate = rate * 2;
    uint16_t pcm = 1, ch = 1, align = 2, bits = 16;
    [d appendBytes:"RIFF" length:4]; [d appendBytes:&riffLen length:4]; [d appendBytes:"WAVE" length:4];
    [d appendBytes:"fmt " length:4]; [d appendBytes:&fmtLen length:4];
    [d appendBytes:&pcm length:2]; [d appendBytes:&ch length:2]; [d appendBytes:&rate length:4];
    [d appendBytes:&byteRate length:4]; [d appendBytes:&align length:2]; [d appendBytes:&bits length:2];
    [d appendBytes:"data" length:4]; [d appendBytes:&dataLen length:4];
    [d increaseLengthBy:dataLen];
    return d;
}

+ (void)startKeeping {
    UIApplication *app = UIApplication.sharedApplication;
    if (gTask == UIBackgroundTaskInvalid)
        gTask = [app beginBackgroundTaskWithName:@"downloads" expirationHandler:^{
            [app endBackgroundTask:gTask];
            gTask = UIBackgroundTaskInvalid;
        }];
    if (VGPlayerIsActive()) return;   // a video is playing in the background, which already keeps us going
    AVAudioSession *s = AVAudioSession.sharedInstance;
    [s setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [s setActive:YES error:nil];
    if (!gSilence) {
        gSilence = [[AVAudioPlayer alloc] initWithData:[self silentWav] error:nil];
        gSilence.numberOfLoops = -1;
        gSilence.volume = 0.01;
    }
    [gSilence play];
}

+ (void)stopKeeping {
    [gSilence stop];
    if (gTask != UIBackgroundTaskInvalid) {
        [UIApplication.sharedApplication endBackgroundTask:gTask];
        gTask = UIBackgroundTaskInvalid;
    }
}

+ (void)playerClosed {
    if (gInBackground && self.enabled && [VGEngine shared].activeCount > 0) [self startKeeping];
}

// Plays VidGrab's sound like a notification: ringer volume, and quiet when the phone is on silent.
+ (void)playFinishSound {
    static SystemSoundID sid;
    if (!sid) {
        NSURL *u = [NSBundle.mainBundle URLForResource:@"vidgrab-done" withExtension:@"wav"];
        if (u) AudioServicesCreateSystemSoundID((__bridge CFURLRef)u, &sid);
    }
    if (sid) AudioServicesPlaySystemSound(sid);
}

+ (void)testSoundLater:(BOOL)later completion:(void (^)(NSString *))done {
    NSMutableString *r = [NSMutableString string];
    UIApplication *app = UIApplication.sharedApplication;
    __block UIBackgroundTaskIdentifier bt = [app beginBackgroundTaskWithName:@"sound test" expirationHandler:^{ [app endBackgroundTask:bt]; bt = UIBackgroundTaskInvalid; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((later ? 5 : 0.2) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSURL *u = [NSBundle.mainBundle URLForResource:@"vidgrab-done" withExtension:@"wav"];
        NSNumber *size = nil;
        [u getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        [r appendFormat:@"version %@\n", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
        [r appendFormat:@"app was %@\n", app.applicationState == UIApplicationStateActive ? @"open" : @"in the background"];
        [r appendFormat:@"sound file: %@\n", u ? [NSString stringWithFormat:@"found, %@ bytes", size] : @"MISSING"];
        AVAudioSession *s = AVAudioSession.sharedInstance;
        [r appendFormat:@"media volume: %d%%\n", (int)round(s.outputVolume * 100)];
        NSMutableArray *outs = [NSMutableArray array];
        for (AVAudioSessionPortDescription *o in s.currentRoute.outputs) [outs addObject:o.portType];
        [r appendFormat:@"speaker: %@\n", [outs componentsJoinedByString:@", "] ?: @"none"];
        [r appendFormat:@"sound session: %@, other audio playing: %@\n", [s.category stringByReplacingOccurrencesOfString:@"AVAudioSessionCategory" withString:@""],
                        s.isOtherAudioPlaying ? @"yes" : @"no"];

        // 1) like a notification (ringer volume, silent switch mutes it)
        SystemSoundID sid = 0;
        OSStatus st = u ? AudioServicesCreateSystemSoundID((__bridge CFURLRef)u, &sid) : -1;
        [r appendFormat:@"1) notification style: %@", st == 0 ? @"loaded" : [NSString stringWithFormat:@"failed to load (error %d)", (int)st]];
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        __block BOOL ended = NO;
        if (st == 0) AudioServicesPlaySystemSoundWithCompletion(sid, ^{ ended = YES; });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (st == 0) [r appendFormat:@", %@\n", ended ? @"played to the end" : [NSString stringWithFormat:@"did not finish in %.1fs", CFAbsoluteTimeGetCurrent() - t0]];
            else [r appendString:@"\n"];
            if (sid) AudioServicesDisposeSystemSoundID(sid);

            // 2) like music (media volume, ignores the silent switch)
            NSError *e = nil;
            if (!VGPlayerIsActive())
                [s setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:&e];
            BOOL active = [s setActive:YES error:&e];
            static AVAudioPlayer *p;
            NSError *pe = nil;
            p = u ? [[AVAudioPlayer alloc] initWithContentsOfURL:u error:&pe] : nil;
            BOOL played = [p play];
            [r appendFormat:@"2) music style: %@%@%@\n", p ? [NSString stringWithFormat:@"%.1fs long", p.duration] : [NSString stringWithFormat:@"failed to load (%@)", pe.localizedDescription],
                            played ? @", playing" : @", would not play", active ? @"" : [NSString stringWithFormat:@", sound session error: %@", e.localizedDescription]];

            [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *ns) {
                NSString *auth = @[@"not asked yet", @"turned off", @"on", @"quiet", @"on"][MIN((NSInteger)ns.authorizationStatus, 4)];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [r appendFormat:@"notifications: %@, sounds %@", auth, ns.soundSetting == UNNotificationSettingEnabled ? @"on" : @"off"];
                    done(r);
                    if (bt != UIBackgroundTaskInvalid) { [app endBackgroundTask:bt]; bt = UIBackgroundTaskInvalid; }
                });
            }];
        });
    });
}

+ (BOOL)notify {
    if (gDone + gFailed == 0) return NO;
    BOOL sound = VGOverlay.finishSound;
    if (sound) [self playFinishSound];
    UNMutableNotificationContent *c = [UNMutableNotificationContent new];
    if (gDone == 1 && gFailed == 0) {
        c.title = @"Download finished";
        c.body = gLastTitle.length ? [NSString stringWithFormat:@"%@ is ready to watch.", gLastTitle] : @"Your video is ready to watch.";
    } else if (gFailed == 0) {
        c.title = @"Downloads finished";
        c.body = [NSString stringWithFormat:@"%ld videos are ready to watch.", (long)gDone];
    } else {
        c.title = gDone ? @"Downloads finished" : @"Download didn't finish";
        c.body = gDone ? [NSString stringWithFormat:@"%ld saved, %ld didn't finish. Open VidGrab to try again.", (long)gDone, (long)gFailed]
                       : @"Open VidGrab to try again.";
    }
    // Only sent while you're outside VidGrab, so the sound never plays inside the app.
    c.sound = sound ? nil : UNNotificationSound.defaultSound;   // our own sound already played
    UNNotificationRequest *r = [UNNotificationRequest requestWithIdentifier:@"vg.downloads" content:c trigger:nil];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:r withCompletionHandler:nil];
    gDone = gFailed = 0;
    return sound;
}

@end
