#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Checks the GitHub Releases page for a newer VidGrab and offers to install it.
@interface VGUpdater : NSObject
/// Quiet check each time the app opens. Only speaks up if there's an update.
+ (void)checkQuietlyFrom:(UIViewController *)host;
/// Check from Settings: always reports the result.
+ (void)checkNowFrom:(UIViewController *)host;
@end

NS_ASSUME_NONNULL_END
