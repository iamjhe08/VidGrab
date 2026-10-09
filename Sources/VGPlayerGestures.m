#import "VGPlayerGestures.h"
#import "VGTheme.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

static NSString *const kBrightnessKey = @"vgGestureBrightness";
static NSString *const kVolumeKey     = @"vgGestureVolume";
static NSString *const kSeekKey       = @"vgGestureSeek";
static NSString *const kLevelsKey     = @"vgGestureLevels";
static NSString *const kSeekSpanKey   = @"vgGestureSeekSpan";
static NSString *const kBrightRightKey = @"vgGestureBrightnessRight";

// Everything is on until the person turns it off.
static BOOL Flag(NSString *key) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    return [d objectForKey:key] ? [d boolForKey:key] : YES;
}

static NSString *Clock(double s) {
    int t = (int)MAX(0, floor(s));
    if (t >= 3600) return [NSString stringWithFormat:@"%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60];
    return [NSString stringWithFormat:@"%d:%02d", t / 60, t % 60];
}

typedef NS_ENUM(NSInteger, VGGestureMode) { VGGestureNone, VGGestureBrightness, VGGestureVolume, VGGestureSeek };

/// Dark glass with a thin border and a soft shadow, like the rest of VidGrab.
static void StyleGlass(UIVisualEffectView *v, CGFloat radius) {
    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.clipsToBounds = YES;
    v.layer.borderWidth = 1;
    v.layer.borderColor = VGStroke.CGColor;
    v.userInteractionEnabled = NO;
    UIView *tint = [[UIView alloc] initWithFrame:v.bounds];
    tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tint.backgroundColor = [VGSurface colorWithAlphaComponent:0.62];
    [v.contentView addSubview:tint];
}

#pragma mark - On-screen indicators

/// Brightness and volume: an icon, a coral bar that fills from the bottom, and the percentage.
@interface VGLevelHUD : UIVisualEffectView
- (void)setIcon:(NSString *)icon level:(double)level;
@end

@implementation VGLevelHUD {
    UIImageView *_icon;
    UIView *_track;
    VGGradientView *_fill;
    UILabel *_label;
}

static const CGFloat kTrackHeight = 112;

- (instancetype)init {
    self = [super initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    if (!self) return nil;
    self.frame = CGRectMake(0, 0, 56, 208);
    StyleGlass(self, 28);

    _icon = [[UIImageView alloc] initWithFrame:CGRectMake(14, 14, 28, 28)];
    _icon.contentMode = UIViewContentModeCenter;
    _icon.tintColor = UIColor.whiteColor;
    _icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold];
    [self.contentView addSubview:_icon];

    _track = [[UIView alloc] initWithFrame:CGRectMake(21, 52, 14, kTrackHeight)];
    _track.backgroundColor = VGSurface2;
    _track.layer.cornerRadius = 7;
    _track.clipsToBounds = YES;
    [self.contentView addSubview:_track];

    _fill = [VGGradientView new];
    _fill.gradient.colors = @[(id)VGAccent.CGColor, (id)VGAccent2.CGColor];   // top to bottom
    [_track addSubview:_fill];

    _label = [[UILabel alloc] initWithFrame:CGRectMake(0, 172, 56, 22)];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.textColor = UIColor.whiteColor;
    _label.font = VGRounded(13, UIFontWeightBold);
    [self.contentView addSubview:_label];
    return self;
}

- (void)setIcon:(NSString *)icon level:(double)level {
    level = MIN(1, MAX(0, level));
    _icon.image = [UIImage systemImageNamed:icon];
    CGFloat h = round(kTrackHeight * level);
    _fill.frame = CGRectMake(0, kTrackHeight - h, 14, h);
    _label.text = [NSString stringWithFormat:@"%d%%", (int)round(level * 100)];
}

@end

/// Seeking: the new time, how far it moved, and where that is in the video.
@interface VGSeekHUD : UIVisualEffectView
- (void)setTime:(double)time delta:(double)delta duration:(double)duration;
@end

@implementation VGSeekHUD {
    UIImageView *_icon;
    UILabel *_time;
    UILabel *_delta;
    VGProgressBar *_bar;
}

- (instancetype)init {
    self = [super initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    if (!self) return nil;
    self.frame = CGRectMake(0, 0, 172, 112);
    StyleGlass(self, 26);

    _icon = [[UIImageView alloc] initWithFrame:CGRectMake(70, 12, 32, 26)];
    _icon.contentMode = UIViewContentModeCenter;
    _icon.tintColor = VGAccent;
    _icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightBold];
    [self.contentView addSubview:_icon];

    _time = [[UILabel alloc] initWithFrame:CGRectMake(0, 38, 172, 30)];
    _time.textAlignment = NSTextAlignmentCenter;
    _time.textColor = UIColor.whiteColor;
    _time.font = [UIFont monospacedDigitSystemFontOfSize:26 weight:UIFontWeightBold];
    [self.contentView addSubview:_time];

    _delta = [[UILabel alloc] initWithFrame:CGRectMake(0, 68, 172, 18)];
    _delta.textAlignment = NSTextAlignmentCenter;
    _delta.textColor = VGSecondary;
    _delta.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.contentView addSubview:_delta];

    _bar = [[VGProgressBar alloc] initWithFrame:CGRectMake(20, 94, 132, 5)];
    [self.contentView addSubview:_bar];
    return self;
}

