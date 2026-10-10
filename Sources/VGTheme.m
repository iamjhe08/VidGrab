#import "VGTheme.h"
#import <CoreImage/CoreImage.h>

NSString *const VGThemeDidChangeNotification = @"VGThemeDidChangeNotification";

@interface VGPalette ()
@property (nonatomic, readwrite) UIColor *background, *surface, *surface2, *stroke, *text, *secondary, *tertiary;
@property (nonatomic, readwrite) UIColor *accent, *accent2, *accentSoft, *tabBar, *listBackground, *selectedCell, *editButton;
@property (nonatomic, readwrite) NSString *title, *detail;
@property (nonatomic, readwrite) BOOL glass;
@end

@implementation VGPalette

static VGPalette *make(NSString *title, NSString *detail, unsigned bg, unsigned surface, unsigned surface2, unsigned stroke,
                       unsigned secondary, unsigned tertiary, unsigned accent, unsigned accent2, unsigned soft,
                       unsigned tab, unsigned list, unsigned selected, unsigned edit) {
    VGPalette *p = [VGPalette new];
    p.title = title; p.detail = detail;
    p.background = VGHex(bg); p.surface = VGHex(surface); p.surface2 = VGHex(surface2); p.stroke = VGHex(stroke);
    p.text = UIColor.whiteColor; p.secondary = VGHex(secondary); p.tertiary = VGHex(tertiary);
    p.accent = VGHex(accent); p.accent2 = VGHex(accent2); p.accentSoft = VGHex(soft);
    p.tabBar = VGHex(tab); p.listBackground = VGHex(list); p.selectedCell = VGHex(selected); p.editButton = VGHex(edit);
    return p;
}

+ (NSArray<VGPalette *> *)all {
    static NSArray *a;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        a = @[
            make(@"Default", @"VidGrab's own look",
                 0x0A0A0D, 0x15151B, 0x1F1F27, 0x2A2A34, 0xA3A3AE, 0x6C6C78, 0xFF3D68, 0xD9338F, 0xFF8FA6, 0x0D0D11, 0x0F0F14, 0x26232C, 0x3A3A46),
            make(@"SP", @"",
                 0x121212, 0x181818, 0x282828, 0x333333, 0xB3B3B3, 0x727272, 0x1DB954, 0x1ED760, 0x5EE08A, 0x0A0A0A, 0x101010, 0x2A2A2A, 0x3E3E3E),
            make(@"SC", @"",
                 0x111111, 0x1A1A1A, 0x262626, 0x333333, 0xA6A6A6, 0x6B6B6B, 0xFF5500, 0xFF7700, 0xFF9B66, 0x0C0C0C, 0x141414, 0x2A2522, 0x3A3A3A),
            make(@"FL", @"",
                 0x08090B, 0x131518, 0x1C1F24, 0x2A2E35, 0x9BA1AB, 0x666C76, 0x3E8BFF, 0x2DD4E0, 0x8DBBFF, 0x0C0D10, 0x0F1114, 0x1B2330, 0x2C3139),
            make(@"PR", @"",
                 0x07060E, 0x100E1C, 0x1A1730, 0x2F2A55, 0xA9A4C4, 0x6F6A8E, 0x8A6CFF, 0x22D3EE, 0xBFAEFF, 0x0A0914, 0x0C0A18, 0x231E40, 0x302A52),
        ];
        ((VGPalette *)a[4]).glass = YES;
    });
    return a;
}

+ (NSInteger)selectedIndex {
    NSInteger i = [NSUserDefaults.standardUserDefaults integerForKey:@"vgTheme"];
    return (i >= 0 && i < (NSInteger)self.all.count) ? i : 0;
}

+ (void)selectIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.all.count) index = 0;
    [NSUserDefaults.standardUserDefaults setInteger:index forKey:@"vgTheme"];
}

+ (VGPalette *)current { return self.all[self.selectedIndex]; }

@end

@implementation VGGradientView
+ (Class)layerClass { return CAGradientLayer.class; }
- (CAGradientLayer *)gradient { return (CAGradientLayer *)self.layer; }
@end

@interface VGProgressBar ()
@property (nonatomic, strong) VGGradientView *fill;
@end

