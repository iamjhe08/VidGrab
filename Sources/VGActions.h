#import <UIKit/UIKit.h>
#import "VGEngine.h"

#import <AVKit/AVKit.h>

NS_ASSUME_NONNULL_BEGIN

@class VGItem;

/// VidGrab's own video player: themed controls, live scrubbing, screen size, speed,
/// picture-in-picture, background sound, lock screen controls and resume.
@interface VGPlayerViewController : UIViewController
+ (instancetype)playerFor:(VGItem *)item;
/// Builds something the player can play from the links `-[VGEngine streamLinkFor:]` found. The item joins picture and sound when they come separately.
+ (void)prepareStream:(NSDictionary *)info completion:(void (^)(AVPlayerItem *_Nullable item, NSString *_Nullable error))completion;
/// A player for a video that streams from the internet. Shows a download button that saves it (in `option`'s quality) to Downloads.
+ (instancetype)playerForStreamItem:(AVPlayerItem *)item video:(VGVideo *)video option:(nullable VGOption *)option audio:(BOOL)audio;
/// A thin progress line along the bottom edge while the controls are hidden (Settings > Video player).
@property (class, nonatomic) BOOL miniProgressEnabled;
/// YES when the stream is a main playlist the player can limit by quality without reloading.
@property (nonatomic) BOOL streamMaster;
/// Every quality that can be switched to at once (from the stream lookup): height -> items to play.
@property (nonatomic, copy, nullable) NSDictionary *streamVariants;
/// Called when the video plays to the end (used to move on to the next track of a streamed playlist).
@property (nonatomic, copy, nullable) void (^onEnded)(VGPlayerViewController *player);
/// Playlist mode: shows previous and next buttons, shuffle and repeat. `onSkip` gets -1 (back) or +1 (next).
@property (nonatomic) BOOL playlistMode;
/// How far above the bottom a message should sit so it clears the open track list (0 when the list is closed).
- (CGFloat)trackSheetLift;
- (void)say:(NSString *)text icon:(NSString *)icon;   // a short message in the right spot: top centre, or above the Tracks list when it is open
@property (nonatomic, copy, nullable) void (^onSkip)(VGPlayerViewController *player, NSInteger direction);
/// Playlist mode: the track list for the "Tracks" button. Returns @{@"titles": NSArray<NSString *>, @"current": NSNumber}.
@property (nonatomic, copy, nullable) NSDictionary *(^trackProvider)(void);
/// Playlist mode: the viewer picked a track from the list (its position in the play order).
@property (nonatomic, copy, nullable) void (^onPickTrack)(NSInteger position);
/// Playlist mode: hide the picture and show the VidGrab banner (the sound keeps playing).
@property (nonatomic) BOOL videoOff;
@property (nonatomic) BOOL shuffleOn;
@property (nonatomic) NSInteger repeatMode;   // 0 off, 1 all, 2 one
/// Called when the viewer taps shuffle or repeat.
@property (nonatomic, copy, nullable) void (^onModeChange)(BOOL shuffle, NSInteger repeat);
@property (nonatomic, copy, nullable) NSString *positionText;   // for example "3 of 12"
/// Plays another stream inside this same player, with no closing or reopening.
- (void)swapToStreamItem:(AVPlayerItem *)item video:(VGVideo *)video audio:(BOOL)audio master:(BOOL)master variants:(nullable NSDictionary *)variants position:(NSString *)position;
/// Moves the playing stream to another quality, keeping the position.
- (void)switchToOption:(VGOption *)opt;
/// Starts the current track again from the beginning (repeat one).
- (void)restartTrack;
/// Shows the paused end state (the playlist is over).
- (void)showFinished;
/// Seconds into the current track.
- (double)currentSeconds;
/// A short message over the picture.
- (void)showMessage:(NSString *)text;
- (void)start;
@end

/// A video player is on screen or about to appear (the app allows landscape only then).
BOOL VGPlayerIsOnScreen(void);

/// Shared actions for a finished download (used by Home and Downloads).
@interface VGActions : NSObject
+ (void)play:(VGItem *)item from:(UIViewController *)vc;
+ (void)saveToPhotos:(VGItem *)item from:(UIViewController *)vc;
+ (void)share:(VGItem *)item from:(UIViewController *)vc source:(UIView *)source;
+ (void)saveToFiles:(VGItem *)item from:(UIViewController *)vc;
+ (void)alert:(NSString *)title message:(nullable NSString *)message from:(UIViewController *)vc;
+ (void)toast:(NSString *)text icon:(NSString *)icon in:(UIView *)view;
/// Same, with the message sitting `bottom` points above the bottom safe area (the default is 70).
+ (void)toast:(NSString *)text icon:(NSString *)icon in:(UIView *)view bottom:(CGFloat)bottom;
+ (void)toast:(NSString *)text icon:(NSString *)icon in:(UIView *)view top:(CGFloat)top;

/// Several downloads at once (Downloads > Select).
+ (void)saveItemsToPhotos:(NSArray<VGItem *> *)items from:(UIViewController *)vc;
+ (void)saveItemsToFiles:(NSArray<VGItem *> *)items from:(UIViewController *)vc;
+ (void)shareItems:(NSArray<VGItem *> *)items from:(UIViewController *)vc source:(UIView *)source;
@end

NS_ASSUME_NONNULL_END