- (void)setTime:(double)time delta:(double)delta duration:(double)duration {
    BOOL back = delta < 0;
    _icon.image = [UIImage systemImageNamed:back ? @"backward.fill" : @"forward.fill"];
    _time.text = Clock(time);
    _delta.text = [NSString stringWithFormat:@"%@%@", back ? @"\u2212" : @"+", Clock(fabs(delta))];
    _bar.progress = duration > 0 ? time / duration : 0;
}

@end

#pragma mark - Gestures

@interface VGPlayerGestures () <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIViewController<VGPlayerGestureHost> *host;
@property (nonatomic, strong) UIPanGestureRecognizer *pan;
@property (nonatomic, strong) VGLevelHUD *levelHUD;
@property (nonatomic, strong) VGSeekHUD *seekHUD;
@property (nonatomic, strong) MPVolumeView *volumeView;   // only on screen while the volume is being changed
@property (nonatomic) VGGestureMode mode;
@property (nonatomic) double startValue;                  // brightness, volume or seconds when the swipe began
@property (nonatomic) double target;                      // where a seek is pointing
@property (nonatomic) double savedBrightness;
@property (nonatomic) BOOL brightnessChanged;
@property (nonatomic) NSInteger hideToken;
@end

@implementation VGPlayerGestures

#pragma mark Settings

+ (BOOL)levelsEnabled {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ([d objectForKey:kLevelsKey]) return [d boolForKey:kLevelsKey];
    return Flag(kBrightnessKey) || Flag(kVolumeKey);   // from the two old switches: on unless both were off
}
+ (void)setLevelsEnabled:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:kLevelsKey]; }
+ (BOOL)brightnessOnRight { return [NSUserDefaults.standardUserDefaults boolForKey:kBrightRightKey]; }
+ (void)setBrightnessOnRight:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:kBrightRightKey]; }
+ (BOOL)seekEnabled { return Flag(kSeekKey); }
+ (void)setSeekEnabled:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:kSeekKey]; }

+ (NSArray<NSNumber *> *)seekChoices { return @[@60, @120, @300, @600]; }

+ (NSInteger)seekChoiceIndex {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSInteger i = [d objectForKey:kSeekSpanKey] ? [d integerForKey:kSeekSpanKey] : 1;
    return MIN(MAX(i, 0), (NSInteger)self.seekChoices.count - 1);
}

+ (void)setSeekChoiceIndex:(NSInteger)index { [NSUserDefaults.standardUserDefaults setInteger:index forKey:kSeekSpanKey]; }

+ (NSString *)seekChoiceName:(NSInteger)index {
    int m = [self.seekChoices[index] intValue] / 60;
    return m == 1 ? @"1 minute" : [NSString stringWithFormat:@"%d minutes", m];
}

+ (NSString *)seekShortName { return [NSString stringWithFormat:@"%d min", [self.seekChoices[self.seekChoiceIndex] intValue] / 60]; }

#pragma mark Setup

- (instancetype)initWithHost:(UIViewController<VGPlayerGestureHost> *)host {
    if ((self = [super init])) _host = host;
    return self;
}

