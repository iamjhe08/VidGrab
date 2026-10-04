#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Bottom sheet that looks up a link, shows quality cards, and downloads.
@interface VGQualitySheet : UIViewController
- (instancetype)initWithURL:(NSString *)url fallbackURL:(nullable NSString *)fallback;
/// Present as a sheet (medium and large heights) from a view controller.
- (void)presentFrom:(UIViewController *)host;
@end

NS_ASSUME_NONNULL_END
