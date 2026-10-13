#import "VGTheme.h"
#import "VGCustomTheme.h"
#import <CoreImage/CoreImage.h>

NSString *const VGThemeDidChangeNotification = @"VGThemeDidChangeNotification";

@interface VGPalette ()
@property (nonatomic, readwrite) UIColor *background, *surface, *surface2, *stroke, *text, *secondary, *tertiary;
@property (nonatomic, readwrite) UIColor *accent, *accent2, *accentSoft, *tabBar, *listBackground, *selectedCell, *editButton;
@property (nonatomic, readwrite) NSString *title, *detail;
@property (nonatomic, readwrite) BOOL glass, light, flat, carbon;
@property (nonatomic, readwrite) UIColor *logoColor, *onAccent, *buttonBg, *buttonFg;
@property (nonatomic, readwrite) UIColor *playerBackground, *playerSurface, *playerStroke, *playerSecondary;
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
    p.playerBackground = p.background; p.playerSurface = p.surface; p.playerStroke = p.stroke; p.playerSecondary = p.secondary;
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
        // GD: a true-black canvas with a warm gold accent.
        a = [a arrayByAddingObject:make(@"GD", @"",
                 0x000000, 0x0C0C0C, 0x161616, 0x262626, 0xA8A8A8, 0x6A6A6A, 0xF5B800, 0xFFD54A, 0xFFE08A, 0x000000, 0x050505, 0x2A2410, 0x363636)];
        // PB: pitch black with no accent color (greys only). Only the VidGrab logo is dark grey.
        VGPalette *pb = make(@"PB", @"",
                 0x000000, 0x090909, 0x131313, 0x222222, 0x9A9A9A, 0x4D4D4D, 0x808080, 0x5C5C5C, 0x9A9A9A, 0x000000, 0x000000, 0x1B1B1B, 0x2C2C2C);
        pb.logoColor = VGHex(0x6A6A6A);
        pb.flat = YES;
        a = [a arrayByAddingObject:pb];
        // CB: carbon. Charcoal greys with a cool steel tint, no accent color; the logo is brushed silver.
        VGPalette *cb = make(@"CB", @"",
                 0x131415, 0x1B1C1E, 0x25272A, 0x34363A, 0xA0A3A8, 0x5A5D62, 0x8C9096, 0x6A6E74, 0xA9ADB3, 0x0E0F10, 0x111213, 0x2A2C2F, 0x3A3D41);
        cb.logoColor = VGHex(0xB8BDC4);
        cb.flat = YES; cb.carbon = YES;
        cb.playerBackground = VGHex(0x0D0E0F); cb.playerSurface = VGHex(0x1A1B1D); cb.playerStroke = VGHex(0x303236); cb.playerSecondary = VGHex(0xA0A3A8);
        a = [a arrayByAddingObject:cb];
        // MBRG: matte black with rose gold. Soft rose buttons with dark text.
        VGPalette *mb = make(@"MBRG", @"",
                 0x0B0B0D, 0x171719, 0x222226, 0x2A2A2E, 0xA1A1AA, 0x6E6E76, 0xD9A0A7, 0xB87982, 0xE8C0C5, 0x0B0B0D, 0x0E0E10, 0x2B2124, 0x2E2E33);
        mb.onAccent = VGHex(0x0B0B0D);
        a = [a arrayByAddingObject:mb];
        // MC: monochrome crimson. Graphite greys with one crimson red.
        VGPalette *mc = make(@"MC", @"",
                 0x101214, 0x1A1D20, 0x25282C, 0x2F3338, 0x8A8E94, 0x5C6066, 0xFF1F3D, 0xD9162B, 0xFF7A8C, 0x0C0E10, 0x0F1113, 0x2A1519, 0x30343A);
        mc.onAccent = UIColor.whiteColor;
        a = [a arrayByAddingObject:mc];
        // PF: pink flow, in its deep plum dark look. Hot pink buttons with white text.
        VGPalette *pf = make(@"PF", @"",
                 0x22101C, 0x331828, 0x45223A, 0x5A2E4A, 0xD4A8C0, 0x9A6C86, 0xEC4899, 0xF472B6, 0xFBCFE8, 0x1B0C16, 0x1F0E19, 0x4A2040, 0x573052);
        pf.onAccent = UIColor.whiteColor;
        a = [a arrayByAddingObject:pf];
        // The custom theme slot (number 11, VGCustomThemeSlot). Filled in from the custom theme the person applied.
        a = [a arrayByAddingObject:[VGPalette new]];
        NSAssert(a.count == VGCustomThemeSlot + 1, @"custom theme slot moved");
        // New presets go after the custom slot so saved theme numbers never change.
        VGPalette *mid = make(@"Midnight Blue", @"",
                 0x070B1A, 0x0F1629, 0x18213B, 0x27345A, 0xA5B0CC, 0x6A759A, 0x4C8DFF, 0x7AB0FF, 0xA9C8FF, 0x060916, 0x090E1E, 0x16264A, 0x25325A);
        mid.onAccent = UIColor.whiteColor;
        VGPalette *em = make(@"Emerald", @"",
                 0x06100C, 0x0E1B15, 0x16291F, 0x24412F, 0x9FB8AB, 0x65806F, 0x10B981, 0x34D399, 0x86EFC0, 0x050D0A, 0x08130E, 0x12301F, 0x234232);
        em.onAccent = VGHex(0x04120C);
        VGPalette *sun = make(@"Sunset", @"",
                 0x140B0A, 0x201210, 0x2E1A16, 0x45261E, 0xC9A89C, 0x8F6F63, 0xFF7A45, 0xFFA94D, 0xFFC9A8, 0x0F0807, 0x120A08, 0x3A1D14, 0x4A2A20);
        sun.onAccent = VGHex(0x1A0B05);
        a = [a arrayByAddingObjectsFromArray:@[mid, em, sun]];
        // Short descriptions for the gallery. Names stay as they were.
        NSDictionary *details = @{@"Default": @"VidGrab's own look", @"SP": @"Dark grey, green accent", @"SC": @"Dark grey, orange accent",
            @"FL": @"Near-black, blue accent", @"PR": @"Purple glass, violet accent", @"GD": @"True black, gold accent",
            @"PB": @"Pitch black, greys only", @"CB": @"Carbon fiber, steel greys", @"MBRG": @"Matte black, rose gold",
            @"MC": @"Graphite, crimson", @"PF": @"Deep plum, hot pink", @"Midnight Blue": @"Deep navy, blue accent",
            @"Emerald": @"Dark green, emerald accent", @"Sunset": @"Warm dark, orange accent"};
        for (VGPalette *p in a) if (p.title.length && details[p.title]) p.detail = details[p.title];
    });
    static BOOL filled;
    if (!filled) { filled = YES; VGResetCustomThemeCache(); }   // fill the custom slot once the list exists
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

