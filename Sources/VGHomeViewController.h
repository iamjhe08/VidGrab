#import <UIKit/UIKit.h>

@interface VGHomeViewController : UIViewController
- (void)loadLink:(NSString *)link;
/// A link from Share or the background: starts the download by itself when Settings > Downloads has a default type and quality.
- (void)loadSharedLink:(NSString *)link;
@end
