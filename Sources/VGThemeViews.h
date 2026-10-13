#import <UIKit/UIKit.h>
#import "VGTheme.h"

/// A small picture of a theme. The gallery and the editor both draw it from a palette, so what you see is what the app uses.
@interface VGThemePreviewView : UIView
/// Compact: a thumbnail for lists. Otherwise the larger sample used while editing.
@property (nonatomic, assign) BOOL compact;
/// `background` is the picture behind the pages (gradient, photo or texture) when the theme has one.
- (void)showPalette:(VGPalette *)palette background:(UIImage *)background;
@end

/// One row of the editor with a name, the color's HEX value, a swatch you tap to change it, and an optional reset arrow.
@interface VGColorRow : UIControl
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) unsigned value;
@property (nonatomic, assign) BOOL showsReset;       // the reset arrow appears only while the value was changed
@property (nonatomic, copy) void (^onReset)(void);
@end