- (void)adopt:(VGPalette *)o {
    self.background = o.background; self.surface = o.surface; self.surface2 = o.surface2; self.stroke = o.stroke;
    self.text = o.text; self.secondary = o.secondary; self.tertiary = o.tertiary;
    self.accent = o.accent; self.accent2 = o.accent2; self.accentSoft = o.accentSoft; self.tabBar = o.tabBar;
    self.listBackground = o.listBackground; self.selectedCell = o.selectedCell; self.editButton = o.editButton;
    self.title = o.title; self.detail = o.detail;
    self.glass = o.glass; self.light = o.light; self.flat = o.flat; self.carbon = o.carbon;
    self.logoColor = o.logoColor; self.onAccent = o.onAccent; self.buttonBg = o.buttonBg; self.buttonFg = o.buttonFg;
    self.playerBackground = o.playerBackground; self.playerSurface = o.playerSurface; self.playerStroke = o.playerStroke; self.playerSecondary = o.playerSecondary;
}

/// One place that turns a custom theme description into the colors the app uses. The gallery, the editor preview and the app all call this.
+ (VGPalette *)paletteForSpec:(VGThemeSpec *)spec {
    VGPalette *b = self.all[(spec.base >= 0 && spec.base < (NSInteger)self.all.count && spec.base != VGCustomThemeSlot) ? spec.base : 0];
    VGPalette *p = [VGPalette new];
    [p adopt:b];
    p.title = spec.name; p.detail = @"";
    UIColor *white = UIColor.whiteColor, *black = UIColor.blackColor;
    NSString *mode = spec.bgMode;
    BOOL photo = [mode isEqual:@"photo"] && spec.hasPhoto;
    BOOL image = photo || [mode isEqual:@"gradient"] || [mode isEqual:@"texture"];
    p.carbon = image;
    // The color the pages sit on, used to work out surfaces and text.
    UIColor *effective;
    BOOL derive;
    if ([mode isEqual:@"gradient"]) { effective = VGMixColors(VGHex(spec.grad1), VGHex(spec.grad2), 0.5); derive = YES; }
    else if (photo) { effective = VGHex(0x0B0B0D); derive = YES; }
    else if ([mode isEqual:@"texture"]) {
        BOOL carbonAsBase = [spec.texture isEqual:@"carbon"];
        effective = carbonAsBase ? b.background : VGHex(spec.bgColor);
        derive = carbonAsBase ? !b.carbon : (VGHexOf(effective) != VGHexOf(b.background) || !b.carbon);
    } else { effective = VGHex(spec.bgColor); derive = VGHexOf(effective) != VGHexOf(b.background); }
    if (derive) {
        CGFloat r = 0, g = 0, bl = 0, al = 0; [effective getRed:&r green:&g blue:&bl alpha:&al];
        BOOL light = !photo && (0.299 * r + 0.587 * g + 0.114 * bl) > 0.6;
        p.background = effective; p.light = light;
        if (light) {
            p.surface = VGMixColors(effective, black, 0.04); p.surface2 = VGMixColors(effective, black, 0.09); p.stroke = VGMixColors(effective, black, 0.15);
            p.text = VGHex(0x111114); p.secondary = VGMixColors(effective, black, 0.62); p.tertiary = VGMixColors(effective, black, 0.42);
            p.tabBar = VGMixColors(effective, white, 0.5); p.listBackground = VGMixColors(effective, black, 0.02); p.editButton = VGMixColors(effective, black, 0.12);
            p.playerBackground = VGHex(0x0A0A0D); p.playerSurface = VGHex(0x15151B); p.playerStroke = VGHex(0x2A2A34); p.playerSecondary = VGHex(0xA3A3AE);
        } else {
            p.surface = VGMixColors(effective, white, 0.07); p.surface2 = VGMixColors(effective, white, 0.13); p.stroke = VGMixColors(effective, white, 0.20);
            p.text = white; p.secondary = VGMixColors(effective, white, 0.66); p.tertiary = VGMixColors(effective, white, 0.42);
            p.tabBar = VGMixColors(effective, black, 0.35); p.listBackground = VGMixColors(effective, black, 0.2); p.editButton = VGMixColors(effective, white, 0.22);
            p.playerBackground = VGMixColors(effective, black, 0.35); p.playerSurface = p.surface; p.playerStroke = p.stroke; p.playerSecondary = p.secondary;
        }
        p.selectedCell = VGMixColors(effective, p.accent, light ? 0.16 : 0.18);
    }
    // Accent: only when it differs from the preset's, so an untouched preset looks exactly like itself.
    if (spec.accent != VGHexOf(b.accent)) {
        UIColor *acc = VGHex(spec.accent);
        CGFloat r = 0, g = 0, bl = 0, al = 0; [acc getRed:&r green:&g blue:&bl alpha:&al];
        p.accent = acc; p.accent2 = VGMixColors(acc, white, 0.18); p.accentSoft = VGMixColors(acc, white, 0.45);
        p.selectedCell = VGMixColors(p.background, acc, p.light ? 0.16 : 0.18);
        p.onAccent = (0.299 * r + 0.587 * g + 0.114 * bl) > 0.6 ? VGHex(0x0A0A0D) : white;
        p.logoColor = acc; p.flat = NO; p.glass = b.glass;
    }
    // Advanced colors.
    NSDictionary<NSString *, NSNumber *> *o = spec.overrides;
    if (o[@"text"]) p.text = VGHex(o[@"text"].unsignedIntValue);
    if (o[@"secondary"]) { p.secondary = VGHex(o[@"secondary"].unsignedIntValue); p.tertiary = VGMixColors(p.secondary, p.background, 0.45); }
    if (o[@"surface"]) { p.surface = VGHex(o[@"surface"].unsignedIntValue); p.surface2 = VGMixColors(p.surface, p.light ? black : white, 0.08); }
    if (o[@"stroke"]) p.stroke = VGHex(o[@"stroke"].unsignedIntValue);
    if (o[@"buttonBg"]) p.buttonBg = VGHex(o[@"buttonBg"].unsignedIntValue);
    if (o[@"buttonFg"]) p.buttonFg = VGHex(o[@"buttonFg"].unsignedIntValue);
    if (o[@"selected"]) p.selectedCell = VGHex(o[@"selected"].unsignedIntValue);
    if (o[@"bars"]) p.tabBar = VGHex(o[@"bars"].unsignedIntValue);
    return p;
}

