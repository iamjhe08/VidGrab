#import <UIKit/UIKit.h>
#import "VGCustomTheme.h"

/// The editor for one custom theme. It works on a copy, so nothing changes until Save.
@interface VGCustomThemeViewController : UIViewController
/// `spec` is a copy of a saved theme (isNew NO) or a fresh one made from a preset (isNew YES).
+ (void)presentFrom:(UIViewController *)host spec:(VGThemeSpec *)spec isNew:(BOOL)isNew onSaved:(void (^)(VGThemeSpec *saved))onSaved;
@end
