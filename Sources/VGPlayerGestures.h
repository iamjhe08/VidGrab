#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// What the swipe gestures need from the player screen.
@protocol VGPlayerGestureHost <NSObject>
@property (nonatomic, readonly, nullable) AVPlayer *gesturePlayer;
/// Sideways swipes preview the video live: pause, follow the finger frame by frame, then carry on.
- (void)gestureScrubBegan;
- (void)gestureScrubToSeconds:(double)seconds;
- (void)gestureScrubEnded;
@end

/// Swipe controls for VidGrab's player: brightness (left side), volume (right side) and seeking (sideways).
/// Every part can be switched off in Settings > Player gestures.
@interface VGPlayerGestures : NSObject

/// Brightness and volume swipes (up and down) on or off together.
@property (class, nonatomic) BOOL levelsEnabled;
@property (class, nonatomic) BOOL seekEnabled;
/// Brightness on the right and volume on the left (the default is the other way round).
@property (class, nonatomic) BOOL brightnessOnRight;

/// How far one swipe across the whole screen seeks: 1, 2, 5 or 10 minutes.
+ (NSArray<NSNumber *> *)seekChoices;                 // seconds
+ (NSInteger)seekChoiceIndex;
+ (void)setSeekChoiceIndex:(NSInteger)index;
+ (NSString *)seekChoiceName:(NSInteger)index;        // "2 minutes"
+ (NSString *)seekShortName;                          // "2 min" (current choice)

- (instancetype)initWithHost:(UIViewController<VGPlayerGestureHost> *)host;
- (void)attach;
- (void)detach;
/// Puts the screen brightness back to what it was before the first brightness swipe.
- (void)restoreBrightness;

@end

NS_ASSUME_NONNULL_END
