#import "VGThemeViews.h"
#import "VGCustomTheme.h"
#import "VGLocalize.h"

@interface VGThemePreviewView ()
@property (nonatomic, strong) UIImageView *bgImage;
@property (nonatomic, strong) UILabel *title, *line, *toggleLabel, *chipLabel;
@property (nonatomic, strong) UIView *card, *separator, *primary, *secondary, *chip, *miniBar, *miniPill;
@property (nonatomic, strong) UILabel *primaryLabel, *secondaryLabel;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UISlider *slider;
@end

@implementation VGThemePreviewView

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.clipsToBounds = YES; self.userInteractionEnabled = NO; self.isAccessibilityElement = NO;
        _bgImage = [UIImageView new]; _bgImage.contentMode = UIViewContentModeScaleAspectFill; _bgImage.clipsToBounds = YES;
        _title = [UILabel new]; _title.text = @"VidGrab"; _title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
        _line = [UILabel new]; _line.text = VGT(@"This is how your theme looks"); _line.font = [UIFont systemFontOfSize:13];
        _card = [UIView new]; _card.layer.cornerRadius = 12; _card.layer.borderWidth = 1;
        _toggleLabel = [UILabel new]; _toggleLabel.text = VGT(@"Toggle"); _toggleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _toggle = [UISwitch new]; _toggle.on = YES; _toggle.transform = CGAffineTransformMakeScale(0.75, 0.75);
        _slider = [UISlider new]; _slider.value = 0.6;
        _separator = [UIView new];
        _primary = [UIView new]; _primary.layer.cornerRadius = 10; _primaryLabel = [UILabel new]; _primaryLabel.text = VGT(@"Download"); _primaryLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold]; _primaryLabel.textAlignment = NSTextAlignmentCenter;
        _secondary = [UIView new]; _secondary.layer.cornerRadius = 10; _secondaryLabel = [UILabel new]; _secondaryLabel.text = VGT(@"Cancel"); _secondaryLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]; _secondaryLabel.textAlignment = NSTextAlignmentCenter;
        _chip = [UIView new]; _chip.layer.cornerRadius = 10; _chipLabel = [UILabel new]; _chipLabel.text = VGT(@"Selected"); _chipLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]; _chipLabel.textAlignment = NSTextAlignmentCenter;
        _miniBar = [UIView new]; _miniBar.layer.cornerRadius = 2; _miniPill = [UIView new];
        for (UIView *v in @[_bgImage, _title, _line, _card, _miniBar, _miniPill]) [self addSubview:v];
        for (UIView *v in @[_toggleLabel, _toggle, _slider, _separator, _primary, _secondary, _chip]) [_card addSubview:v];
        [_primary addSubview:_primaryLabel]; [_secondary addSubview:_secondaryLabel]; [_chip addSubview:_chipLabel];
    }
    return self;
}

- (void)setCompact:(BOOL)c {
    _compact = c;
    self.layer.cornerRadius = c ? 8 : 16;
    for (UIView *v in @[_title, _line]) v.hidden = c;
    for (UIView *v in @[_toggleLabel, _toggle, _slider, _separator, _primary, _secondary, _chip]) v.hidden = c;
    _miniBar.hidden = !c; _miniPill.hidden = !c;
    [self setNeedsLayout];
}

