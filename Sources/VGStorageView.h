#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A small card like the iPhone Storage screen in Settings: how much of the phone is free, a bar split into VidGrab,
/// everything else and free space, and the VidGrab share in numbers.
@interface VGStorageView : UIView
/// Reads the phone's storage again. `vidGrabBytes` is what VidGrab's own videos take (vault included).
- (void)refreshWithVidGrabBytes:(long long)vidGrabBytes;
/// Every storage figure the phone reports, one per line, shown when the card is tapped.
@property (nonatomic, copy, readonly) NSString *detailsText;
/// Called when the card is tapped.
@property (nonatomic, copy, nullable) void (^onTap)(void);
@end

NS_ASSUME_NONNULL_END