@end


static UIColor *sCarbonCached; static CGSize sCarbonSize; static NSString *sCarbonKey, *sCarbonPending; static NSMutableDictionary *sIconCache;

/// Rebuilds the custom slot from the applied custom theme and forgets cached pictures and icons.
void VGResetCustomThemeCache(void) {
    sCarbonCached = nil; sCarbonKey = nil; sCarbonPending = nil;
    [sIconCache removeObjectForKey:@(VGCustomThemeSlot)];
    NSArray<VGPalette *> *all = VGPalette.all;
    if (all.count <= VGCustomThemeSlot) return;
    VGThemeSpec *spec = VGThemeStore.active ?: [VGThemeSpec specFromPreset:0];
    [all[VGCustomThemeSlot] adopt:[VGPalette paletteForSpec:spec]];
}

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
        NSForegroundColorAttributeName: VGLogo,
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

void VGPrimaryButtonColors(VGPalette *p, UIColor **bg, UIColor **fg) {
    if (p.buttonBg) { *bg = p.buttonBg; *fg = p.buttonFg ?: (p.light ? UIColor.blackColor : UIColor.whiteColor); return; }
    if (p.buttonFg && p.onAccent) { *bg = p.accent; *fg = p.buttonFg; return; }
    if (p.onAccent) { *bg = p.accent; *fg = p.buttonFg ?: p.onAccent; return; }
    if (p.flat) { *bg = VGHex(0x3A3A3A); *fg = p.buttonFg ?: UIColor.whiteColor; return; }
    if (p.light) { *bg = p.text; *fg = p.buttonFg ?: UIColor.whiteColor; return; }
    *bg = UIColor.whiteColor; *fg = p.buttonFg ?: VGHex(0x0A0A0D);
}