- (void)attach {
    UIView *v = self.host.view;
    if (!v || self.pan) return;
    UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    p.maximumNumberOfTouches = 1;
    p.cancelsTouchesInView = NO;
    p.delaysTouchesBegan = NO;
    p.delaysTouchesEnded = NO;
    p.delegate = self;
    [v addGestureRecognizer:p];
    self.pan = p;
}

- (void)detach {
    if (self.mode == VGGestureSeek) [self.host gestureScrubEnded];
    self.mode = VGGestureNone;
    [self restoreBrightness];
    if (self.pan) { [self.pan.view removeGestureRecognizer:self.pan]; self.pan = nil; }
    self.hideToken++;
    [self removeIndicators];
}

- (void)restoreBrightness {
    if (!self.brightnessChanged) return;
    self.brightnessChanged = NO;
    UIScreen.mainScreen.brightness = self.savedBrightness;
}

- (double)duration {
    AVPlayer *p = self.host.gesturePlayer;
    double d = p.currentItem ? CMTimeGetSeconds(p.currentItem.duration) : 0;
    return isfinite(d) && d > 0 ? d : 0;
}

#pragma mark Deciding what a swipe does

// Brightness on one half, volume on the other (only when the phone is sideways), seeking when the swipe goes sideways.
// Swipes that start on a button, or at the very edges of the screen, are left alone.
- (VGGestureMode)modeForPan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    CGPoint t = [g translationInView:v], vel = [g velocityInView:v], loc = [g locationInView:v];
    CGPoint start = CGPointMake(loc.x - t.x, loc.y - t.y);
    CGRect b = v.bounds;
    UIEdgeInsets ins = v.safeAreaInsets;
    if (start.x < 16 || start.x > b.size.width - 16) return VGGestureNone;
    if (start.y < ins.top + 44 || start.y > b.size.height - ins.bottom - 60) return VGGestureNone;

    double dx = fabs(t.x), dy = fabs(t.y);
    if (dx == 0 && dy == 0) { dx = fabs(vel.x); dy = fabs(vel.y); }
    if (dx > dy) {
        if (!VGPlayerGestures.seekEnabled) return VGGestureNone;
        return [self duration] > 1 ? VGGestureSeek : VGGestureNone;
    }
    if (b.size.width < b.size.height) return VGGestureNone;   // upright: only sideways swipes (seeking) work
    BOOL leftHalf = start.x < b.size.width / 2;
    BOOL brightnessHere = leftHalf != VGPlayerGestures.brightnessOnRight;   // left half by default
    if (!VGPlayerGestures.levelsEnabled) return VGGestureNone;
    return brightnessHere ? VGGestureBrightness : VGGestureVolume;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    return [self modeForPan:(UIPanGestureRecognizer *)g] != VGGestureNone;
}

// Leave the player's own buttons and progress bar alone.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    for (UIView *v = touch.view; v && v != g.view; v = v.superview)
        if ([v isKindOfClass:UIControl.class] || [NSStringFromClass(v.class) isEqualToString:@"VGSaveCard"] || [NSStringFromClass(v.class) isEqualToString:@"VGTrackSheet"]) return NO;   // buttons, the save card and the track list handle their own touches
    return YES;
}

#pragma mark Swiping

- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    CGPoint t = [g translationInView:v];
    double range = MAX(v.bounds.size.height * 0.7, 1);   // a swipe over 70% of the height covers the full range

    switch (g.state) {
        case UIGestureRecognizerStateBegan: {
            self.mode = [self modeForPan:g];
            self.hideToken++;
            if (self.mode == VGGestureSeek) {
                self.startValue = CMTimeGetSeconds(self.host.gesturePlayer.currentTime);
                self.target = self.startValue;
                [self.host gestureScrubBegan];
            } else if (self.mode == VGGestureBrightness) {
                self.startValue = UIScreen.mainScreen.brightness;
                if (!self.brightnessChanged) { self.savedBrightness = self.startValue; self.brightnessChanged = YES; }
            } else if (self.mode == VGGestureVolume) {
                self.startValue = AVAudioSession.sharedInstance.outputVolume;
                [self addVolumeViewTo:v];
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (self.mode == VGGestureSeek) {
                double dur = [self duration];
                if (dur <= 0) break;
                double span = [VGPlayerGestures.seekChoices[VGPlayerGestures.seekChoiceIndex] doubleValue];
                double delta = t.x / MAX(v.bounds.size.width, 1) * span;
                self.target = MIN(MAX(self.startValue + delta, 0), dur);
                [self.host gestureScrubToSeconds:self.target];   // the video follows your finger
                [self showSeekIn:v duration:dur];
            } else if (self.mode == VGGestureBrightness) {
                double level = MIN(1, MAX(0, self.startValue - t.y / range));
                UIScreen.mainScreen.brightness = level;
                [self showLevel:level icon:level < 0.5 ? @"sun.min.fill" : @"sun.max.fill" right:VGPlayerGestures.brightnessOnRight in:v];
            } else if (self.mode == VGGestureVolume) {
                double level = MIN(1, MAX(0, self.startValue - t.y / range));
                [self setVolume:level in:v];
                NSString *icon = level <= 0.001 ? @"speaker.slash.fill" : level < 0.34 ? @"speaker.wave.1.fill" : level < 0.67 ? @"speaker.wave.2.fill" : @"speaker.wave.3.fill";
                [self showLevel:level icon:icon right:!VGPlayerGestures.brightnessOnRight in:v];
            }
            break;
        }
        default: {   // finished, cancelled or failed
            if (self.mode == VGGestureSeek) [self.host gestureScrubEnded];
            self.mode = VGGestureNone;
            [self hideSoon];
            break;
        }
    }
}

#pragma mark Volume

// iOS has no public call to set the volume. The hidden volume slider is the usual way.
// It's only on screen during the swipe, so the normal volume pop-up still shows for the side buttons.
- (void)addVolumeViewTo:(UIView *)v {
    if (!self.volumeView) {
        self.volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-2000, -2000, 10, 10)];
        self.volumeView.alpha = 0.01;
    }
    if (self.volumeView.superview != v) [v addSubview:self.volumeView];
    [self.volumeView layoutIfNeeded];
}

- (void)setVolume:(double)level in:(UIView *)v {
    if (!self.volumeView.superview) [self addVolumeViewTo:v];
    for (UIView *s in self.volumeView.subviews) {
        if ([s isKindOfClass:UISlider.class]) { ((UISlider *)s).value = (float)level; break; }
    }
}

#pragma mark Indicators

- (void)showLevel:(double)level icon:(NSString *)icon right:(BOOL)right in:(UIView *)v {
    [self.seekHUD removeFromSuperview];
    if (!self.levelHUD) self.levelHUD = [VGLevelHUD new];
    VGLevelHUD *h = self.levelHUD;
    UIEdgeInsets ins = v.safeAreaInsets;
    CGSize s = h.bounds.size;
    CGFloat x = right ? v.bounds.size.width - ins.right - 20 - s.width : ins.left + 20;
    h.frame = CGRectMake(x, round((v.bounds.size.height - s.height) / 2), s.width, s.height);
    [h setIcon:icon level:level];
    [self present:h in:v];
}

- (void)showSeekIn:(UIView *)v duration:(double)duration {
    [self.levelHUD removeFromSuperview];
    if (!self.seekHUD) self.seekHUD = [VGSeekHUD new];
    VGSeekHUD *h = self.seekHUD;
    CGSize s = h.bounds.size;
    h.frame = CGRectMake(round((v.bounds.size.width - s.width) / 2), round((v.bounds.size.height - s.height) / 2) - 40, s.width, s.height);
    [h setTime:self.target delta:self.target - self.startValue duration:duration];
    [self present:h in:v];
}

- (void)present:(UIView *)h in:(UIView *)v {
    if (h.superview != v) { h.alpha = 0; [v addSubview:h]; }
    [v bringSubviewToFront:h];
    if (h.alpha < 1) [UIView animateWithDuration:0.15 animations:^{ h.alpha = 1; }];
}

- (void)hideSoon {
    NSInteger token = ++self.hideToken;
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        VGPlayerGestures *me = ws;
        if (!me || me.hideToken != token) return;
        UIView *h = me.levelHUD.superview ? (UIView *)me.levelHUD : (UIView *)me.seekHUD;
        [UIView animateWithDuration:0.25 animations:^{ h.alpha = 0; } completion:^(BOOL f) {
            if (me.hideToken == token) [me removeIndicators];
        }];
    });
}

- (void)removeIndicators {
    [self.levelHUD removeFromSuperview];
    [self.seekHUD removeFromSuperview];
    [self.volumeView removeFromSuperview];
}

@end
