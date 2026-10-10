#import <UIKit/UIKit.h>

// VidGrab's own palette: near-black canvas, coral-pink accent (matches the app icon).
static inline UIColor *VGHex(unsigned int h) {
    return [UIColor colorWithRed:((h >> 16) & 0xFF) / 255.0 green:((h >> 8) & 0xFF) / 255.0 blue:(h & 0xFF) / 255.0 alpha:1];
}
/// The colors of the chosen theme. Default is VidGrab's own look; the others take their feel from well-known apps.
@interface VGPalette : NSObject
@property (nonatomic, readonly) UIColor *background, *surface, *surface2, *stroke, *text, *secondary, *tertiary;
@property (nonatomic, readonly) UIColor *accent, *accent2, *accentSoft, *tabBar, *listBackground, *selectedCell, *editButton;
@property (nonatomic, readonly) NSString *title, *detail;
/// Futuristic glass look: see-through bars with a blur.
@property (nonatomic, readonly) BOOL glass;
+ (VGPalette *)current;
+ (NSArray<VGPalette *> *)all;
/// Index of the saved theme (0 = Default).
+ (NSInteger)selectedIndex;
+ (void)selectIndex:(NSInteger)index;
@end
extern NSString *const VGThemeDidChangeNotification;

#define VGBackground  ([VGPalette current].background)
#define VGSurface     ([VGPalette current].surface)
#define VGSurface2    ([VGPalette current].surface2)
#define VGStroke      ([VGPalette current].stroke)
#define VGText        ([VGPalette current].text)
#define VGSecondary   ([VGPalette current].secondary)
#define VGTertiary    ([VGPalette current].tertiary)
#define VGAccent      ([VGPalette current].accent)
#define VGAccent2     ([VGPalette current].accent2)
#define VGAccentSoft  ([VGPalette current].accentSoft)
#define VGTabBarBg    ([VGPalette current].tabBar)
#define VGListBg      ([VGPalette current].listBackground)
#define VGSelectedBg  ([VGPalette current].selectedCell)
#define VGEditBg      ([VGPalette current].editButton)

static inline UIFont *VGFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

static inline UIFont *VGRounded(CGFloat size, UIFontWeight weight) {
    UIFont *f = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *d = [f.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    return d ? [UIFont fontWithDescriptor:d size:size] : f;
}

static inline NSString *VGDuration(double seconds) {
    int t = (int)seconds;
    if (t <= 0) return nil;
    if (t >= 3600) return [NSString stringWithFormat:@"%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60];
    return [NSString stringWithFormat:@"%d:%02d", t / 60, t % 60];
}

/// A view whose backing layer is a gradient.
@interface VGGradientView : UIView
@property (nonatomic, readonly) CAGradientLayer *gradient;
@end

/// Rounded progress track with an accent gradient fill.
@interface VGProgressBar : UIView
@property (nonatomic) double progress;
- (void)setProgress:(double)progress animated:(BOOL)animated;
@end

/// The "VIDGRAB" wordmark.
UILabel *VGWordmark(CGFloat size);

/// Primary (white, dark text) and secondary (dark, white text) buttons.
UIButton *VGPrimaryButton(NSString *title, NSString *icon);
UIButton *VGSecondaryButton(NSString *title, NSString *icon);

/// VidGrab's app icon with its colors turned to match the chosen theme (the original for Default).
UIImage *VGThemedIcon(void);
/// The accent as a CSS color for web pages, e.g. "rgba(255,61,104,0.96)".
NSString *VGAccentCSS(void);
