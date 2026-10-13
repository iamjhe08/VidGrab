#import <UIKit/UIKit.h>
@class VGThemeSpec;

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
/// No colored glow behind the Home header or the player (for the greys-only themes).
@property (nonatomic, readonly) BOOL flat;
/// Uses a wallpaper picture behind the main pages (Carbon).
@property (nonatomic, readonly) BOOL carbon;
/// A light theme (white background, dark text).
@property (nonatomic, readonly) BOOL light;
/// The video player always stays dark; these are its glass, edge and background colors.
/// The color of the VidGrab logo (the accent unless the theme says otherwise).
@property (nonatomic, readonly) UIColor *logoColor;
/// When set, primary buttons use the accent color with this text color (instead of white or grey).
@property (nonatomic, readonly) UIColor *onAccent;
@property (nonatomic, readonly) UIColor *buttonBg, *buttonFg;
@property (nonatomic, readonly) UIColor *playerBackground, *playerSurface, *playerStroke, *playerSecondary;
+ (VGPalette *)current;
+ (NSArray<VGPalette *> *)all;
/// Index of the saved theme (0 = Default).
+ (NSInteger)selectedIndex;
+ (void)selectIndex:(NSInteger)index;
@end
@interface VGPalette (Custom)
/// Turns a saved custom theme into a palette. Used by the app, the gallery and the editor preview alike.
+ (VGPalette *)paletteForSpec:(VGThemeSpec *)spec;
@end
extern NSString *const VGThemeDidChangeNotification;

#define VGBackground  ([VGPalette current].background)
#define VGScreen      ([VGPalette current].carbon ? VGCarbonColor() : [VGPalette current].background)
#define VGSurface     ([VGPalette current].surface)
#define VGSurface2    ([VGPalette current].surface2)
#define VGStroke      ([VGPalette current].stroke)
#define VGText        ([VGPalette current].text)
#define VGSecondary   ([VGPalette current].secondary)
#define VGTertiary    ([VGPalette current].tertiary)
#define VGAccent      ([VGPalette current].accent)
#define VGAccent2     ([VGPalette current].accent2)
#define VGAccentSoft  ([VGPalette current].accentSoft)
/// The color of something switched on (shuffle, repeat, selected...). The greys-only themes use bright white so "on" is easy to tell from "off".
#define VGOn          ([VGPalette current].flat ? VGHex(0xF2F2F2) : [VGPalette current].accent)
/// The "off" color on the dark player (white normally, dim grey on the greys-only themes so the "on" white stands out).
#define VGOffOnPlayer ([VGPalette current].flat ? VGHex(0x6A6A6A) : UIColor.whiteColor)
/// Text or icons drawn on top of the accent color.
#define VGOnAccent    ([VGPalette current].onAccent ?: UIColor.whiteColor)
#define VGTabBarBg    ([VGPalette current].tabBar)
#define VGListBg      ([VGPalette current].listBackground)
#define VGSelectedBg  ([VGPalette current].selectedCell)
#define VGLight       ([VGPalette current].light)
#define VGLogo        ([VGPalette current].logoColor ?: [VGPalette current].accent)
#define VGPlayerBG        ([VGPalette current].playerBackground)
#define VGPlayerSurface   ([VGPalette current].playerSurface)
#define VGPlayerStroke    ([VGPalette current].playerStroke)
#define VGPlayerSecondary ([VGPalette current].playerSecondary)
#define VGInterfaceStyle  (VGPalette.current.light ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark)
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
/// The carbon wallpaper as a color that fills a whole screen.
UIColor *VGCarbonColor(void);
/// The accent as a CSS color for web pages, e.g. "rgba(255,61,104,0.96)".
NSString *VGAccentCSS(void);

/// Rebuilds the custom slot from the applied custom theme and clears cached pictures and icons.
void VGResetCustomThemeCache(void);
/// The colors a primary button uses in a palette (shared by real buttons and previews).
void VGPrimaryButtonColors(VGPalette *palette, UIColor **background, UIColor **foreground);
