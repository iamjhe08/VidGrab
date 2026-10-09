#import <UIKit/UIKit.h>
#import "VGEngine.h"

NS_ASSUME_NONNULL_BEGIN

/// Edit an audio file's title, artist, album and cover picture.
@interface VGAudioEditorViewController : UIViewController
- (instancetype)initWithItem:(VGItem *)item;
@end

@class VGCoverResult;
/// A grid of cover pictures found online; picking one hands back the big picture.
@interface VGCoverPickerViewController : UIViewController
- (instancetype)initWithResults:(NSArray<VGCoverResult *> *)results;
@property (nonatomic, copy, nullable) void (^onPick)(UIImage *image, VGCoverResult *result);
@end

NS_ASSUME_NONNULL_END