- (void)showPalette:(VGPalette *)p background:(UIImage *)bg {
    BOOL hasImage = bg != nil;
    self.backgroundColor = p.background;
    self.bgImage.image = bg; self.bgImage.hidden = !hasImage;
    self.overrideUserInterfaceStyle = p.light ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    self.title.textColor = hasImage && !p.light ? UIColor.whiteColor : p.text;
    self.line.textColor = hasImage && !p.light ? [UIColor colorWithWhite:1 alpha:0.75] : p.secondary;
    self.card.backgroundColor = p.surface; self.card.layer.borderColor = p.stroke.CGColor;
    self.toggleLabel.textColor = p.text;
    self.toggle.onTintColor = p.accent;
    self.slider.minimumTrackTintColor = p.accent; self.slider.maximumTrackTintColor = p.surface2; self.slider.thumbTintColor = p.light ? UIColor.whiteColor : p.text;
    self.separator.backgroundColor = p.stroke;
    UIColor *pbg = nil, *pfg = nil; VGPrimaryButtonColors(p, &pbg, &pfg);
    self.primary.backgroundColor = pbg ?: p.accent; self.primaryLabel.textColor = pfg ?: UIColor.whiteColor;
    self.secondary.backgroundColor = p.surface2; self.secondaryLabel.textColor = p.text;
    self.chip.backgroundColor = p.selectedCell; self.chipLabel.textColor = p.accent;
    self.miniBar.backgroundColor = p.text; self.miniPill.backgroundColor = pbg ?: p.accent;
    self.card.layer.borderColor = p.stroke.CGColor;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    self.bgImage.frame = self.bounds;
    if (self.compact) {
        self.miniBar.frame = CGRectMake(8, 8, W * 0.42, 4);
        self.card.frame = CGRectMake(6, H * 0.42, W - 12, H * 0.5 - 2); self.card.layer.cornerRadius = 6;
        self.miniPill.frame = CGRectMake(W - 6 - 22, H * 0.42 + (H * 0.5 - 2 - 8) / 2, 18, 8); self.miniPill.layer.cornerRadius = 4;
        return;
    }
    self.title.frame = CGRectMake(16, 14, W - 32, 28);
    self.line.frame = CGRectMake(16, 42, W - 32, 18);
    CGFloat top = 68;
    self.card.frame = CGRectMake(12, top, W - 24, H - top - 12);
    CGFloat cw = self.card.bounds.size.width, ch = self.card.bounds.size.height;
    self.toggleLabel.frame = CGRectMake(12, 8, 80, 26);
    CGSize ts = self.toggle.bounds.size; CGFloat k = 0.75;
    self.toggle.frame = CGRectMake(cw - 12 - ts.width * k, 8 + (26 - ts.height * k) / 2, ts.width * k, ts.height * k);
    self.slider.frame = CGRectMake(104, 8, MAX(40, cw - 104 - 12 - ts.width * k - 12), 26);
    self.separator.frame = CGRectMake(12, 42, cw - 24, 1);
    CGFloat by = 52, bh = MAX(30, ch - by - 10), bw = (cw - 24 - 16) / 3;
    self.primary.frame = CGRectMake(12, by, bw, bh); self.primaryLabel.frame = self.primary.bounds;
    self.secondary.frame = CGRectMake(12 + bw + 8, by, bw, bh); self.secondaryLabel.frame = self.secondary.bounds;
    self.chip.frame = CGRectMake(12 + (bw + 8) * 2, by, bw, bh); self.chipLabel.frame = self.chip.bounds;
}

@end

#pragma mark Color row

@interface VGColorRow ()
@property (nonatomic, strong) UILabel *titleLabel, *hexLabel;
@property (nonatomic, strong) UIView *swatch;
@property (nonatomic, strong) UIButton *resetB;
@end

@implementation VGColorRow

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = VGHex(0x15151B); self.layer.cornerRadius = 12;
        _titleLabel = [UILabel new]; _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]; _titleLabel.textColor = UIColor.whiteColor;
        _hexLabel = [UILabel new]; _hexLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular]; _hexLabel.textColor = VGHex(0xA3A3AE);
        _swatch = [UIView new]; _swatch.layer.cornerRadius = 8; _swatch.layer.borderWidth = 1; _swatch.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor; _swatch.userInteractionEnabled = NO;
        _resetB = [UIButton buttonWithType:UIButtonTypeSystem];
        [_resetB setImage:[UIImage systemImageNamed:@"arrow.counterclockwise"] forState:UIControlStateNormal];
        _resetB.tintColor = VGHex(0xA3A3AE); _resetB.hidden = YES; _resetB.accessibilityLabel = VGT(@"Reset");
        [_resetB addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
        for (UIView *v in @[_titleLabel, _hexLabel, _swatch, _resetB]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:v]; }
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:48],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14], [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_swatch.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14], [_swatch.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_swatch.widthAnchor constraintEqualToConstant:30], [_swatch.heightAnchor constraintEqualToConstant:30],
            [_hexLabel.trailingAnchor constraintEqualToAnchor:_swatch.leadingAnchor constant:-10], [_hexLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_resetB.trailingAnchor constraintEqualToAnchor:_hexLabel.leadingAnchor constant:-8], [_resetB.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_resetB.widthAnchor constraintEqualToConstant:32], [_resetB.heightAnchor constraintEqualToConstant:32],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_resetB.leadingAnchor constant:-6],
        ]];
        self.isAccessibilityElement = YES; self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}
- (void)setTitle:(NSString *)t { _title = [t copy]; self.titleLabel.text = VGT(t); self.accessibilityLabel = VGT(t); }
- (void)setValue:(unsigned)v { _value = v; self.swatch.backgroundColor = VGHex(v); self.hexLabel.text = VGHexString(v); self.accessibilityValue = VGHexString(v); }
- (void)setShowsReset:(BOOL)s { _showsReset = s; self.resetB.hidden = !s; }
- (void)resetTapped { if (self.onReset) self.onReset(); }

@end