UIButton *VGPrimaryButton(NSString *title, NSString *icon) {
    UIColor *bg = nil, *fg = nil;
    VGPrimaryButtonColors(VGPalette.current, &bg, &fg);
    if (bg) return makeButton(title, icon, bg, fg);
    if (VGPalette.current.onAccent) return makeButton(title, icon, VGAccent, VGPalette.current.onAccent);
    if (VGPalette.current.flat) return makeButton(title, icon, VGHex(0x3A3A3A), UIColor.whiteColor);   // greys-only themes: no bright white button
    return VGPalette.current.light ? makeButton(title, icon, VGText, UIColor.whiteColor) : makeButton(title, icon, UIColor.whiteColor, VGHex(0x0A0A0D));
}

UIButton *VGSecondaryButton(NSString *title, NSString *icon) {
    return makeButton(title, icon, VGSurface2, VGText);
}

UIImage *VGThemedIcon(void) {
    UIImage *base = [UIImage imageNamed:@"AppIcon60x60"] ?: [UIImage imageNamed:@"AppIcon60x60@3x"];
    if (!base || VGPalette.selectedIndex == 0) return base;
    if (!sIconCache) sIconCache = [NSMutableDictionary dictionary];
    NSMutableDictionary *cache = sIconCache;
    NSNumber *key = @(VGPalette.selectedIndex);
    if (cache[key]) return cache[key];
    CGFloat h0 = 0, h1 = 0, sat = 0, br = 0, al = 0;
    [VGHex(0xFF3D68) getHue:&h0 saturation:&sat brightness:&br alpha:&al];
    [VGLogo getHue:&h1 saturation:&sat brightness:&br alpha:&al];
    CIImage *in = [CIImage imageWithCGImage:base.CGImage];
    CIFilter *f;
    if (sat < 0.08) {
        f = [CIFilter filterWithName:@"CIColorControls"];
        [f setValue:in forKey:kCIInputImageKey];
        [f setValue:@0.0 forKey:kCIInputSaturationKey];
    } else {
        f = [CIFilter filterWithName:@"CIHueAdjust"];
        [f setValue:in forKey:kCIInputImageKey];
        [f setValue:@((h1 - h0) * 2 * M_PI) forKey:kCIInputAngleKey];
    }
    CIImage *out = f.outputImage;
    CGImageRef cg = out ? [[CIContext contextWithOptions:nil] createCGImage:out fromRect:in.extent] : NULL;
    if (!cg) return base;
    UIImage *img = [UIImage imageWithCGImage:cg scale:base.scale orientation:base.imageOrientation];
    CGImageRelease(cg);
    cache[key] = img;
    return img;
}

