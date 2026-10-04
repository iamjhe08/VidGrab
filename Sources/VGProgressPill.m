#import "VGProgressPill.h"
#import "VGEngine.h"
#import "VGTheme.h"

@interface VGProgressPill ()
@property (nonatomic, strong) CAShapeLayer *track, *arc;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *percent, *badge;
@property (nonatomic) BOOL showing;
@end

@implementation VGProgressPill

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [VGSurface2 colorWithAlphaComponent:0.97];
        self.layer.cornerRadius = 24;
        self.layer.borderColor = VGStroke.CGColor;
        self.layer.borderWidth = 1;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 12;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.accessibilityLabel = @"Downloads in progress";
        self.accessibilityTraits = UIAccessibilityTraitButton;

        UIView *ring = [UIView new];
        ring.userInteractionEnabled = NO;
        ring.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:ring];
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(15, 15) radius:13 startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
        _track = [CAShapeLayer layer];
        _track.path = path.CGPath;
        _track.fillColor = UIColor.clearColor.CGColor;
        _track.strokeColor = VGStroke.CGColor;
        _track.lineWidth = 3;
        _arc = [CAShapeLayer layer];
        _arc.path = path.CGPath;
        _arc.fillColor = UIColor.clearColor.CGColor;
        _arc.strokeColor = VGAccent.CGColor;
        _arc.lineWidth = 3;
        _arc.lineCap = kCALineCapRound;
        _arc.strokeEnd = 0;
        [ring.layer addSublayer:_track];
        [ring.layer addSublayer:_arc];

        _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down"
                                                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightHeavy]]];
        _icon.tintColor = VGText;
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        [ring addSubview:_icon];

        _percent = [UILabel new];
        _percent.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightHeavy];
        _percent.textColor = VGText;
        _percent.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_percent];

        _badge = [UILabel new];
        _badge.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightHeavy];
        _badge.textColor = UIColor.whiteColor;
        _badge.backgroundColor = VGAccent;
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.layer.cornerRadius = 10;
        _badge.clipsToBounds = YES;
        _badge.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_badge];

        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:48],
            [ring.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:9],
            [ring.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [ring.widthAnchor constraintEqualToConstant:30],
            [ring.heightAnchor constraintEqualToConstant:30],
            [_icon.centerXAnchor constraintEqualToAnchor:ring.centerXAnchor],
            [_icon.centerYAnchor constraintEqualToAnchor:ring.centerYAnchor],
            [_percent.leadingAnchor constraintEqualToAnchor:ring.trailingAnchor constant:8],
            [_percent.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [_percent.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_badge.centerXAnchor constraintEqualToAnchor:ring.trailingAnchor constant:-1],
            [_badge.centerYAnchor constraintEqualToAnchor:ring.topAnchor constant:1],
            [_badge.heightAnchor constraintEqualToConstant:20],
            [_badge.widthAnchor constraintGreaterThanOrEqualToConstant:20],
        ]];
        self.hidden = YES;
        self.alpha = 0;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:VGTasksDidChangeNotification object:nil];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.transform = highlighted ? CGAffineTransformMakeScale(0.95, 0.95) : CGAffineTransformIdentity;
}

- (void)setSuppressed:(BOOL)suppressed {
    _suppressed = suppressed;
    [self refresh];
}

- (void)refresh {
    VGEngine *e = [VGEngine shared];
    NSUInteger n = e.activeCount;
    VGTask *lead = e.leadTask;
    BOOL show = n > 0 && !self.suppressed;
    if (lead) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.25];
        self.arc.strokeEnd = MAX(0.02, lead.fraction);
        [CATransaction commit];
        self.percent.text = lead.state == VGTaskQueued ? @"Waiting" : [NSString stringWithFormat:@"%d%%", (int)round(lead.fraction * 100)];
    }
    self.badge.text = [NSString stringWithFormat:@"%lu", (unsigned long)n];
    self.badge.hidden = n < 2;
    self.accessibilityValue = [NSString stringWithFormat:@"%@, %lu %@", self.percent.text, (unsigned long)n, n == 1 ? @"download" : @"downloads"];

    if (show == self.showing) return;
    self.showing = show;
    if (show) {
        self.hidden = NO;
        self.transform = CGAffineTransformMakeScale(0.85, 0.85);
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0
                         animations:^{ self.alpha = 1; self.transform = CGAffineTransformIdentity; } completion:nil];
    } else {
        [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; } completion:^(BOOL f) { if (!self.showing) self.hidden = YES; }];
    }
}

@end
