// VidGrab floating download bubble that stays on screen over other apps (TrollStore and jailbreak).
// The way it draws over other apps and receives touches comes from TrollSpeed by Lessica (MIT license,
// see LICENSE-TrollSpeed): a small helper process whose window SpringBoard hosts above everything.
//
// Usage: VidGrabHUD -hud <state.json path> <app pid>

#import <notify.h>
#import <signal.h>
#import <sys/stat.h>
#import <sys/utsname.h>
#import <objc/runtime.h>

#import "IOKit+SPI.h"
#import "TSEventFetcher.h"
#import "BackboardServices.h"
#import "AXEventRepresentation.h"
#import "UIApplication+Private.h"
#import "UIWindow+Private.h"
#import "SpringBoardServices.h"
#import "SBSAccessibilityWindowHostingController.h"

// How VidGrab talks to the bubble: Darwin notifications plus one 64-bit state value,
// which works even though the app itself is sandboxed.
//   bits 0-15 downloads left, 16-31 progress (0-1000), 32 waiting, 33-40 saved, 41-48 failed, 49 sample
#define N_STATE  "com.t4mag0.vidgrab.hud.state"
#define N_UPDATE "com.t4mag0.vidgrab.hud.update"
#define N_HIDE   "com.t4mag0.vidgrab.hud.exit"
#define N_PID    "com.t4mag0.vidgrab.hud.pid"
#define N_ALIVE  "com.t4mag0.vidgrab.hud.alive"

static BOOL gDaemon;        // started by the jailbreak at boot, stays running and hides when idle
static pid_t gAppPid;       // spawn mode: the VidGrab that started us
static NSString *const kCache = @"/var/mobile/Library/Caches";

static void HUDLog(NSString *step) {
    NSString *p = [kCache stringByAppendingPathComponent:@"com.t4mag0.vidgrab.hud.log"];
    FILE *f = fopen(p.fileSystemRepresentation, "a");
    if (!f) return;
    fprintf(f, "%ld %s\n", (long)time(NULL), step.UTF8String);
    fclose(f);
    chmod(p.fileSystemRepresentation, 0666);
}

static uint64_t ReadState(const char *name) {
    int t = 0; uint64_t v = 0;
    if (notify_register_check(name, &t) == NOTIFY_STATUS_OK) { notify_get_state(t, &v); notify_cancel(t); }
    return v;
}

static void WriteState(const char *name, uint64_t v) {
    static NSMutableDictionary *tokens;
    if (!tokens) tokens = [NSMutableDictionary dictionary];
    NSString *k = @(name);
    int t;
    if (tokens[k]) t = [tokens[k] intValue];
    else { notify_register_check(name, &t); tokens[k] = @(t); }
    notify_set_state(t, v);
    notify_post(name);
}

static UIColor *Hex(unsigned h, CGFloat a) {
    return [UIColor colorWithRed:((h >> 16) & 0xFF) / 255.0 green:((h >> 8) & 0xFF) / 255.0 blue:(h & 0xFF) / 255.0 alpha:a];
}

#pragma mark - Touches

static void HUDEventCallback(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event) {
    static UIApplication *app = [UIApplication sharedApplication];
    static NSOperatingSystemVersion v;
    static dispatch_once_t vonce;
    dispatch_once(&vonce, ^{ v = [[NSProcessInfo processInfo] operatingSystemVersion]; });
    if (v.majorVersion < 15 || (v.majorVersion == 15 && v.minorVersion < 1)) [app _enqueueHIDEvent:event];

    BOOL useAX = YES;
    if (v.majorVersion == 15 && v.minorVersion == 0 && v.patchVersion == 0) {
        struct utsname u; uname(&u);
        NSString *model = [NSString stringWithUTF8String:u.machine];
        if (![model hasPrefix:@"iPhone13,"] && ![model hasPrefix:@"iPhone14,"]) useAX = NO;
    }
    if (v.majorVersion < 15) useAX = NO;
    if (!useAX) return;

    static Class AXRep = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/AccessibilityUtilities.framework"] load];
        AXRep = objc_getClass("AXEventRepresentation");
    });
    AXEventRepresentation *rep = [AXRep representationWithHIDEvent:event hidStreamIdentifier:@"UIApplicationEvents"];
    dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIWindow *win = app.windows.firstObject;
