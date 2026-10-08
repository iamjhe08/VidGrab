#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Bottom sheet that looks up a link, shows quality cards, and downloads.
@interface VGQualitySheet : UIViewController
- (instancetype)initWithURL:(NSString *)url fallbackURL:(nullable NSString *)fallback;
/// Streams the browser caught while the page played (url, kind, headers, title, label). They are tried when the page link itself fails.
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *candidates;
/// Set by the browser: when nothing is found, suggest playing the video first.
@property (nonatomic) BOOL fromBrowser;
/// Present as a sheet (medium and large heights) from a view controller.
- (void)presentFrom:(UIViewController *)host;
@end

NS_ASSUME_NONNULL_END
