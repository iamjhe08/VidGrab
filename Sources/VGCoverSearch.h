#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Finds album art on the internet (Apple's free music search; no account needed).
@interface VGCoverResult : NSObject
@property (nonatomic, copy) NSString *title, *artist, *album;
@property (nonatomic, strong) NSURL *smallURL, *bigURL;
@end

@interface VGCoverSearch : NSObject
+ (BOOL)autoEnabled;
+ (void)setAutoEnabled:(BOOL)on;
/// Up to 12 matches for the words given (a title, an artist, or both).
+ (void)search:(NSString *)terms completion:(void (^)(NSArray<VGCoverResult *> *results, NSString *_Nullable error))completion;
+ (void)loadImage:(NSURL *)url completion:(void (^)(UIImage *_Nullable image))completion;
/// Words that make a better search: removes things like "(Official Video)" or "[Lyrics]".
+ (NSString *)cleanedTerms:(NSString *)s;
@end

NS_ASSUME_NONNULL_END