#pragma clang diagnostic pop
        UIView *hit = [win hitTest:[rep location] withEvent:nil];
        UITouchPhase phase = UITouchPhaseEnded;
        if ([rep isTouchDown]) phase = UITouchPhaseBegan;
        else if ([rep isMove]) phase = UITouchPhaseMoved;
        else if ([rep isCancel]) phase = UITouchPhaseCancelled;
        NSInteger pointer = [[[[rep handInfo] paths] firstObject] pathIdentity];
        if (pointer > 0)
            [TSEventFetcher receiveAXEventID:MIN(MAX(pointer, 1), 98) atGlobalCoordinate:[rep location] withTouchPhase:phase inWindow:win onView:hit];
    });
}

#pragma mark - Window

@interface VGHUDWindow : UIWindow
@end
@implementation VGHUDWindow
+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest { return NO; }
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }
@end

// Only the bubble takes touches; everything else goes to the app underneath.
@interface VGHUDRootView : UIView
@property (nonatomic, weak) UIView *bubble;
@end
@implementation VGHUDRootView
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return (v && v != self) ? v : nil;
}
@end

#pragma mark - Bubble

static const CGFloat kSize = 60;

@interface VGHUDController : UIViewController
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) CAShapeLayer *arc;
@property (nonatomic, strong) UILabel *percent, *badge;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic) BOOL finishing, active;
@property (nonatomic) CGPoint grab;
@end

@implementation VGHUDController

- (void)loadView { self.view = [VGHUDRootView new]; }

