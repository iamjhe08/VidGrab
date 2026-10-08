#import <UIKit/UIKit.h>

/// Settings > Backup: save VidGrab's settings to a file, and load them back
/// (on this phone after reinstalling, or on another phone).
@interface VGSettingsBackup : NSObject
+ (void)exportFrom:(UIViewController *)vc;
+ (void)importFrom:(UIViewController *)vc completion:(void (^)(void))done;
@end
