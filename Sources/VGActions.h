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

/// Several downloads at once (Downloads > Select).
+ (void)saveItemsToPhotos:(NSArray<VGItem *> *)items from:(UIViewController *)vc;
+ (void)saveItemsToFiles:(NSArray<VGItem *> *)items from:(UIViewController *)vc;
+ (void)shareItems:(NSArray<VGItem *> *)items from:(UIViewController *)vc source:(UIView *)source;
@end

NS_ASSUME_NONNULL_END
