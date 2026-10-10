#import <UIKit/UIKit.h>

/// Posted when "iPad layout" is switched in Settings.
extern NSString *const VGLayoutDidChangeNotification;

/// The iPad layout: a list of pages down the left side with the current page next to it, instead of the tab bar at the bottom.
/// It wraps the normal tab controller, so every page works as before. On a narrow window (Split View) the tab bar comes back.
@interface VGSidebarController : UIViewController
@property (class, nonatomic) BOOL layoutOn;
@property (nonatomic, readonly) UITabBarController *tabs;
- (instancetype)initWithTabs:(UITabBarController *)tabs;
/// Lets go of the tab controller so it can be shown on its own again.
- (void)releaseTabs;
/// Repaints the list after a theme change.
- (void)retheme;
@end
