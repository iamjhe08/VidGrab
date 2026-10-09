#import <UIKit/UIKit.h>

/// The download bubble that stays on screen over other apps after you leave VidGrab,
/// like AssistiveTouch. Works when VidGrab is installed with TrollStore or on a jailbroken phone.
@interface VGOverlay : NSObject
@property (class, nonatomic) BOOL enabled;          // Settings switch, on by default
@property (class, nonatomic, readonly) BOOL supported;   // this install can show it
+ (void)start;
/// Installed as a jailbreak package. Floating progress (bubble and sound) only works there.
@property (class, nonatomic, readonly) BOOL fullInstall;
/// Settings > Sound when done: VidGrab's own sound for the "downloads finished" notification. Off by default.
@property (class, nonatomic) BOOL finishSound;
/// The bubble over other apps can run on this install (jailbreak packages only).
@property (class, nonatomic, readonly) BOOL bubbleAllowed;
/// ...and its background service is running right now.
+ (BOOL)realBubbleAvailable;
/// TrollStore: the VidGrab Bubble helper app is installed.
+ (BOOL)helperInstalled;
+ (BOOL)canInstallHelper;
+ (void)installHelperFrom:(UIViewController *)vc;
+ (BOOL)trollStoreInstall;
+ (BOOL)starterPresent;
/// Settings > Test bubble: shows a sample bubble for 20 seconds and reports what happened.
+ (void)testWithCompletion:(void (^)(BOOL ok, NSString *details))done;
@end
