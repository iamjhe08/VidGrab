#import <UIKit/UIKit.h>

/// Settings: storage (cache size, Clear cache, Auto-clear switch), download engine, support, about.
@interface VGSettingsViewController : UITableViewController
/// Shows Settings as a sheet with a Done button.
+ (void)presentFrom:(UIViewController *)host;
@end
