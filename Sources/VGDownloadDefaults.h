#import <Foundation/Foundation.h>
#import "VGEngine.h"

NS_ASSUME_NONNULL_BEGIN

/// The viewer's default choices for downloads (Settings > Downloads).
@interface VGDownloadDefaults : NSObject
/// -1 = always ask (the default), 0 = best available, otherwise the tallest picture to download (2160, 1440, 1080, 720, 480, 360).
@property (class, nonatomic) NSInteger quality;
/// -1 = always ask (the default), 0 = video, 1 = audio only.
@property (class, nonatomic) NSInteger kind;
/// Pieces of a video fetched at once (4, 8, 16 or 32; default 8). Helps with downloads that arrive in many small parts.
@property (class, nonatomic) NSInteger threads;
/// YES = downloads stay in Files only: every Save to Photos button is hidden.
@property (class, nonatomic) BOOL filesOnly;
+ (NSArray<NSNumber *> *)threadChoices;
/// The extra-info text for a download with the thread count added.
+ (NSString *)extraWithThreads:(NSString *)extra;
/// YES when this download's options should be hidden behind Files only.
/// YES when Settings > Downloads is set up (audio, or a chosen quality): Download starts straight away.
@property (class, readonly) BOOL skipSheet;
+ (NSArray<NSNumber *> *)qualityChoices;
+ (NSString *)nameForQuality:(NSInteger)q;
+ (NSString *)kindName;
/// The option to download without asking, or nil when the card should be shown.
+ (nullable VGOption *)autoPickFrom:(NSArray<VGOption *> *)options;
/// The option to preselect for these defaults. `current` is returned when the defaults ask for the best.
+ (NSInteger)indexIn:(NSArray<VGOption *> *)options current:(NSInteger)current;
@end

NS_ASSUME_NONNULL_END
