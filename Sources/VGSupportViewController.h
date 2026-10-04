#import <UIKit/UIKit.h>

/// "Buy me a coffee" sheet. Donation details come from support.json in the app bundle.
@interface VGSupportViewController : UIViewController
- (void)presentFrom:(UIViewController *)host;
@end
