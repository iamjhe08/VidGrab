#import <UIKit/UIKit.h>
#import "VGEngine.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const VGMusicChangedNotification;   // track, play state or modes changed
extern NSString *const VGMusicTickNotification;      // about twice a second while playing

/// Playlists the viewer builds from songs in the Audio library. They only list songs; no file is copied.
@interface VGMusicPlaylists : NSObject
+ (NSArray<NSDictionary *> *)all;                                   // each: id, name, items (file names, in order)
+ (nullable NSDictionary *)withID:(NSString *)identifier;
+ (NSDictionary *)create:(NSString *)name items:(NSArray<NSString *> *)fileNames;
+ (void)rename:(NSString *)identifier to:(NSString *)name;
+ (void)remove:(NSString *)identifier;
+ (void)add:(NSArray<NSString *> *)fileNames to:(NSString *)identifier;
+ (void)removeFile:(NSString *)fileName from:(NSString *)identifier;
/// The playlist's songs, in the viewer's order. Songs that were deleted are skipped.
+ (NSArray<VGItem *> *)itemsIn:(NSString *)identifier;
@end
extern NSString *const VGMusicPlaylistsChanged;

/// The Library's music player: plays a list of songs one after another, with shuffle and repeat.
@interface VGMusicPlayer : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<VGItem *> *queue;
@property (nonatomic, readonly, nullable) VGItem *current;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic) BOOL shuffle;
@property (nonatomic) NSInteger repeatMode;   // 0 off, 1 all, 2 one
@property (nonatomic, readonly) double position, duration;
- (void)playQueue:(NSArray<VGItem *> *)items startAt:(NSUInteger)index;
- (void)togglePlay;
- (void)pause;
- (void)next;
- (void)previous;
- (void)seekTo:(double)seconds;
- (void)cycleRepeat;
- (void)toggleShuffle;
/// Stops and empties the player.
- (void)stop;
@end

/// The bar shown at the bottom of the Library. Collapsed it is a single row; tap it for the full controls.
@interface VGMiniMusicView : UIView
@property (nonatomic, copy, nullable) void (^onHeightChange)(void);
/// When set, tapping the bar's picture or arrow calls this (the Library opens the big player) instead of expanding the bar.
@property (nonatomic, copy, nullable) void (^onOpenPanel)(void);
/// Hidden on purpose (the big player is showing) even while a song plays.
@property (nonatomic) BOOL suppressed;
- (CGFloat)currentHeight;
- (void)refresh;
@end

/// The big player that sits over the Library's song list on the Audio tab: frosted glass, large cover, all controls.
@interface VGMusicPanel : UIVisualEffectView
@property (nonatomic, copy, nullable) void (^onMinimize)(void);
@end

NS_ASSUME_NONNULL_END
