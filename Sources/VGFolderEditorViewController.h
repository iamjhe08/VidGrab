#import <UIKit/UIKit.h>
#import "VGEngine.h"

NS_ASSUME_NONNULL_BEGIN

/// The sheet for making a folder or editing one: a name and a color.
@interface VGFolderEditorViewController : UIViewController
/// Pass nil to make a new folder.
- (instancetype)initWithFolder:(nullable VGFolder *)folder;
@property (nonatomic, copy, nullable) void (^onSave)(NSString *name, NSString *colorHex);
/// Wraps the editor in a navigation controller set up as a half-height sheet.
+ (UINavigationController *)sheetWithFolder:(nullable VGFolder *)folder onSave:(void (^)(NSString *name, NSString *colorHex))onSave;
@end

NS_ASSUME_NONNULL_END
