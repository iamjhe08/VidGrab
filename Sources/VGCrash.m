#import "VGCrash.h"
#import <UIKit/UIKit.h>
#import <execinfo.h>
#import <fcntl.h>
#import <signal.h>
#import <sys/utsname.h>
#import <unistd.h>

static int gFD = -1;
static NSString *gPrevious = nil;
static NSString *gPreviousLast = nil;

static NSString *dir(void) {
    return NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
}
static NSString *runPath(void) { return [dir() stringByAppendingPathComponent:@"last-run.log"]; }

static void writeRaw(const char *s) {
    if (gFD >= 0 && s) write(gFD, s, strlen(s));
}

static void onSignal(int sig) {
    char buf[64];
    snprintf(buf, sizeof buf, "\nCRASH: signal %d\n", sig);
    writeRaw(buf);
    void *frames[64];
    int n = backtrace(frames, 64);
    if (gFD >= 0) backtrace_symbols_fd(frames, n, gFD);
    signal(sig, SIG_DFL);
    raise(sig);
}

static void onException(NSException *e) {
    NSString *s = [NSString stringWithFormat:@"\nCRASH: %@: %@\n%@\n", e.name, e.reason,
                   [e.callStackSymbols componentsJoinedByString:@"\n"]];
    writeRaw(s.UTF8String);
}

@implementation VGCrash

+ (void)install {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:dir() withIntermediateDirectories:YES attributes:nil error:nil];

    // Look at how the previous run ended.
    NSString *prev = [NSString stringWithContentsOfFile:runPath() encoding:NSUTF8StringEncoding error:nil];
    // "ON" is written when the app comes on screen, "OK" when it leaves (home screen, app switcher,
    // lock). Only a crash, or the app dying while on screen, counts. Force-closing never does,
    // because opening the app switcher already wrote "OK".
    NSRange lastOK = [prev rangeOfString:@"\nOK\n" options:NSBackwardsSearch];
    NSString *afterOK = lastOK.location == NSNotFound ? prev : [prev substringFromIndex:NSMaxRange(lastOK)];
    BOOL crashed = [afterOK containsString:@"CRASH:"];
    BOOL diedOnScreen = [afterOK containsString:@"\nON\n"];
    if (prev.length && (crashed || diedOnScreen)) {
        NSString *how = [prev containsString:@"CRASH:"] ? @"" : @"\n(No error was recorded: iOS probably closed the app, often because it ran out of memory.)\n";
        gPrevious = [prev stringByAppendingString:how];
        for (NSString *line in [prev componentsSeparatedByString:@"\n"].reverseObjectEnumerator) {
            if ([line hasPrefix:@"> "]) { gPreviousLast = [line substringFromIndex:2]; break; }
        }
    }

    gFD = open(runPath().fileSystemRepresentation, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    struct utsname u;
    uname(&u);
    NSString *header = [NSString stringWithFormat:@"VidGrab %@ · iOS %@ · %s · %@\n",
                        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                        UIDevice.currentDevice.systemVersion, u.machine, [NSDate date]];
    writeRaw(header.UTF8String);

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n) { writeRaw("\nON\n"); }];
    [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n) { writeRaw("\nOK\n"); }];
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification *n) { writeRaw("\nOK\n"); }];
    [nc addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *n) { writeRaw("\nOK\n"); }];

    NSSetUncaughtExceptionHandler(&onException);
    int sigs[] = {SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP};
    for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++) signal(sigs[i], onSignal);
}

+ (void)breadcrumb:(NSString *)step {
    NSString *line = [NSString stringWithFormat:@"> %@\n", step];
    writeRaw(line.UTF8String);
}

+ (void)markHealthy { /* no longer needed: leaving the screen marks a clean state */ }
+ (NSString *)previousReport { return gPrevious; }
+ (NSString *)previousLastStep { return gPreviousLast; }
+ (void)clearPreviousReport { gPrevious = nil; gPreviousLast = nil; }

@end
