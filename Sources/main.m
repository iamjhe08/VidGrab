#import <UIKit/UIKit.h>
#import "VGEngine.h"
#import "VGUpdater.h"
#import "VGTheme.h"
#import "VGHomeViewController.h"
#import "VGDownloadsViewController.h"
#import "VGLibraryViewController.h"
#import "VGBrowserViewController.h"
#import "VGBlocker.h"
#import "VGProgressPill.h"
#import "VGCrash.h"
#import "VGCache.h"
#import "VGKeepAlive.h"
#import "VGOverlay.h"
#import "VGActions.h"

@interface VGAppDelegate : UIResponder <UIApplicationDelegate, UITabBarControllerDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UITabBarController *tabs;
@property (nonatomic, strong) VGHomeViewController *home;
@property (nonatomic, strong) VGProgressPill *pill;
@end

@implementation VGAppDelegate

- (void)applyAppearance {
    UITabBarAppearance *tab = [UITabBarAppearance new];
    [tab configureWithOpaqueBackground];
    tab.backgroundColor = VGTabBarBg;
    tab.shadowColor = VGStroke;
    if (VGPalette.current.glass) {   // glass theme: see-through bars with a blur
        [tab configureWithTransparentBackground];
        tab.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        tab.backgroundColor = [VGTabBarBg colorWithAlphaComponent:0.50];
        tab.shadowColor = [UIColor colorWithWhite:1 alpha:0.12];
    }
    UITabBarItemAppearance *item = [UITabBarItemAppearance new];
    item.normal.iconColor = VGTertiary;
    item.normal.titleTextAttributes = @{NSForegroundColorAttributeName: VGTertiary, NSFontAttributeName: VGFont(10, UIFontWeightSemibold)};
    item.selected.iconColor = VGText;
    item.selected.titleTextAttributes = @{NSForegroundColorAttributeName: VGText, NSFontAttributeName: VGFont(10, UIFontWeightBold)};
    tab.stackedLayoutAppearance = item;
    tab.inlineLayoutAppearance = item;
    tab.compactInlineLayoutAppearance = item;
    UITabBar.appearance.standardAppearance = tab;
    UITabBar.appearance.scrollEdgeAppearance = tab;

    UINavigationBarAppearance *nav = [UINavigationBarAppearance new];
    [nav configureWithOpaqueBackground];
    nav.backgroundColor = VGBackground;
    nav.shadowColor = UIColor.clearColor;
    if (VGPalette.current.glass) {
        [nav configureWithTransparentBackground];
        nav.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        nav.backgroundColor = [VGBackground colorWithAlphaComponent:0.55];
        nav.shadowColor = [UIColor colorWithWhite:1 alpha:0.08];
    }
    nav.titleTextAttributes = @{NSForegroundColorAttributeName: VGText, NSFontAttributeName: VGFont(17, UIFontWeightBold)};
    nav.largeTitleTextAttributes = @{NSForegroundColorAttributeName: VGText, NSFontAttributeName: VGFont(32, UIFontWeightHeavy)};
    UINavigationBar.appearance.standardAppearance = nav;
    UINavigationBar.appearance.scrollEdgeAppearance = nav;
    UINavigationBar.appearance.compactAppearance = nav;
    UINavigationBar.appearance.tintColor = VGAccent;
}

- (void)buildTabs {
    self.home = [VGHomeViewController new];
    UINavigationController *homeNav = [[UINavigationController alloc] initWithRootViewController:self.home];
    homeNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Home" image:[UIImage systemImageNamed:@"house"]
                                               selectedImage:[UIImage systemImageNamed:@"house.fill"]];

    UINavigationController *browseNav = [[UINavigationController alloc] initWithRootViewController:[VGBrowserViewController new]];
    browseNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Browse" image:[UIImage systemImageNamed:@"safari"]
                                                 selectedImage:[UIImage systemImageNamed:@"safari.fill"]];

    UINavigationController *libNav = [[UINavigationController alloc] initWithRootViewController:[VGLibraryViewController new]];
    libNav.navigationBar.prefersLargeTitles = YES;
    libNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Library" image:[UIImage systemImageNamed:@"books.vertical"]
                                              selectedImage:[UIImage systemImageNamed:@"books.vertical.fill"]];

    UINavigationController *dlNav = [[UINavigationController alloc] initWithRootViewController:[VGDownloadsViewController new]];
    dlNav.navigationBar.prefersLargeTitles = YES;
    dlNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Downloads" image:[UIImage systemImageNamed:@"arrow.down.circle"]
                                             selectedImage:[UIImage systemImageNamed:@"arrow.down.circle.fill"]];

    self.tabs = [UITabBarController new];
    self.tabs.viewControllers = @[homeNav, browseNav, libNav, dlNav];
    self.tabs.tabBar.tintColor = VGText;
}