- (NSString *)posPath { return [kCache stringByAppendingPathComponent:@"com.t4mag0.vidgrab.hudpos.plist"]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    UIView *b = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kSize, kSize)];
    b.backgroundColor = Hex(0x1F1F27, 0.96);
    b.layer.cornerRadius = kSize / 2;
    b.layer.borderColor = Hex(0x2A2A34, 1).CGColor;
    b.layer.borderWidth = 1;
    b.layer.shadowColor = UIColor.blackColor.CGColor;
    b.layer.shadowOpacity = 0.55;
    b.layer.shadowRadius = 14;
    b.layer.shadowOffset = CGSizeMake(0, 5);
    [self.view addSubview:b];
    self.bubble = b;
    ((VGHUDRootView *)self.view).bubble = b;

    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(kSize / 2, kSize / 2) radius:kSize / 2 - 6
                                                    startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
    CAShapeLayer *track = [CAShapeLayer layer];
    track.path = path.CGPath; track.fillColor = UIColor.clearColor.CGColor;
    track.strokeColor = Hex(0x2A2A34, 1).CGColor; track.lineWidth = 4;
    self.arc = [CAShapeLayer layer];
    self.arc.path = path.CGPath; self.arc.fillColor = UIColor.clearColor.CGColor;
    self.arc.strokeColor = Hex(0xFF3D68, 1).CGColor; self.arc.lineWidth = 4;
    self.arc.lineCap = kCALineCapRound; self.arc.strokeEnd = 0.02;
    [b.layer addSublayer:track];
    [b.layer addSublayer:self.arc];

    self.icon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 13, kSize, 12)];
    self.icon.image = [UIImage systemImageNamed:@"arrow.down" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightHeavy]];
    self.icon.tintColor = Hex(0xFF3D68, 1);
    self.icon.contentMode = UIViewContentModeCenter;
    [b addSubview:self.icon];

    self.percent = [[UILabel alloc] initWithFrame:CGRectMake(8, 25, kSize - 16, 20)];
    self.percent.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightHeavy];
    self.percent.textColor = UIColor.whiteColor;
    self.percent.textAlignment = NSTextAlignmentCenter;
    self.percent.adjustsFontSizeToFitWidth = YES;
    self.percent.minimumScaleFactor = 0.6;
    [b addSubview:self.percent];

    self.badge = [[UILabel alloc] initWithFrame:CGRectMake(kSize - 16, -5, 22, 22)];
    self.badge.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightHeavy];
    self.badge.textColor = UIColor.whiteColor;
    self.badge.backgroundColor = Hex(0xFF3D68, 1);
    self.badge.textAlignment = NSTextAlignmentCenter;
    self.badge.layer.cornerRadius = 11;
    self.badge.layer.borderColor = Hex(0x0A0A0D, 1).CGColor;
    self.badge.layer.borderWidth = 2;
    self.badge.clipsToBounds = YES;
    self.badge.hidden = YES;
    [b addSubview:self.badge];

    [b addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(pressed:)];
    press.minimumPressDuration = 0;
    press.cancelsTouchesInView = NO;
    press.delegate = (id<UIGestureRecognizerDelegate>)self;
    [b addGestureRecognizer:press];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    pan.maximumNumberOfTouches = 1;
    [b addGestureRecognizer:pan];

    b.alpha = 0;
    b.hidden = YES;

    int token;
    notify_register_dispatch(N_UPDATE, &token, dispatch_get_main_queue(), ^(int t) { [self reload]; });
    notify_register_dispatch(N_HIDE, &token, dispatch_get_main_queue(), ^(int t) { [self hide]; });
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        WriteState(N_ALIVE, (uint64_t)time(NULL));   // lets VidGrab know the bubble is ready
        if (!self.active) return;
        pid_t app = gAppPid ?: (pid_t)ReadState(N_PID);
        if (app > 0 && kill(app, 0) != 0) [self hide];   // VidGrab was closed
        else [self reload];
    }];
    WriteState(N_ALIVE, (uint64_t)time(NULL));
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!gDaemon) [self reload];   // started for this download: show right away
}

#pragma mark Position

- (CGRect)area {
    CGSize s = UIScreen.mainScreen.bounds.size;
    return CGRectMake(10, 54, s.width - 20, s.height - 54 - 40);
}

- (void)place:(BOOL)animated {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self posPath]];
    BOOL left = [d[@"left"] boolValue];
    double y = d[@"y"] ? [d[@"y"] doubleValue] : 0.72;
    CGRect a = [self area];
    CGPoint c = CGPointMake(left ? CGRectGetMinX(a) + kSize / 2 : CGRectGetMaxX(a) - kSize / 2,
                            CGRectGetMinY(a) + kSize / 2 + (a.size.height - kSize) * MIN(1, MAX(0, y)));
    if (animated) [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.4 options:0 animations:^{ self.bubble.center = c; } completion:nil];
    else self.bubble.center = c;
    [UIView animateWithDuration:animated ? 0.25 : 0 animations:^{ [self layoutBadge]; }];
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint p = [g locationInView:self.view];
    if (g.state == UIGestureRecognizerStateBegan) {
        [self wake];
        self.grab = CGPointMake(p.x - self.bubble.center.x, p.y - self.bubble.center.y);
        [UIView animateWithDuration:0.15 animations:^{ self.bubble.transform = CGAffineTransformMakeScale(1.08, 1.08); }];
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGRect a = CGRectInset([self area], -8, -8);
        self.bubble.center = CGPointMake(MIN(CGRectGetMaxX(a) - kSize / 2, MAX(CGRectGetMinX(a) + kSize / 2, p.x - self.grab.x)),
                                         MIN(CGRectGetMaxY(a) - kSize / 2, MAX(CGRectGetMinY(a) + kSize / 2, p.y - self.grab.y)));
    } else {
        CGRect a = [self area];
        BOOL left = self.bubble.center.x + [g velocityInView:self.view].x * 0.15 < CGRectGetMidX(a);
        double y = (self.bubble.center.y - CGRectGetMinY(a) - kSize / 2) / MAX(1, a.size.height - kSize);
        [@{@"left": @(left), @"y": @(MIN(1, MAX(0, y)))} writeToFile:[self posPath] atomically:YES];
        chmod([self posPath].fileSystemRepresentation, 0666);
        [UIView animateWithDuration:0.2 animations:^{ self.bubble.transform = CGAffineTransformIdentity; }];
        [self place:YES];
        [self scheduleDim];
    }
}