@implementation VGProgressBar

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = VGSurface2;
        self.clipsToBounds = YES;
        _fill = [VGGradientView new];
        _fill.gradient.colors = @[(id)VGAccent.CGColor, (id)VGAccent2.CGColor];
        _fill.gradient.startPoint = CGPointMake(0, 0.5);
        _fill.gradient.endPoint = CGPointMake(1, 0.5);
        [self addSubview:_fill];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2;
    self.fill.layer.cornerRadius = self.bounds.size.height / 2;
    self.fill.frame = CGRectMake(0, 0, self.bounds.size.width * MAX(0, MIN(1, self.progress)), self.bounds.size.height);
}

- (void)setProgress:(double)progress { [self setProgress:progress animated:NO]; }

- (void)setProgress:(double)progress animated:(BOOL)animated {
    _progress = progress;
    if (animated) {
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{ [self layoutSubviews]; } completion:nil];
    } else {
        [self setNeedsLayout];
    }
}

@end

UILabel *VGWordmark(CGFloat size) {
    UILabel *l = [UILabel new];
    UIFont *f = VGFont(size, UIFontWeightBlack);
    UIFontDescriptor *d = [f.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitCondensed];
    if (d) f = [UIFont fontWithDescriptor:d size:size];
    l.attributedText = [[NSAttributedString alloc] initWithString:@"VIDGRAB" attributes:@{
        NSFontAttributeName: f,
        NSForegroundColorAttributeName: VGAccent,
        NSKernAttributeName: @(1.5),
    }];
    return l;
}

static UIButton *makeButton(NSString *title, NSString *icon, UIColor *bg, UIColor *fg) {
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration];
    c.baseBackgroundColor = bg;
    c.baseForegroundColor = fg;
    c.cornerStyle = UIButtonConfigurationCornerStyleFixed;
    c.background.cornerRadius = 10;
    c.contentInsets = NSDirectionalEdgeInsetsMake(14, 16, 14, 16);
    c.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: VGFont(16, UIFontWeightBold)}];
    if (icon) {
        c.image = [UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold]];
        c.imagePadding = 8;
    }
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    b.configurationUpdateHandler = ^(UIButton *button) {
        button.alpha = button.isHighlighted ? 0.75 : (button.isEnabled ? 1 : 0.4);
    };
    return b;
}

UIButton *VGPrimaryButton(NSString *title, NSString *icon) {
    return makeButton(title, icon, UIColor.whiteColor, VGHex(0x0A0A0D));
}

UIButton *VGSecondaryButton(NSString *title, NSString *icon) {
    return makeButton(title, icon, VGSurface2, UIColor.whiteColor);
}

UIImage *VGThemedIcon(void) {
    UIImage *base = [UIImage imageNamed:@"AppIcon60x60"] ?: [UIImage imageNamed:@"AppIcon60x60@3x"];
    if (!base || VGPalette.selectedIndex == 0) return base;
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSNumber *key = @(VGPalette.selectedIndex);
    if (cache[key]) return cache[key];
    CGFloat h0 = 0, h1 = 0, sat = 0, br = 0, al = 0;
    [VGHex(0xFF3D68) getHue:&h0 saturation:&sat brightness:&br alpha:&al];
    [VGAccent getHue:&h1 saturation:&sat brightness:&br alpha:&al];
    CIImage *in = [CIImage imageWithCGImage:base.CGImage];
    CIFilter *f = [CIFilter filterWithName:@"CIHueAdjust"];
    [f setValue:in forKey:kCIInputImageKey];
    [f setValue:@((h1 - h0) * 2 * M_PI) forKey:kCIInputAngleKey];
    CIImage *out = f.outputImage;
    CGImageRef cg = out ? [[CIContext contextWithOptions:nil] createCGImage:out fromRect:in.extent] : NULL;
    if (!cg) return base;
    UIImage *img = [UIImage imageWithCGImage:cg scale:base.scale orientation:base.imageOrientation];
    CGImageRelease(cg);
    cache[key] = img;
    return img;
}

NSString *VGAccentCSS(void) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [VGAccent getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"rgba(%d,%d,%d,0.96)", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255)];
}
