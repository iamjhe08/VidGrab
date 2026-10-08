#import "VGProgressPill.h"
#import "VGEngine.h"
#import "VGTheme.h"

// A round download bubble you can drag anywhere, like AssistiveTouch.
// Let go and it snaps to the nearest side. It remembers where you left it.

static const CGFloat kSize = 60;
static NSString *const kSideKey = @"vgBubbleSide";   // 0 = right, 1 = left
static NSString *const kYKey = @"vgBubbleY";         // 0...1 down the screen

@interface VGProgressPill ()
@property (nonatomic, strong) CAShapeLayer *track, *arc;
@property (nonatomic, strong) UILabel *percent, *badge;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic) BOOL showing, dragging;
@property (nonatomic) CGPoint grab;
@end

@implementation VGProgressPill

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, kSize, kSize)])) {
        self.backgroundColor = [VGSurface2 colorWithAlphaComponent:0.96];
        self.layer.cornerRadius = kSize / 2;
        self.layer.borderColor = VGStroke.CGColor;
        self.layer.borderWidth = 1;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.55;
        self.layer.shadowRadius = 14;
        self.layer.shadowOffset = CGSizeMake(0, 5);
        self.accessibilityLabel = @"Downloads in progress";
        self.accessibilityHint = @"Opens Downloads. Drag to move it.";
        self.accessibilityTraits = UIAccessibilityTraitButton;

        CGFloat r = kSize / 2 - 6;
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(kSize / 2, kSize / 2) radius:r
                                                        startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
        _track = [CAShapeLayer layer];
        _track.path = path.CGPath;
        _track.fillColor = UIColor.clearColor.CGColor;
        _track.strokeColor = VGStroke.CGColor;
        _track.lineWidth = 4;
        _arc = [CAShapeLayer layer];
        _arc.path = path.CGPath;
        _arc.fillColor = UIColor.clearColor.CGColor;
        _arc.strokeColor = VGAccent.CGColor;
        _arc.lineWidth = 4;
        _arc.lineCap = kCALineCapRound;
        _arc.strokeEnd = 0;
        [self.layer addSublayer:_track];
        [self.layer addSublayer:_arc];

        _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down"
                                                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightHeavy]]];
        _icon.tintColor = VGAccent;
        _icon.frame = CGRectMake(0, 13, kSize, 12);
        _icon.contentMode = UIViewContentModeCenter;
        [self addSubview:_icon];

        _percent = [[UILabel alloc] initWithFrame:CGRectMake(8, 25, kSize - 16, 20)];
        _percent.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightHeavy];
        _percent.textColor = VGText;
        _percent.textAlignment = NSTextAlignmentCenter;
        _percent.adjustsFontSizeToFitWidth = YES;
        _percent.minimumScaleFactor = 0.6;
        [self addSubview:_percent];

        _badge = [[UILabel alloc] initWithFrame:CGRectMake(kSize - 20, -4, 24, 22)];
        _badge.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightHeavy];
        _badge.textColor = UIColor.whiteColor;
        _badge.backgroundColor = VGAccent;
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.layer.cornerRadius = 11;
        _badge.layer.borderColor = VGBackground.CGColor;
        _badge.layer.borderWidth = 2;
        _badge.clipsToBounds = YES;
        [self addSubview:_badge];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];

        self.hidden = YES;
        self.alpha = 0;
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:self selector:@selector(refresh) name:VGTasksDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(placeSoon) name:UIDeviceOrientationDidChangeNotification object:nil];
    }
    return self;
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    [self placeSoon];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (!self.dragging) self.transform = highlighted ? CGAffineTransformMakeScale(0.92, 0.92) : CGAffineTransformIdentity;
}

#pragma mark Position

// Where the bubble may sit: inside the safe area and above the tab bar.
- (CGRect)allowedArea {
    UIView *sv = self.superview;
    if (!sv || sv.bounds.size.width < 1) return CGRectZero;
    UIEdgeInsets in = sv.safeAreaInsets;
    CGFloat m = 10;
    CGFloat top = in.top + 50, bottom = sv.bounds.size.height - in.bottom - 49 - m;
    return CGRectMake(in.left + m, top, sv.bounds.size.width - in.left - in.right - 2 * m, MAX(kSize, bottom - top));
}

- (void)placeSoon {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self place:NO]; });
}

