#import <UIKit/UIKit.h>
#import "VGEngine.h"
#import "VGUpdater.h"
#import "VGTheme.h"
#import "VGHomeViewController.h"
#import "VGDownloadsViewController.h"
#import "VGBrowserViewController.h"
#import "VGBlocker.h"
#import "VGProgressPill.h"
#import "VGCrash.h"
#import "VGCache.h"

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
    tab.backgroundColor = VGHex(0x0D0D11);
    tab.shadowColor = VGStroke;
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
    nav.titleTextAttributes = @{NSForegroundColorAttributeName: VGText, NSFontAttributeName: VGFont(17, UIFontWeightBold)};
    nav.largeTitleTextAttributes = @{NSForegroundColorAttributeName: VGText, NSFontAttributeName: VGFont(32, UIFontWeightHeavy)};
    UINavigationBar.appearance.standardAppearance = nav;
    UINavigationBar.appearance.scrollEdgeAppearance = nav;
    UINavigationBar.appearance.compactAppearance = nav;
    UINavigationBar.appearance.tintColor = VGAccent;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [VGCrash install];
    // If the last run ended badly while preparing the ad blocker, turn it off so the app can open.
    if ([[VGCrash previousLastStep] hasPrefix:@"adblock"]) [VGBlocker shared].enabled = NO;
    [VGCrash breadcrumb:@"launch"];
    if (VGCache.autoClearOnLaunch) [VGCache clear:nil];   // Settings > Auto-clear cache on launch
    [[VGEngine shared] start];
    // The ad blocker gets ready when Browse is first opened, not at launch.
    [self applyAppearance];

    self.home = [VGHomeViewController new];
    UINavigationController *homeNav = [[UINavigationController alloc] initWithRootViewController:self.home];
    homeNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Home" image:[UIImage systemImageNamed:@"house"]
                                               selectedImage:[UIImage systemImageNamed:@"house.fill"]];

    UINavigationController *browseNav = [[UINavigationController alloc] initWithRootViewController:[VGBrowserViewController new]];
    browseNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Browse" image:[UIImage systemImageNamed:@"safari"]
                                                 selectedImage:[UIImage systemImageNamed:@"safari.fill"]];

    UINavigationController *dlNav = [[UINavigationController alloc] initWithRootViewController:[VGDownloadsViewController new]];
    dlNav.navigationBar.prefersLargeTitles = YES;
    dlNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Downloads" image:[UIImage systemImageNamed:@"arrow.down.circle"]
                                             selectedImage:[UIImage systemImageNamed:@"arrow.down.circle.fill"]];

    self.tabs = [UITabBarController new];
    self.tabs.viewControllers = @[homeNav, browseNav, dlNav];
    self.tabs.tabBar.tintColor = VGText;

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
    self.pill = [VGProgressPill new];
    self.pill.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pill addTarget:self action:@selector(openDownloads) forControlEvents:UIControlEventTouchUpInside];
    [self.tabs.view addSubview:self.pill];
    [NSLayoutConstraint activateConstraints:@[
        [self.pill.trailingAnchor constraintEqualToAnchor:self.tabs.view.trailingAnchor constant:-16],
        // Above the tab bar (49 pt tall above the home indicator), anchored to the screen's safe area.
        [self.pill.bottomAnchor constraintEqualToAnchor:self.tabs.view.safeAreaLayoutGuide.bottomAnchor constant:-63],
    ]];
    [VGCrash breadcrumb:@"window ready"];
    return YES;
}

- (void)openDownloads {
    [[UIImpactFeedbackGenerator new] impactOccurred];
    self.tabs.selectedIndex = 2;
    self.pill.suppressed = NO;
}

- (void)tabBarController:(UITabBarController *)tc didSelectViewController:(UIViewController *)vc {
    self.pill.suppressed = tc.selectedIndex == 1;  // the browser has its own progress button
}

// vidgrab://download?url=<encoded link>  (for Shortcuts and share-sheet automations)
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)options {
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