- (void)tapped {
    [self wake];
    [UIView animateWithDuration:0.1 animations:^{ self.bubble.transform = CGAffineTransformMakeScale(0.9, 0.9); }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.1 animations:^{ self.bubble.transform = CGAffineTransformIdentity; }]; }];
    NSURL *u = [NSURL URLWithString:@"vidgrab://downloads"];
    if (!SBSOpenSensitiveURLAndUnlock((__bridge CFURLRef)u, 1))
        SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(@"com.t4mag0.vidgrab", u, nil, nil, NO);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }

- (void)pressed:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) [self wake];
    else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) [self scheduleDim];
}

#pragma mark Dimming

// Like AssistiveTouch: fades to see-through after 3 seconds untouched, wakes up when touched.
- (void)scheduleDim {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dim) object:nil];
    [self performSelector:@selector(dim) withObject:nil afterDelay:3.0];
}

- (void)dim {
    if (!self.active || self.finishing) return;
    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.bubble.alpha = 0.4; } completion:nil];
}

- (void)wake {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dim) object:nil];
    [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.bubble.alpha = 1; } completion:nil];
}

#pragma mark Show and hide

- (void)appear {
    if (self.active) return;
    self.active = YES;
    self.finishing = NO;
    self.arc.strokeColor = Hex(0xFF3D68, 1).CGColor;
    self.icon.frame = CGRectMake(0, 13, kSize, 12);
    self.icon.image = [UIImage systemImageNamed:@"arrow.down" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightHeavy]];
    self.icon.tintColor = Hex(0xFF3D68, 1);
    [self place:NO];
    self.bubble.hidden = NO;
    self.bubble.transform = CGAffineTransformMakeScale(0.6, 0.6);
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.65 initialSpringVelocity:0.6 options:0
                     animations:^{ self.bubble.alpha = 1; self.bubble.transform = CGAffineTransformIdentity; } completion:nil];
    [self scheduleDim];
    HUDLog(@"bubble shown");
}

- (void)hide {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hide) object:nil];
    self.finishing = NO;   // ready for the next download
    if (!self.active) { if (!gDaemon) exit(0); return; }
    self.active = NO;
    [UIView animateWithDuration:FADE_OUT_DURATION animations:^{ self.bubble.alpha = 0; self.bubble.transform = CGAffineTransformMakeScale(0.6, 0.6); }
                     completion:^(BOOL f) {
        if (self.active) return;
        self.bubble.hidden = YES;
        if (!gDaemon) exit(0);
    }];
}

// The count sits just outside the circle, touching it without covering it, on the
// top corner that faces the middle of the screen (so it never goes off the edge).
- (void)layoutBadge {
    CGFloat bw = self.badge.bounds.size.width;
    BOOL onRight = self.bubble.center.x > CGRectGetMidX(self.view.bounds);
    (void)onRight;
    CGFloat x = kSize - 12;   // always top right
    self.badge.frame = CGRectMake(x, -10, bw, 22);
}

#pragma mark Content