- (void)place:(BOOL)animated {
    if (self.dragging) return;
    CGRect a = [self allowedArea];
    if (CGRectIsEmpty(a)) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    BOOL left = [d integerForKey:kSideKey] == 1;
    double y = [d objectForKey:kYKey] ? [d doubleForKey:kYKey] : 1.0;   // first time: bottom right
    CGFloat cx = left ? CGRectGetMinX(a) + kSize / 2 : CGRectGetMaxX(a) - kSize / 2;
    CGFloat cy = CGRectGetMinY(a) + kSize / 2 + (a.size.height - kSize) * MIN(1, MAX(0, y));
    void (^move)(void) = ^{ self.center = CGPointMake(cx, cy); };
    if (animated) [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.4 options:0 animations:move completion:nil];
    else move();
    [UIView animateWithDuration:animated ? 0.25 : 0 animations:^{ [self layoutBadge]; }];
}

- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *sv = self.superview;
    CGPoint p = [g locationInView:sv];
    switch (g.state) {
        case UIGestureRecognizerStateBegan: {
            self.dragging = YES;
            self.grab = CGPointMake(p.x - self.center.x, p.y - self.center.y);
            [UIView animateWithDuration:0.15 animations:^{ self.transform = CGAffineTransformMakeScale(1.08, 1.08); }];
            [[UISelectionFeedbackGenerator new] selectionChanged];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGRect a = CGRectInset([self allowedArea], -8, -8);
            CGFloat x = MIN(CGRectGetMaxX(a) - kSize / 2, MAX(CGRectGetMinX(a) + kSize / 2, p.x - self.grab.x));
            CGFloat y = MIN(CGRectGetMaxY(a) - kSize / 2, MAX(CGRectGetMinY(a) + kSize / 2, p.y - self.grab.y));
            self.center = CGPointMake(x, y);
            break;
        }
        default: {
            self.dragging = NO;
            CGRect a = [self allowedArea];
            // A quick flick sends it to the side it was thrown toward.
            CGFloat endX = self.center.x + [g velocityInView:sv].x * 0.15;
            BOOL left = endX < CGRectGetMidX(a);
            double y = (self.center.y - CGRectGetMinY(a) - kSize / 2) / MAX(1, a.size.height - kSize);
            NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
            [d setInteger:left ? 1 : 0 forKey:kSideKey];
            [d setDouble:MIN(1, MAX(0, y)) forKey:kYKey];
            [UIView animateWithDuration:0.2 animations:^{ self.transform = CGAffineTransformIdentity; }];
            [self place:YES];
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
            break;
        }
    }
}

// The count sits just outside the circle, touching it without covering it, on the
// top corner that faces the middle of the screen (so it never goes off the edge).
- (void)layoutBadge {
    CGFloat bw = self.badge.bounds.size.width;
    BOOL onRight = self.center.x > CGRectGetMidX(self.superview.bounds);
    (void)onRight;
    CGFloat x = kSize - 12;   // always top right
    self.badge.frame = CGRectMake(x, -10, bw, 22);
}

#pragma mark Content

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
        self.percent.text = lead.state == VGTaskQueued ? @"Wait" : [NSString stringWithFormat:@"%d%%", (int)round(lead.fraction * 100)];
    }
    self.badge.text = [NSString stringWithFormat:@"%lu", (unsigned long)n];
    CGFloat bw = MAX(22, [self.badge.text sizeWithAttributes:@{NSFontAttributeName: self.badge.font}].width + 12);
    self.badge.bounds = CGRectMake(0, 0, bw, 22);
    [self layoutBadge];
    self.badge.hidden = n < 2;
    self.accessibilityValue = [NSString stringWithFormat:@"%@, %lu %@", self.percent.text, (unsigned long)n, n == 1 ? @"download" : @"downloads"];

    if (show == self.showing) return;
    self.showing = show;
    if (show) {
        [self.superview bringSubviewToFront:self];
        [self place:NO];
        self.hidden = NO;
        self.transform = CGAffineTransformMakeScale(0.6, 0.6);
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.65 initialSpringVelocity:0.6 options:0
                         animations:^{ self.alpha = 1; self.transform = CGAffineTransformIdentity; } completion:nil];
    } else {
        [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; self.transform = CGAffineTransformMakeScale(0.6, 0.6); }
                         completion:^(BOOL f) { if (!self.showing) { self.hidden = YES; self.transform = CGAffineTransformIdentity; } }];
    }
}

@end
