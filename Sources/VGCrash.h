#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Small crash recorder. Each launch writes short "breadcrumbs" (what the app is doing)
/// to a file; crashes add the error and call stack. If the last run ended without
/// reaching "OK", the next launch can show the details so the user can copy them.
@interface VGCrash : NSObject
+ (void)install;
+ (void)breadcrumb:(NSString *)step;
/// Called once the app has been running normally for a few seconds.
+ (void)markHealthy;
/// The report from the previous run if it crashed or was closed by iOS, else nil.
+ (nullable NSString *)previousReport;
/// The last thing the previous run was doing before it ended badly.
+ (nullable NSString *)previousLastStep;
+ (void)clearPreviousReport;
@end

NS_ASSUME_NONNULL_END