- (void)rebuildForTheme {
    // The mini video player lives on top of the tab bar; to be safe, a theme picked while it is open applies next launch.
    extern BOOL VGPlayerIsActive(void);
    if (VGPlayerIsActive()) return;
    NSInteger sel = self.tabs.selectedIndex;
    [self.pill removeFromSuperview];
    [self applyAppearance];
    [self buildTabs];
    self.tabs.selectedIndex = MIN(sel, (NSInteger)self.tabs.viewControllers.count - 1);
    self.tabs.delegate = self;
    self.window.backgroundColor = VGBackground;
    self.window.tintColor = VGAccent;
    [UIView transitionWithView:self.window duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ self.window.rootViewController = self.tabs; } completion:nil];
    self.pill = [VGProgressPill new];
    [self.pill addTarget:self action:@selector(openDownloads) forControlEvents:UIControlEventTouchUpInside];
    [self.tabs.view addSubview:self.pill];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [VGCrash install];
    // If the last run ended badly while preparing the ad blocker, turn it off so the app can open.
    if ([[VGCrash previousLastStep] hasPrefix:@"adblock"]) [VGBlocker shared].enabled = NO;
    [VGCrash breadcrumb:@"launch"];
    if (VGCache.autoClearOnLaunch) [VGCache clear:nil];   // Settings > Auto-clear cache on launch
    [[VGEngine shared] start];
    [VGKeepAlive start];
    [VGOverlay start];
    // The ad blocker gets ready when Browse is first opened, not at launch.
    [self applyAppearance];

    [self buildTabs];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.backgroundColor = VGBackground;
    self.window.tintColor = VGAccent;
    self.window.rootViewController = self.tabs;
    [self.window makeKeyAndVisible];
    // Look for a newer VidGrab on GitHub every time the app opens or comes back to the front.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [VGUpdater checkQuietlyFrom:self.tabs];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
                                                         queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [VGUpdater checkQuietlyFrom:self.tabs];
            });
        }];
    });

    // Download progress, visible on Home and Downloads (Browse shows it on its own button).
    self.tabs.delegate = self;
    // A round bubble you can drag anywhere; it snaps to the nearest side and remembers its spot.
    self.pill = [VGProgressPill new];
    [self.pill addTarget:self action:@selector(openDownloads) forControlEvents:UIControlEventTouchUpInside];
    [self.tabs.view addSubview:self.pill];
    // Downloads > Select shows its own action bar where the bubble sits, so step aside.
    [NSNotificationCenter.defaultCenter addObserverForName:@"VGSelectModeDidChange" object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *n) {
        self.pill.suppressed = [n.object boolValue] || self.tabs.selectedIndex == 1;
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:VGThemeDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *n) { [self rebuildForTheme]; }];
    [VGCrash breadcrumb:@"window ready"];
    return YES;
}

- (void)openDownloads {
    [[UIImpactFeedbackGenerator new] impactOccurred];
    self.tabs.selectedIndex = 3;
    self.pill.suppressed = NO;
}

- (void)tabBarController:(UITabBarController *)tc didSelectViewController:(UIViewController *)vc {
    self.pill.suppressed = tc.selectedIndex == 1;  // the browser has its own progress button
}

// The app stays upright, except while the video player is showing.
- (UIInterfaceOrientationMask)application:(UIApplication *)app supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) return UIInterfaceOrientationMaskAll;
    return VGPlayerIsOnScreen() ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
}

// vidgrab://download?url=<encoded link>  (for Shortcuts and share-sheet automations)
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)options {
    if ([url.host isEqualToString:@"bubble-ready"]) return YES;   // the Bubble helper app sends you back here
    // vidgrab://downloads  (tapping the floating bubble over another app)
    if ([url.host isEqualToString:@"downloads"]) {
        UIViewController *shown = self.tabs.presentedViewController;
        if (shown && ![shown isKindOfClass:NSClassFromString(@"VGPlayerViewController")]) [shown dismissViewControllerAnimated:NO completion:nil];
        self.tabs.selectedIndex = 3;
        self.pill.suppressed = NO;
        return YES;
    }
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *link = nil;
    for (NSURLQueryItem *q in c.queryItems) if ([q.name isEqualToString:@"url"]) link = q.value;
    if (!link.length) return NO;
    self.tabs.selectedIndex = 0;
    self.pill.suppressed = NO;
    [self.home loadLink:link];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(VGAppDelegate.class));
    }
}