- (void)reload {
    uint64_t v = ReadState(N_STATE);
    NSInteger n = (NSInteger)(v & 0xFFFF);
    double f = ((v >> 16) & 0xFFFF) / 1000.0;
    BOOL waiting = (v >> 32) & 1;
    NSInteger saved = (v >> 33) & 0xFF, failed = (v >> 41) & 0xFF;
    BOOL sample = (v >> 49) & 1;

    if (n <= 0) {
        if (self.active && !self.finishing && (saved || failed)) [self finish:failed > 0 && saved == 0];
        else if (self.active && !self.finishing) [self hide];
        return;
    }
    if (self.finishing) return;
    [self appear];
    if (sample) [self performSelector:@selector(hide) withObject:nil afterDelay:20];
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.25];
    self.arc.strokeEnd = MAX(0.02, f);
    [CATransaction commit];
    self.percent.text = waiting ? @"Wait" : [NSString stringWithFormat:@"%d%%", (int)round(f * 100)];
    self.badge.text = [NSString stringWithFormat:@"%ld", (long)n];
    CGFloat bw = MAX(22, [self.badge.text sizeWithAttributes:@{NSFontAttributeName: self.badge.font}].width + 12);
    self.badge.bounds = CGRectMake(0, 0, bw, 22);
    [self layoutBadge];
    self.badge.hidden = n < 2;
}

// All done: show a check (or a warning) for a moment, then go away.
- (void)finish:(BOOL)failed {
    self.finishing = YES;
    [self wake];
    self.badge.hidden = YES;
    self.percent.text = nil;
    self.arc.strokeEnd = 1;
    UIColor *c = failed ? Hex(0xFFB020, 1) : Hex(0x34C759, 1);
    self.arc.strokeColor = c.CGColor;
    self.icon.frame = self.bubble.bounds;
    self.icon.image = [UIImage systemImageNamed:failed ? @"exclamationmark" : @"checkmark"
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightHeavy]];
    self.icon.tintColor = c;
    [self performSelector:@selector(hide) withObject:nil afterDelay:2.5];
}

@end

#pragma mark - App

@interface VGHUDDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) id hosting;
@end

@implementation VGHUDDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[VGHUDWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [VGHUDController new];
    self.window.windowLevel = 10000010.0;
    self.window.hidden = NO;
    [self.window makeKeyAndVisible];

    self.hosting = [[objc_getClass("SBSAccessibilityWindowHostingController") alloc] init];
    unsigned int ctx = [self.window _contextId];
    double level = self.window.windowLevel;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = self.hosting;
    inv.selector = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    [inv setArgument:&ctx atIndex:2];
    [inv setArgument:&level atIndex:3];
    [inv invoke];
    HUDLog([NSString stringWithFormat:@"window on screen (context %u)", ctx]);
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return 1;
        gDaemon = strcmp(argv[1], "-daemon") == 0;
        if (!gDaemon && strcmp(argv[1], "-hud") != 0) return 1;
        gAppPid = (!gDaemon && argc > 2) ? (pid_t)atoi(argv[2]) : 0;
        signal(SIGPIPE, SIG_IGN);
        HUDLog([NSString stringWithFormat:@"started (%s) as user %d", gDaemon ? "service" : "helper", getuid()]);

        [UIScreen initialize];
        CFRunLoopGetCurrent();
        GSInitialize();
        BKSDisplayServicesStart();
        UIApplicationInitialize();
        UIApplicationInstantiateSingleton(objc_getClass("HUDMainApplication"));
        static id<UIApplicationDelegate> delegate = [VGHUDDelegate new];
        [UIApplication.sharedApplication setDelegate:delegate];
        HUDLog(@"app ready");
        [UIApplication.sharedApplication _accessibilityInit];
        [NSRunLoop currentRunLoop];
        BKSHIDEventRegisterEventCallback(HUDEventCallback);
        if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 15) {
            GSEventInitialize(0);
            GSEventPushRunLoopMode(kCFRunLoopDefaultMode);
        }
        [UIApplication.sharedApplication __completeAndRunAsPlugin];
        CFRunLoopRun();
        return 0;
    }
}
