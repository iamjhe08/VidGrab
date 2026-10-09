#import <UIKit/UIKit.h>
#import <notify.h>
#import <spawn.h>

extern char **environ;
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *attr, uid_t persona_id, uint32_t flags);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *attr, uid_t uid);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *attr, uid_t gid);

#define N_ALIVE "com.t4mag0.vidgrab.hud.alive"

static BOOL Alive(void) {
    int t = 0; uint64_t v = 0;
    notify_register_check(N_ALIVE, &t);
    notify_get_state(t, &v);
    notify_cancel(t);
    return v > 0 && llabs((long long)time(NULL) - (long long)v) < 4;
}

@interface HelperApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UILabel *label;
@end

@implementation HelperApp

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.07 alpha:1];
    self.label = [UILabel new];
    self.label.numberOfLines = 0;
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.textColor = UIColor.whiteColor;
    self.label.font = [UIFont systemFontOfSize:16];
    self.label.text = @"Starting the VidGrab bubble...";
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:self.label];
    [NSLayoutConstraint activateConstraints:@[
        [self.label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
        [self.label.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:24],
        [self.label.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-24]]];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self go]; });
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)o {
    dispatch_async(dispatch_get_main_queue(), ^{ [self go]; });
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)app { }

- (void)go {
    if (Alive()) { [self finish]; return; }
    NSString *path = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"VidGrabHUD"];
    char *args[] = {(char *)path.fileSystemRepresentation, "-daemon", NULL};
    NSMutableString *report = [NSMutableString string];
    BOOL started = NO;
    for (int root = 1; root >= 0 && !started; root--) {
        posix_spawnattr_t attr;
        posix_spawnattr_init(&attr);
        if (root) {
            posix_spawnattr_set_persona_np(&attr, 99, 1);
            posix_spawnattr_set_persona_uid_np(&attr, 0);
            posix_spawnattr_set_persona_gid_np(&attr, 0);
        }
        pid_t pid = 0;
        int rc = posix_spawn(&pid, args[0], NULL, &attr, args, environ);
        posix_spawnattr_destroy(&attr);
        if (rc == 0) started = YES;
        else [report appendFormat:@"start %@ failed: %d (%s)\n", root ? @"as root" : @"as app", rc, strerror(rc)];
    }
    if (!started) {
        self.label.text = [NSString stringWithFormat:@"The bubble could not start.\n\n%@\nMake sure this app was installed with TrollStore.", report];
        return;
    }
    __block int tries = 0;
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        tries++;
        if (Alive()) { [t invalidate]; [self finish]; }
        else if (tries > 16) {
            [t invalidate];
            self.label.text = @"The bubble helper started but did not answer. Close this app and try again.";
        }
    }];
}

/// Back to VidGrab.
- (void)finish {
    self.label.text = @"Bubble is ready.";
    NSURL *u = [NSURL URLWithString:@"vidgrab://bubble-ready"];
    [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([HelperApp class])); }
}
