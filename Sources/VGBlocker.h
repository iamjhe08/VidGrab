#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const VGBlockerDidChangeNotification;

/// Ad and tracker blocking for the built-in browser, using the filter lists
/// uBlock Origin Lite uses by default, converted to Apple's content-blocker rules.
@interface VGBlocker : NSObject
+ (instancetype)shared;
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL skipYouTubeAds;
@property (nonatomic, readonly) BOOL ready;
@property (nonatomic, readonly) NSUInteger ruleCount;

/// Compiles the bundled rules the first time (a few seconds), then loads them instantly.
- (void)prepare;
- (BOOL)isAllowedSite:(nullable NSString *)host;
- (void)setAllowed:(BOOL)allowed forSite:(NSString *)host;
/// Adds or removes the blocking rules on a browser for the given site.
- (void)applyTo:(WKUserContentController *)controller host:(nullable NSString *)host;
/// Script that skips YouTube video ads (only used on youtube.com).
+ (NSString *)youTubeAdSkipScript;
@end

NS_ASSUME_NONNULL_END
