#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Temporary files that are safe to delete: engine scratch files, leftover partial downloads,
/// saved site icons and the browser's page cache. Never touches downloads, sign-ins,
/// favorites or the ad-block rules.
@interface VGCache : NSObject
@property (class, nonatomic) BOOL autoClearOnLaunch;
/// Total size in bytes (computed in the background).
+ (void)size:(void (^)(long long bytes))completion;
/// Deletes the cache (running downloads keep their scratch files).
+ (void)clear:(void (^_Nullable)(long long freed))completion;
@end

NS_ASSUME_NONNULL_END
