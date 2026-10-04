#import <UIKit/UIKit.h>

// VidGrab's own palette: near-black canvas, coral-pink accent (matches the app icon).
static inline UIColor *VGHex(unsigned int h) {
    return [UIColor colorWithRed:((h >> 16) & 0xFF) / 255.0 green:((h >> 8) & 0xFF) / 255.0 blue:(h & 0xFF) / 255.0 alpha:1];
}
#define VGBackground  VGHex(0x0A0A0D)
#define VGSurface     VGHex(0x15151B)
#define VGSurface2    VGHex(0x1F1F27)
#define VGStroke      VGHex(0x2A2A34)
#define VGText        UIColor.whiteColor
#define VGSecondary   VGHex(0xA3A3AE)
#define VGTertiary    VGHex(0x6C6C78)
#define VGAccent      VGHex(0xFF3D68)
#define VGAccent2     VGHex(0xD9338F)

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