UIColor *VGCarbonColor(void) {
    CGSize s = UIScreen.mainScreen.bounds.size;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) { CGFloat m = MAX(s.width, s.height); s = CGSizeMake(m, m); }
    VGPalette *cur = VGPalette.current;
    if (VGPalette.selectedIndex == VGCustomThemeSlot) {
        VGThemeSpec *spec = VGThemeStore.active;
        if (!spec) return cur.background;
        NSString *key = [spec.cacheKey stringByAppendingFormat:@"|%.0fx%.0f", s.width, s.height];
        if (sCarbonCached && [sCarbonKey isEqual:key]) return sCarbonCached;
        CGFloat scale = UIScreen.mainScreen.scale;
        if ([spec.bgMode isEqual:@"photo"]) {
            // Photos are decoded and blurred off the main thread; the pages show the plain color until the picture is ready.
            if (![sCarbonPending isEqual:key]) {
                sCarbonPending = key;
                VGRenderThemeBackgroundAsync(spec, s, scale, nil, ^(UIImage *img) {
                    if (![sCarbonPending isEqual:key] || !img) return;
                    sCarbonCached = [UIColor colorWithPatternImage:img]; sCarbonKey = key; sCarbonSize = s;
                    [NSNotificationCenter.defaultCenter postNotificationName:VGThemeDidChangeNotification object:nil];
                });
            }
            return cur.background;
        }
        UIImage *img = VGRenderThemeBackground(spec, s, scale, nil);
        if (!img) return cur.background;
        sCarbonCached = [UIColor colorWithPatternImage:img]; sCarbonKey = key; sCarbonSize = s;
        return sCarbonCached;
    }
    NSString *key = [NSString stringWithFormat:@"carbon|%.0fx%.0f", s.width, s.height];
    if (sCarbonCached && [sCarbonKey isEqual:key]) return sCarbonCached;
    UIImage *img = [UIImage imageWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"carbon" ofType:@"jpg"]];
    if (!img) return cur.background;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:s];
    UIImage *fit = [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        CGFloat k = MAX(s.width / img.size.width, s.height / img.size.height);
        CGSize d = CGSizeMake(img.size.width * k, img.size.height * k);
        [img drawInRect:CGRectMake((s.width - d.width) / 2, 0, d.width, d.height)];
    }];
    sCarbonCached = [UIColor colorWithPatternImage:fit]; sCarbonKey = key; sCarbonSize = s;
    return sCarbonCached;
}

NSString *VGAccentCSS(void) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [VGAccent getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"rgba(%d,%d,%d,0.96)", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255)];
}
