#import <UIKit/UIKit.h>
#import "VGEngine.h"

NS_ASSUME_NONNULL_BEGIN

/// Shared actions for a finished download (used by Home and Downloads).
@interface VGActions : NSObject
+ (void)play:(VGItem *)item from:(UIViewController *)vc;
+ (void)saveToPhotos:(VGItem *)item from:(UIViewController *)vc;
+ (void)share:(VGItem *)item from:(UIViewController *)vc source:(UIView *)source;
+ (void)saveToFiles:(VGItem *)item from:(UIViewController *)vc;
+ (void)alert:(NSString *)title message:(nullable NSString *)message from:(UIViewController *)vc;
+ (void)toast:(NSString *)text icon:(NSString *)icon in:(UIView *)view;
@end

NS_ASSUME_NONNULL_END
