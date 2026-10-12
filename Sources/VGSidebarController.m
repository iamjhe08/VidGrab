#import "VGSidebarController.h"
#import "VGTheme.h"
#import "VGHaptics.h"

NSString *const VGLayoutDidChangeNotification = @"VGLayoutDidChange";

static const CGFloat kSideWidth = 232;
static const CGFloat kWideEnough = 700;   // narrower than this (Split View, small window): use the tab bar

@interface VGSidebarController ()
@property (nonatomic, strong, readwrite) UITabBarController *tabs;
@property (nonatomic, strong) UIView *side;
@property (nonatomic, strong) UIView *edge;
@property (nonatomic, strong) UILabel *brand;
@property (nonatomic, strong) NSArray<UIButton *> *rows;
@property (nonatomic) BOOL observing;
@end

@implementation VGSidebarController

+ (BOOL)layoutOn { return [NSUserDefaults.standardUserDefaults boolForKey:@"vgIPadLayout"]; }
+ (void)setLayoutOn:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:@"vgIPadLayout"]; }

- (instancetype)initWithTabs:(UITabBarController *)tabs {
    if ((self = [super init])) _tabs = tabs;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VGScreen;

    self.side = [UIView new];
    self.side.backgroundColor = VGTabBarBg;
    self.edge = [UIView new];
    self.edge.backgroundColor = VGStroke;
    self.brand = [UILabel new];
    self.brand.text = @"VidGrab";
    self.brand.font = VGFont(26, UIFontWeightHeavy);
    self.brand.textColor = VGText;
    [self.side addSubview:self.brand];
    [self.side addSubview:self.edge];

    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.tabs.viewControllers.count; i++) {
        UITabBarItem *it = self.tabs.viewControllers[i].tabBarItem;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = (NSInteger)i;
        b.layer.cornerRadius = 12;
        b.layer.cornerCurve = kCACornerCurveContinuous;
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.titleLabel.font = VGFont(16, UIFontWeightSemibold);
        b.accessibilityLabel = it.title;
        [b addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.side addSubview:b];
        [rows addObject:b];
    }
    self.rows = rows;

    [self addChildViewController:self.tabs];
    [self.view addSubview:self.tabs.view];
    [self.view addSubview:self.side];
    [self.tabs didMoveToParentViewController:self];
    [self.tabs addObserver:self forKeyPath:@"selectedIndex" options:NSKeyValueObservingOptionNew context:nil];
    self.observing = YES;
    [self paintRows];
}

- (void)dealloc { [self stopObserving]; }

- (void)stopObserving {
    if (self.observing) { [self.tabs removeObserver:self forKeyPath:@"selectedIndex"]; self.observing = NO; }
}

- (void)releaseTabs {
    [self stopObserving];
    if (self.tabs.parentViewController == self) {
        [self.tabs willMoveToParentViewController:nil];
        [self.tabs.view removeFromSuperview];
        [self.tabs removeFromParentViewController];
    }
    self.tabs.tabBar.hidden = NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{ [self paintRows]; });
}

- (void)paintRows {
    NSInteger sel = self.tabs.selectedIndex;
    for (UIButton *b in self.rows) {
        UITabBarItem *it = self.tabs.viewControllers[(NSUInteger)b.tag].tabBarItem;
        BOOL on = b.tag == sel;
        UIImage *img = on && it.selectedImage ? it.selectedImage : it.image;
        UIImage *icon = [[img imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold]]
                         imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [b setImage:icon forState:UIControlStateNormal];
        [b setTitle:[@"  " stringByAppendingString:it.title ?: @""] forState:UIControlStateNormal];
        b.tintColor = on ? VGOn : VGSecondary;
        [b setTitleColor:on ? VGText : VGSecondary forState:UIControlStateNormal];
        b.backgroundColor = on ? VGSelectedBg : UIColor.clearColor;
        b.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 10);
    }
}

/// A new theme was picked: repaint the side list.
- (void)retheme {
    self.view.backgroundColor = VGScreen;
    self.side.backgroundColor = VGTabBarBg;
    self.edge.backgroundColor = VGStroke;
    self.brand.textColor = VGText;
    [self paintRows];
}

- (void)rowTapped:(UIButton *)b {
    [VGHaptics select];
    self.tabs.selectedIndex = (NSUInteger)b.tag;
    id<UITabBarControllerDelegate> d = self.tabs.delegate;
    if ([d respondsToSelector:@selector(tabBarController:didSelectViewController:)])
        [d tabBarController:self.tabs didSelectViewController:self.tabs.selectedViewController];
    [self paintRows];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    BOOL wide = W >= kWideEnough;
    CGFloat sw = wide ? kSideWidth : 0;
    self.side.hidden = !wide;
    self.tabs.tabBar.hidden = wide;
    self.tabs.view.frame = CGRectMake(sw, 0, W - sw, H);
    self.side.frame = CGRectMake(0, 0, sw, H);
    self.edge.frame = CGRectMake(sw - 1, 0, 1, H);
    CGFloat top = self.view.safeAreaInsets.top + 20;
    self.brand.frame = CGRectMake(24, top, sw - 48, 34);
    CGFloat y = top + 34 + 22;
    for (UIButton *b in self.rows) { b.frame = CGRectMake(12, y, sw - 24, 48); y += 54; }
}

- (UIViewController *)childViewControllerForStatusBarStyle { return self.tabs; }
- (UIViewController *)childViewControllerForStatusBarHidden { return self.tabs; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

@end
