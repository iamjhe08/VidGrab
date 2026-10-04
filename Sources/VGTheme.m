#import "VGTheme.h"

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
