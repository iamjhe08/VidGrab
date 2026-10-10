#import "VGDownloadDefaults.h"
#import "VGActions.h"
#import "VGTheme.h"
#import "VGKeepAlive.h"
#import "VGPlayerGestures.h"
#import "VGSubtitles.h"
#import "VGLive.h"
#import "VGMusic.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <MediaPlayer/MediaPlayer.h>

// VidGrab's own video player: themed controls, live scrubbing, screen size (fit, fill, stretch),
// playback speed, picture-in-picture, background sound, lock screen controls and resume.

@class VGPlayerViewController;
/// The small bar that keeps a video playing at the bottom of the app after the player is pressed down.
@interface VGMiniVideoView : UIView
+ (void)showFor:(VGPlayerViewController *)player;
+ (void)closeOthersThan:(VGPlayerViewController *)player;
+ (BOOL)activeFor:(VGPlayerViewController *)player;
@end

static NSMutableSet *gPiPPlayers;   // players kept alive while in picture-in-picture after closing
static NSInteger gOpenPlayers;      // players on screen or in picture-in-picture
static NSInteger gOnScreen;         // players being shown full screen
static BOOL gPreparing;             // a player is about to appear (so landscape is allowed in time)

BOOL VGPlayerIsActive(void) { return gOpenPlayers > 0; }
BOOL VGPlayerIsOnScreen(void) { return gOnScreen > 0 || gPreparing; }

static NSString *PClock(double s) {
    int t = (int)MAX(0, floor(s));
    if (t >= 3600) return [NSString stringWithFormat:@"%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60];
    return [NSString stringWithFormat:@"%d:%02d", t / 60, t % 60];
}

static NSString *const kAspectKey = @"vgPlayerAspect";
static NSString *const kMiniBarKey = @"vgPlayerMiniBar";

// Screen sizes. A ratio of 0 means "use the video's own".
static NSArray<NSDictionary *> *Sizes(void) {
    return @[
        @{@"name": @"Fit to screen", @"icon": @"arrow.down.right.and.arrow.up.left", @"gravity": AVLayerVideoGravityResizeAspect,     @"ratio": @0},
        @{@"name": @"Fill screen",   @"icon": @"aspectratio.fill", @"gravity": AVLayerVideoGravityResizeAspectFill, @"ratio": @0},
        @{@"name": @"Stretch",       @"icon": @"arrow.up.left.and.arrow.down.right", @"gravity": AVLayerVideoGravityResize,           @"ratio": @0},
        @{@"name": @"16:9",          @"icon": @"rectangle",                         @"gravity": AVLayerVideoGravityResize,           @"ratio": @(16.0 / 9.0)},
        @{@"name": @"4:3",           @"icon": @"aspectratio",                       @"gravity": AVLayerVideoGravityResize,           @"ratio": @(4.0 / 3.0)},
    ];
}

#pragma mark - Small views

/// The picture itself.
@interface VGVideoView : UIView
@property (nonatomic, readonly) AVPlayerLayer *playerLayer;
@end

@implementation VGVideoView
+ (Class)layerClass { return AVPlayerLayer.class; }
- (AVPlayerLayer *)playerLayer { return (AVPlayerLayer *)self.layer; }
@end

/// The progress bar: a thin track with the app's coral gradient and a round handle that grows when touched.
@interface VGScrubber : UIControl
@property (nonatomic) double progress;   // 0 to 1
@property (nonatomic, readonly) BOOL scrubbing;
@property (nonatomic, copy) void (^onBegin)(void);
@property (nonatomic, copy) void (^onMove)(double progress);
@property (nonatomic, copy) void (^onEnd)(void);
@end

@implementation VGScrubber {
    UIView *_track;
    VGGradientView *_fill;
    UIView *_thumb;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _track = [UIView new];
        _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.26];
        _track.clipsToBounds = YES;
        _track.userInteractionEnabled = NO;
        [self addSubview:_track];
        _fill = [VGGradientView new];
        _fill.gradient.colors = @[(id)VGAccent.CGColor, (id)VGAccent2.CGColor];
        _fill.gradient.startPoint = CGPointMake(0, 0.5);
        _fill.gradient.endPoint = CGPointMake(1, 0.5);
        _fill.userInteractionEnabled = NO;
        [_track addSubview:_fill];
        _thumb = [UIView new];
        _thumb.backgroundColor = UIColor.whiteColor;
        _thumb.userInteractionEnabled = NO;
        _thumb.layer.shadowColor = UIColor.blackColor.CGColor;
        _thumb.layer.shadowOpacity = 0.4;
        _thumb.layer.shadowRadius = 3;
        _thumb.layer.shadowOffset = CGSizeMake(0, 1);
        [self addSubview:_thumb];
    }
    return self;
}

- (void)setProgress:(double)progress {
    _progress = MIN(1, MAX(0, progress));
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = _scrubbing ? 8 : 4, inset = 10;
    CGRect tr = CGRectMake(inset, round((self.bounds.size.height - h) / 2), MAX(self.bounds.size.width - inset * 2, 1), h);
    _track.frame = tr;
    _track.layer.cornerRadius = h / 2;
    _fill.frame = CGRectMake(0, 0, tr.size.width * _progress, h);
    CGFloat d = _scrubbing ? 24 : 14;
    _thumb.frame = CGRectMake(tr.origin.x + tr.size.width * _progress - d / 2, CGRectGetMidY(tr) - d / 2, d, d);
    _thumb.layer.cornerRadius = d / 2;
}

- (double)progressFor:(UITouch *)t {
    CGFloat w = MAX(self.bounds.size.width - 20, 1);
    return MIN(1, MAX(0, ([t locationInView:self].x - 10) / w));
}

- (void)setScrubbing:(BOOL)on {
    _scrubbing = on;
    [UIView animateWithDuration:0.15 animations:^{ [self layoutSubviews]; }];
}

- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    [self setScrubbing:YES];
    if (self.onBegin) self.onBegin();
    self.progress = [self progressFor:t];
    if (self.onMove) self.onMove(self.progress);
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    self.progress = [self progressFor:t];
    if (self.onMove) self.onMove(self.progress);
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    if (t) { self.progress = [self progressFor:t]; if (self.onMove) self.onMove(self.progress); }
    [self setScrubbing:NO];
    if (self.onEnd) self.onEnd();
}

- (void)cancelTrackingWithEvent:(UIEvent *)e {
    [self setScrubbing:NO];
    if (self.onEnd) self.onEnd();
}

// A taller touch area than the thin track.
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e { return CGRectContainsPoint(CGRectInset(self.bounds, -6, -8), p); }

@end

/// A round dark-glass button with an icon.
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>

/// Average chip temperature in °C from iOS's own sensors, or 0 when this iPhone does not let apps read them.
static float VGCPUTemperature(void) {
    static void *(*create)(CFAllocatorRef);
    static int (*setMatching)(void *, CFDictionaryRef);
    static CFArrayRef (*copyServices)(void *);
    static void *(*copyEvent)(void *, int64_t, int32_t, int64_t);
    static double (*floatValue)(void *, int32_t);
    static void *client; static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (!h) return;
        create = dlsym(h, "IOHIDEventSystemClientCreate");
        setMatching = dlsym(h, "IOHIDEventSystemClientSetMatching");
        copyServices = dlsym(h, "IOHIDEventSystemClientCopyServices");
        copyEvent = dlsym(h, "IOHIDServiceClientCopyEvent");
        floatValue = dlsym(h, "IOHIDEventGetFloatValue");
        if (create && setMatching && copyServices && copyEvent && floatValue) {
            client = create(kCFAllocatorDefault);
            if (client) {
                int page = 0xff00, usage = 5;
                CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page), u = CFNumberCreate(NULL, kCFNumberIntType, &usage);
                const void *k[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") }, *v[] = { p, u };
                CFDictionaryRef m = CFDictionaryCreate(NULL, k, v, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                setMatching(client, m);
                CFRelease(m); CFRelease(p); CFRelease(u);
            }
        }
    });
    if (!client) return 0;
    CFArrayRef list = copyServices(client);
    if (!list) return 0;
    double sum = 0; int n = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
        void *ev = copyEvent((void *)CFArrayGetValueAtIndex(list, i), 15, 0, 0);   // 15 = temperature
        if (!ev) continue;
        double t = floatValue(ev, 15 << 16);
        CFRelease(ev);
        if (t > 10 && t < 110) { sum += t; n++; }
    }
    CFRelease(list);
    return n ? (float)(sum / n) : 0;
}

static NSInteger OptHeight(VGOption *o) {
    NSString *r = o.res ?: @"";
    if ([r hasPrefix:@"4K"]) return 2160;
    if ([r hasPrefix:@"2K"]) return 1440;
    return r.integerValue;
}

static NSString *FPSFromRes(NSString *res) {
    NSRange r = [res rangeOfString:@"(\\d+)\\s*fps" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch];
    if (r.location == NSNotFound) return nil;
    NSInteger n = [[res substringWithRange:r] integerValue];
    return n > 30 ? [NSString stringWithFormat:@"%ld", (long)n] : nil;
}

static UIButton *RoundButton(NSString *symbol, CGFloat diameter, CGFloat pointSize) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:c] forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    b.backgroundColor = [VGSurface colorWithAlphaComponent:0.78];
    b.layer.cornerRadius = diameter / 2;
    b.layer.borderWidth = 1;
    b.layer.borderColor = VGStroke.CGColor;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.widthAnchor constraintEqualToConstant:diameter].active = YES;
    [b.heightAnchor constraintEqualToConstant:diameter].active = YES;
    return b;
}

static void SetSymbol(UIButton *b, NSString *symbol, CGFloat pointSize) {
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:c] forState:UIControlStateNormal];
}

static UILabel *TimeLabel(NSTextAlignment align) {
    UILabel *l = [UILabel new];
    l.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    l.textColor = [UIColor colorWithWhite:1 alpha:0.92];
    l.textAlignment = align;
    l.text = @"0:00";
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [l.widthAnchor constraintEqualToConstant:54].active = YES;
    return l;
}

#pragma mark - Player


#pragma mark Save sheet

/// The "pick a quality to download" card shown over the player while streaming.
@interface VGSaveCard : UIView
@property (nonatomic, copy) void (^onPick)(VGOption *option);
@property (nonatomic, strong) NSArray<VGOption *> *options;
@property (nonatomic, strong) NSMutableArray<UIControl *> *rows;
@property (nonatomic, strong) NSMutableArray<UIImageView *> *ticks;
@property (nonatomic, strong) VGOption *chosen;
@property (nonatomic, strong) VGOption *playing;
@property (nonatomic, strong) UIButton *go;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) NSLayoutConstraint *scrollHeight;
@property (nonatomic, strong) UIStackView *list;
@end

@implementation VGSaveCard

- (instancetype)initWithVideo:(VGVideo *)video playing:(VGOption *)playing {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.options = video.options;
    self.playing = playing;
    for (VGOption *o in self.options) if (playing && [o.identifier isEqualToString:playing.identifier]) self.chosen = o;
    if (!self.chosen) for (VGOption *o in self.options) if (!o.audio) { self.chosen = o; break; }
    if (!self.chosen) self.chosen = self.options.firstObject;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];

    self.card = [UIView new];
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    self.card.layer.cornerRadius = 28;
    self.card.layer.cornerCurve = kCACornerCurveContinuous;
    self.card.clipsToBounds = YES;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    [self addSubview:self.card];
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:blur];

    UIView *grab = [UIView new];
    grab.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
    grab.layer.cornerRadius = 2.5;
    grab.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *grabHolder = [UIView new];
    [grabHolder addSubview:grab];
    [NSLayoutConstraint activateConstraints:@[
        [grab.centerXAnchor constraintEqualToAnchor:grabHolder.centerXAnchor], [grab.topAnchor constraintEqualToAnchor:grabHolder.topAnchor],
        [grab.bottomAnchor constraintEqualToAnchor:grabHolder.bottomAnchor], [grabHolder.heightAnchor constraintEqualToConstant:5]]];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightSemibold]]];
    icon.tintColor = VGAccent;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:36].active = YES;
    [icon.heightAnchor constraintEqualToConstant:36].active = YES;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *head = [UILabel new];
    head.text = @"Save this video";
    head.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    head.textColor = UIColor.whiteColor;
    UILabel *sub = [UILabel new];
    sub.text = video.title.length ? video.title : @"Pick a quality";
    sub.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    sub.numberOfLines = 1;
    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[head, sub]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 2;
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[icon, texts]];
    top.spacing = 12;
    top.alignment = UIStackViewAlignmentCenter;

    self.rows = [NSMutableArray array];
    self.ticks = [NSMutableArray array];
    self.list = [UIStackView new];
    self.list.axis = UILayoutConstraintAxisVertical;
    self.list.spacing = 8;
    self.list.translatesAutoresizingMaskIntoConstraints = NO;
    for (VGOption *o in self.options) [self.list addArrangedSubview:[self rowFor:o]];
    self.scroll = [UIScrollView new];
    self.scroll.showsVerticalScrollIndicator = NO;
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scroll addSubview:self.list];

    self.go = [UIButton buttonWithType:UIButtonTypeCustom];
    self.go.backgroundColor = VGAccent;
    self.go.layer.cornerRadius = 26;
    self.go.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.go setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.go addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    self.go.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[grabHolder, top, self.scroll, self.go]];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 14;
    col.alignment = UIStackViewAlignmentFill;
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [col setCustomSpacing:18 afterView:top];
    [self.card addSubview:col];

    self.scrollHeight = [self.scroll.heightAnchor constraintEqualToConstant:200];
    NSLayoutConstraint *lead = [self.card.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:12];
    lead.priority = 750;
    NSLayoutConstraint *trail = [self.card.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-12];
    trail.priority = 750;
    [NSLayoutConstraint activateConstraints:@[
        lead, trail,
        [self.card.widthAnchor constraintLessThanOrEqualToConstant:440],
        [self.card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.card.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [blur.topAnchor constraintEqualToAnchor:self.card.topAnchor], [blur.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor], [blur.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
        [col.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:10],
        [col.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-18],
        [col.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:18],
        [col.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-18],
        [grab.widthAnchor constraintEqualToConstant:36],
        [self.go.heightAnchor constraintEqualToConstant:52],
        self.scrollHeight,
        [self.list.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],
        [self.list.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],
        [self.list.leadingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.leadingAnchor],
        [self.list.trailingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.trailingAnchor],
        [self.list.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor]]];
    [self refresh];
    return self;
}

- (void)choose:(VGOption *)o {
    for (VGOption *x in self.options) if ([x.identifier isEqualToString:o.identifier]) { self.chosen = x; break; }
    [self refresh];
}

- (UIControl *)rowFor:(VGOption *)o {
    UIControl *r = [UIControl new];
    r.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    r.layer.cornerRadius = 16;
    r.layer.cornerCurve = kCACornerCurveContinuous;
    r.layer.borderWidth = 1.5;
    r.translatesAutoresizingMaskIntoConstraints = NO;
    [r.heightAnchor constraintEqualToConstant:58].active = YES;
    [r addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];

    UILabel *res = [UILabel new];
    res.text = o.audio ? @"Audio only" : o.res;
    res.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    res.textColor = UIColor.whiteColor;
    NSMutableArray *bits = [NSMutableArray array];
    if (o.format.length) [bits addObject:o.format];
    if (o.convert) [bits addObject:@"converted for iPhone"];
    if (self.playing && [o.identifier isEqualToString:self.playing.identifier]) [bits insertObject:@"now playing" atIndex:0];
    UILabel *meta = [UILabel new];
    meta.text = [bits componentsJoinedByString:@" · "];
    meta.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    meta.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    UIStackView *l = [[UIStackView alloc] initWithArrangedSubviews:@[res, meta]];
    l.axis = UILayoutConstraintAxisVertical;
    l.spacing = 1;
    l.userInteractionEnabled = NO;

    UILabel *size = [UILabel new];
    size.text = o.sizeText;
    size.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
    size.textColor = [UIColor colorWithWhite:1 alpha:0.75];
    UIImageView *tick = [UIImageView new];
    tick.translatesAutoresizingMaskIntoConstraints = NO;
    [tick.widthAnchor constraintEqualToConstant:24].active = YES;
    [self.ticks addObject:tick];
    UIStackView *rt = [[UIStackView alloc] initWithArrangedSubviews:@[size, tick]];
    rt.spacing = 10;
    rt.alignment = UIStackViewAlignmentCenter;
    rt.userInteractionEnabled = NO;

    UIStackView *h = [[UIStackView alloc] initWithArrangedSubviews:@[l, rt]];
    h.alignment = UIStackViewAlignmentCenter;
    h.translatesAutoresizingMaskIntoConstraints = NO;
    h.userInteractionEnabled = NO;
    [r addSubview:h];
    [NSLayoutConstraint activateConstraints:@[
        [h.leadingAnchor constraintEqualToAnchor:r.leadingAnchor constant:16], [h.trailingAnchor constraintEqualToAnchor:r.trailingAnchor constant:-14],
        [h.topAnchor constraintEqualToAnchor:r.topAnchor], [h.bottomAnchor constraintEqualToAnchor:r.bottomAnchor]]];
    [self.rows addObject:r];
    return r;
}

/// Tapping outside the card closes it (no gesture recognizer, so nothing can get in the way of the rows).
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint pt = [touches.anyObject locationInView:self];
    if (!CGRectContainsPoint(self.card.frame, pt)) [self dismiss];
}

- (void)rowTapped:(UIControl *)r {
    NSUInteger i = [self.rows indexOfObject:r];
    if (i == NSNotFound) return;
    self.chosen = self.options[i];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [UIView animateWithDuration:0.18 animations:^{ [self refresh]; }];
}

- (void)refresh {
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
    for (NSUInteger i = 0; i < self.options.count; i++) {
        BOOL on = self.options[i] == self.chosen;
        self.rows[i].layer.borderColor = (on ? VGAccent : UIColor.clearColor).CGColor;
        self.rows[i].backgroundColor = on ? [VGAccent colorWithAlphaComponent:0.18] : [UIColor colorWithWhite:1 alpha:0.07];
        self.ticks[i].image = [UIImage systemImageNamed:on ? @"checkmark.circle.fill" : @"circle" withConfiguration:c];
        self.ticks[i].tintColor = on ? VGAccent : [UIColor colorWithWhite:1 alpha:0.3];
    }
    VGOption *o = self.chosen;
    NSString *what = o.audio ? @"audio" : o.res;
    NSString *t = o.sizeText.length ? [NSString stringWithFormat:@"Download %@  ·  %@", what, o.sizeText] : [NSString stringWithFormat:@"Download %@", what];
    [self.go setTitle:t forState:UIControlStateNormal];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat want = [self.list systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    CGFloat room = MAX(110, self.bounds.size.height - 260);
    CGFloat h = MIN(MIN(want, 300), room);
    if (fabs(self.scrollHeight.constant - h) > 0.5) self.scrollHeight.constant = h;
}

- (void)confirm {
    VGOption *o = self.chosen;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    [self closeThen:^{ if (self.onPick) self.onPick(o); }];
}

- (void)dismiss { [self closeThen:nil]; }

- (void)closeThen:(void (^)(void))after {
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.alpha = 0;
        self.card.transform = CGAffineTransformMakeTranslation(0, 40);
    } completion:^(BOOL f) { [self removeFromSuperview]; if (after) after(); }];
}

- (void)presentIn:(UIView *)host {
    self.frame = host.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.alpha = 0;
    [host addSubview:self];
    [self layoutIfNeeded];
    self.card.transform = CGAffineTransformMakeTranslation(0, self.bounds.size.height * 0.5);
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.4 options:0 animations:^{
        self.alpha = 1;
        self.card.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end



#pragma mark Track list (playlist mode)

@interface VGTrackSheet : UIView <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, copy) void (^onPick)(NSInteger position);
@property (nonatomic, copy) NSDictionary *(^provider)(void);   // asked now and then, so the highlight follows the playing track
@property (nonatomic, strong) NSArray<NSString *> *titles;
@property (nonatomic) NSInteger current;
@property (nonatomic, strong) UIVisualEffectView *card;   // the same frosted panel as the Library music player
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *header, *grab;
@property (nonatomic, strong) UILabel *head;
@property (nonatomic, strong) UIButton *closeB;
@end

@implementation VGTrackSheet {
    UIViewPropertyAnimator *_blur;
    BOOL _closing;
    NSTimer *_poll;
}

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles current:(NSInteger)current {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.titles = titles; self.current = current;
    self.backgroundColor = UIColor.clearColor;   // no dimming: the player shows through the glass, like the Library player
    UITapGestureRecognizer *outside = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    outside.delegate = self;
    [self addGestureRecognizer:outside];
    self.card = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.card.layer.cornerRadius = 28;
    self.card.layer.cornerCurve = kCACornerCurveContinuous;
    self.card.clipsToBounds = YES;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    [self addSubview:self.card];
    UIView *c = self.card.contentView;
    c.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];   // clearly darker than the Library player so the list reads easily
    self.header = [UIView new];
    [c addSubview:self.header];
    self.grab = [UIView new];
    self.grab.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
    self.grab.layer.cornerRadius = 2.5;
    [self.header addSubview:self.grab];
    self.head = [UILabel new];
    self.head.text = [NSString stringWithFormat:@"Playlist  \u00b7  %lu tracks", (unsigned long)titles.count];
    self.head.font = [UIFont systemFontOfSize:20 weight:UIFontWeightHeavy];
    self.head.textColor = UIColor.whiteColor;
    [self.header addSubview:self.head];
    self.closeB = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeB setImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    self.closeB.tintColor = UIColor.whiteColor;
    self.closeB.accessibilityLabel = @"Close track list";
    [self.closeB addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.header addSubview:self.closeB];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.table.dataSource = self; self.table.delegate = self;
    self.table.rowHeight = 56;
    [c addSubview:self.table];
    // Drag the top of the sheet down to close it, like the Library player.
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
    pan.delegate = self;
    [self.header addGestureRecognizer:pan];
    return self;
}

/// A light frosted glass: only part of the blur is applied, so what is behind shows through as soft shapes.
- (void)applyBlur {
    if (_blur) { [_blur stopAnimation:YES]; _blur = nil; self.card.effect = nil; }
    UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:1 curve:UIViewAnimationCurveLinear animations:^{
        self.card.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    }];
    a.pausesOnCompletion = YES;
    a.fractionComplete = 0.45;
    _blur = a;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self applyBlur];
        __weak typeof(self) ws = self;
        _poll = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *t) { [ws syncFromProvider]; }];
    } else { [_poll invalidate]; _poll = nil; }
}
- (void)dealloc { [_blur stopAnimation:YES]; [_poll invalidate]; }

/// Follows the playing track (and the play order) while the sheet stays open.
- (void)syncFromProvider {
    if (!self.provider || _closing) return;
    NSDictionary *d = self.provider();
    NSArray *t = d[@"titles"]; NSInteger cur = [d[@"current"] integerValue];
    if (![t isKindOfClass:NSArray.class] || !t.count) return;
    BOOL changed = cur != self.current || ![t isEqualToArray:self.titles];
    if (!changed) return;
    self.titles = t; self.current = cur;
    [self.table reloadData];
}

- (CGFloat)sheetHeight {
    CGFloat H = self.bounds.size.height - self.safeAreaInsets.bottom - 8;
    CGFloat h = MIN(H, MAX(H * 0.66, 400));
    if (self.bounds.size.height < self.bounds.size.width) h = MIN(self.bounds.size.height - 30, 340);   // landscape
    return h;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat side = 8, sh = [self sheetHeight], W = MIN(b.size.width - 2 * side, 640);
    self.card.bounds = CGRectMake(0, 0, W, sh);   // placed by bounds and center so a drag in progress is not disturbed
    self.card.center = CGPointMake(b.size.width / 2, b.size.height - self.safeAreaInsets.bottom - 8 - sh / 2);
    self.card.contentView.frame = self.card.bounds;
    self.header.frame = CGRectMake(0, 0, W, 62);
    self.grab.frame = CGRectMake(W / 2 - 19, 8, 38, 5);
    self.head.frame = CGRectMake(22, 18, W - 90, 28);
    self.closeB.frame = CGRectMake(W - 60, 10, 44, 44);
    self.table.frame = CGRectMake(0, 62, W, sh - 62);
}

// Only a tap outside the card closes the sheet, so taps on the list reach the rows. The drag only starts downward.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    if ([g isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    return !CGRectContainsPoint(self.card.frame, [t locationInView:self]);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (![g isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    CGPoint v = [(UIPanGestureRecognizer *)g velocityInView:self];
    return fabs(v.y) > fabs(v.x) && v.y > -50;
}

- (void)dragged:(UIPanGestureRecognizer *)g {
    CGFloat dy = MAX(0, [g translationInView:self].y);
    if (g.state == UIGestureRecognizerStateChanged) {
        self.card.transform = CGAffineTransformMakeTranslation(0, dy);
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGFloat vy = [g velocityInView:self].y;
        if (g.state == UIGestureRecognizerStateEnded && (dy > self.card.bounds.size.height * 0.25 || vy > 900)) {
            [self dismiss];
        } else {
            [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{ self.card.transform = CGAffineTransformIdentity; } completion:nil];
        }
    }
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.titles.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"t"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"t"];
    BOOL now = ip.row == self.current;
    c.backgroundColor = now ? [VGAccent colorWithAlphaComponent:0.16] : UIColor.clearColor;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.textLabel.text = self.titles[ip.row];
    c.textLabel.font = [UIFont systemFontOfSize:16 weight:now ? UIFontWeightBold : UIFontWeightSemibold];
    c.textLabel.textColor = now ? VGAccent : UIColor.whiteColor;
    c.textLabel.numberOfLines = 2;
    UILabel *n = [UILabel new];
    n.frame = CGRectMake(0, 0, 44, 30);
    n.textAlignment = NSTextAlignmentCenter;
    if (now) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"waveform" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold]]];
        iv.tintColor = VGAccent; iv.contentMode = UIViewContentModeCenter; iv.frame = CGRectMake(0, 0, 44, 30);
        c.accessoryView = iv;
    } else {
        n.text = [NSString stringWithFormat:@"%ld", (long)ip.row + 1];
        n.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        n.textColor = [UIColor colorWithWhite:1 alpha:0.45];
        c.accessoryView = n;
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:NO];
    NSInteger pos = ip.row;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    if (pos == self.current) return;
    self.current = pos;            // highlight it at once; the list stays open so you can pick again
    [self.table reloadData];
    if (self.onPick) self.onPick(pos);
}

- (void)dismiss { [self closeThen:nil]; }

// Slides away the same way the Library player does.
- (void)closeThen:(void (^)(void))after {
    if (_closing) return;
    _closing = YES;
    CGFloat sh = self.card.bounds.size.height;
    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.card.transform = CGAffineTransformMakeTranslation(0, sh + 40);
    } completion:^(BOOL f) { [self removeFromSuperview]; if (after) after(); }];
}

// Slides up the same way the Library player does.
- (void)presentIn:(UIView *)host {
    self.frame = host.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:self];
    [self layoutIfNeeded];
    if (self.current >= 0 && self.current < (NSInteger)self.titles.count)
        [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.current inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    CGFloat sh = self.card.bounds.size.height;
    self.card.transform = CGAffineTransformMakeTranslation(0, sh + 40);
    [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.2 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.card.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark Banner shown while the picture is off

@interface VGBannerView : UIView
@end

@implementation VGBannerView {
    CAGradientLayer *_glow, *_vignette;
    UIImageView *_pic; UILabel *_name, *_sub;
    NSLayoutConstraint *_iconW, *_iconH, *_stackY;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = VGBackground;
        self.userInteractionEnabled = NO;
        _glow = [CAGradientLayer layer];
        _glow.type = kCAGradientLayerRadial;
        _glow.colors = @[(id)[VGAccent colorWithAlphaComponent:0.34].CGColor, (id)[VGAccent2 colorWithAlphaComponent:0.10].CGColor, (id)UIColor.clearColor.CGColor];
        _glow.locations = @[@0, @0.45, @1];
        _glow.startPoint = CGPointMake(0.5, 0.46);
        _glow.endPoint = CGPointMake(1.0, 1.0);
        [self.layer addSublayer:_glow];

        UIImage *icon = VGThemedIcon();
        UIImageView *pic = [[UIImageView alloc] initWithImage:icon];
        pic.contentMode = UIViewContentModeScaleAspectFill;
        pic.clipsToBounds = YES;
        pic.layer.cornerRadius = 27; _pic = pic;
        pic.layer.cornerCurve = kCACornerCurveContinuous;
        pic.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *iv = [UIView new];   // holds the glow; the picture inside has the rounded corners
        iv.layer.shadowColor = VGAccent.CGColor;
        iv.layer.shadowOpacity = 0.6;
        iv.layer.shadowRadius = 30;
        iv.layer.shadowOffset = CGSizeZero;
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        [iv addSubview:pic];
        [NSLayoutConstraint activateConstraints:@[[pic.topAnchor constraintEqualToAnchor:iv.topAnchor], [pic.bottomAnchor constraintEqualToAnchor:iv.bottomAnchor],
                                                  [pic.leadingAnchor constraintEqualToAnchor:iv.leadingAnchor], [pic.trailingAnchor constraintEqualToAnchor:iv.trailingAnchor]]];
        UILabel *name = [UILabel new];
        name.text = @"VidGrab";
        name.textColor = UIColor.whiteColor;
        name.font = VGRounded(34, UIFontWeightHeavy); _name = name;
        UILabel *sub = [UILabel new];
        sub.text = @"By: T4MAG0";
        sub.textColor = VGSecondary;
        sub.font = VGFont(13, UIFontWeightSemibold); _sub = sub;
        UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:@[iv, name, sub]];
        st.axis = UILayoutConstraintAxisVertical;
        st.alignment = UIStackViewAlignmentCenter;
        st.spacing = 10;
        [st setCustomSpacing:18 afterView:iv];
        st.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:st];
        [NSLayoutConstraint activateConstraints:@[
            (_iconW = [iv.widthAnchor constraintEqualToConstant:120]), (_iconH = [iv.heightAnchor constraintEqualToConstant:120]),
            [st.centerXAnchor constraintEqualToAnchor:self.centerXAnchor], (_stackY = [st.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30])]];

        // A dark edge on every corner so the logo stands out.
        _vignette = [CAGradientLayer layer];
        _vignette.type = kCAGradientLayerRadial;
        _vignette.colors = @[(id)UIColor.clearColor.CGColor, (id)[UIColor colorWithWhite:0 alpha:0.35].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.96].CGColor];
        _vignette.locations = @[@0.38, @0.7, @1];
        _vignette.startPoint = CGPointMake(0.5, 0.5);
        _vignette.endPoint = CGPointMake(1.0, 1.0);
        [self.layer addSublayer:_vignette];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _glow.frame = self.bounds;
    _vignette.frame = self.bounds;
    [CATransaction commit];
    // Bigger logo and text in portrait, where there is room; landscape keeps the compact size so nothing overlaps.
    BOOL portrait = self.bounds.size.height > self.bounds.size.width;
    CGFloat icon = portrait ? MIN(190, MAX(120, self.bounds.size.width * 0.46)) : 120;
    if (fabs(_iconW.constant - icon) > 0.5) {
        _iconW.constant = _iconH.constant = icon;
        _stackY.constant = portrait ? -52 : -30;
        _pic.layer.cornerRadius = icon * 0.225;
        _name.font = VGRounded(icon * 0.283, UIFontWeightHeavy);
        _sub.font = VGFont(MAX(13, icon * 0.095), UIFontWeightSemibold);
    }
}

@end

@interface VGPlayerViewController () <AVPictureInPictureControllerDelegate, UIGestureRecognizerDelegate, VGPlayerGestureHost>
@property (nonatomic, strong) AVPlayer *keptPlayer;   // stays alive while the picture is detached for background sound
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic, copy) NSString *artistText, *albumText;
@property (nonatomic, copy) NSString *artFetchURL;   // the picture being fetched for the lock screen
@property (nonatomic) BOOL audioOnly;
@property (nonatomic) double speed;
@property (nonatomic) NSInteger sizeIndex;       // the viewer's choice for landscape (remembered)
@property (nonatomic) NSInteger portraitIndex;   // portrait always starts at the default

@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) id saveObserver;
@property (nonatomic) BOOL inPiP;
@property (nonatomic) BOOL counted;
@property (nonatomic) BOOL onScreenCounted;
@property (nonatomic) BOOL started;
@property (nonatomic) BOOL restoring;   // coming back from picture-in-picture to full screen
@property (nonatomic) BOOL minimized;   // pressed down: still playing in the small bar

@property (nonatomic, strong) VGVideoView *videoView;
@property (nonatomic, strong) UIView *controls;
@property (nonatomic, strong) UIButton *closeButton, *pipButton, *playButton, *backButton, *forwardButton;
@property (nonatomic, strong) UIButton *speedButton, *sizeButton, *rotateButton, *captionsButton, *saveButton;
@property (nonatomic, strong) VGVideo *streamVideo;     // set when this plays from the internet
@property (nonatomic, strong) VGOption *streamOption;
@property (nonatomic) BOOL savingStream;
@property (nonatomic) BOOL streamFailed;
@property (nonatomic, strong) AVRoutePickerView *routeButton;
@property (nonatomic, strong) UIButton *qualityLabel;
@property (nonatomic, strong) UIButton *heatPill;
@property (nonatomic) CFTimeInterval lastHeatCheck;
@property (nonatomic, assign) NSUInteger switchToken;
@property (nonatomic, assign) BOOL switchPending;
@property (nonatomic, assign) BOOL preparingHigh;
@property (nonatomic, strong) VGLiveStream *live;   // 2K and 4K made on the phone while playing
@property (nonatomic) NSUInteger liveToken;
@property (nonatomic) BOOL livePending;   // 2K is being prepared: the lower quality stays paused
@property (nonatomic) double liveOffset;   // second of the video where the live picture begins
@property (nonatomic, strong) NSMutableDictionary<NSString *, AVPlayerItem *> *warmItems;   // qualities opened ahead of time, ready to switch to
@property (nonatomic, strong) NSMutableSet<NSString *> *warming;
@property (nonatomic, copy) NSString *fpsHint;
@property (nonatomic, assign) CGFloat shownQualityHeight;
@property (nonatomic, strong) VGScrubber *scrubber;
@property (nonatomic, strong) UILabel *elapsedLabel, *durationLabel, *titleLabel;
@property (nonatomic, strong) UIView *toastView;
@property (nonatomic, strong) UIView *miniBar;          // thin progress line along the bottom, only while the controls are hidden
@property (nonatomic, strong) VGGradientView *miniFill;
@property (nonatomic) double miniProgress;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, strong) VGSubtitleEngine *subs;          // auto English subtitles, when switched on
@property (nonatomic, strong) UIView *subtitleBox;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) NSLayoutConstraint *subtitleBottom;
@property (nonatomic, copy) NSString *shownSubtitle;
@property (nonatomic) BOOL tracksLoaded;
@property (nonatomic, strong) AVPictureInPictureController *pip;
@property (nonatomic, strong) VGPlayerGestures *gestures;
@property (nonatomic, strong) NSMutableArray *remoteTokens;
@property (nonatomic) BOOL wantPlay;
@property (nonatomic, strong) UIButton *prevTrackButton, *nextTrackButton, *shuffleButton, *repeatButton;
@property (nonatomic, strong) UIView *audioArtView;
@property (nonatomic, strong) VGBannerView *bannerView;
@property (nonatomic, strong) UIButton *videoToggleButton;
@property (nonatomic, strong) NSLayoutConstraint *midCenterY;
@property (nonatomic, strong) UIView *topGroup, *bottomGroup;   // slide away when the controls hide
@property (nonatomic, strong) UIStackView *buttonRow;
@property (nonatomic, strong) UIView *tracksHolder;
@property (nonatomic, strong) UIButton *rowTracks;
@property (nonatomic, strong) UIView *rowSpacer;

@property (nonatomic) BOOL controlsVisible;
@property (nonatomic) NSInteger hideToken;
@property (nonatomic) NSTimeInterval holdUntil;

@property (nonatomic) BOOL scrubbing;
@property (nonatomic) NSInteger shownPlaying;   // 0 not drawn yet, 1 pause icon, 2 play icon
@property (nonatomic) BOOL resumeAfterScrub;
@property (nonatomic) BOOL seeking;
@property (nonatomic) CMTime chaseTime;
@end

@implementation VGPlayerViewController

@synthesize speed = _speed;
@synthesize positionText = _positionText;
@synthesize videoOff = _videoOff;
- (double)speed { return _speed > 0 ? _speed : 1; }

+ (NSString *)positionsKey { return @"vgPlaybackPositions"; }

+ (BOOL)miniProgressEnabled {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    return [d objectForKey:kMiniBarKey] ? [d boolForKey:kMiniBarKey] : YES;
}
+ (void)setMiniProgressEnabled:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:kMiniBarKey]; }

+ (instancetype)playerFor:(VGItem *)item {
    VGPlayerViewController *p = [VGPlayerViewController new];
    p.key = item.fileName;
    p.titleText = item.title.length ? item.title : item.fileName;
    p.audioOnly = item.audio;
    p.artistText = item.artist;
    p.albumText = item.album;
    p.artwork = item.thumbnailImage;
    p.fileURL = item.fileURL;
    p.fpsHint = FPSFromRes(item.res);
    p.keptPlayer = [AVPlayer playerWithURL:item.fileURL];
    p.controlsVisible = YES;
    p.chaseTime = kCMTimeZero;
    p.modalPresentationStyle = UIModalPresentationFullScreen;
    p.modalPresentationCapturesStatusBarAppearance = YES;
    gPreparing = YES;   // lets the screen turn sideways as soon as the player appears
    return p;
}

+ (void)prepareStream:(NSDictionary *)info completion:(void (^)(AVPlayerItem *, NSString *))completion {
    NSArray *list = [info[@"items"] isKindOfClass:NSArray.class] ? info[@"items"] : @[];
    NSMutableArray<AVURLAsset *> *assets = [NSMutableArray array];
    for (NSDictionary *e in list) {
        NSURL *u = [e[@"url"] isKindOfClass:NSString.class] ? [NSURL URLWithString:e[@"url"]] : nil;
        if (!u) continue;
        NSDictionary *h = [e[@"headers"] isKindOfClass:NSDictionary.class] ? e[@"headers"] : @{};
        NSDictionary *opts = h.count ? @{@"AVURLAssetHTTPHeaderFieldsKey": h} : nil;
        [assets addObject:[AVURLAsset URLAssetWithURL:u options:opts]];
    }
    if (!assets.count) { completion(nil, @"This link can't be streamed. Try Download instead."); return; }
    if (assets.count == 1) { completion([AVPlayerItem playerItemWithAsset:assets[0]], nil); return; }
    // Picture and sound come separately: join them without downloading.
    AVURLAsset *va = assets[0], *aa = assets[1];
    dispatch_group_t g = dispatch_group_create();
    for (AVURLAsset *a in @[va, aa]) {
        dispatch_group_enter(g);
        [a loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration"] completionHandler:^{ dispatch_group_leave(g); }];
    }
    dispatch_group_notify(g, dispatch_get_main_queue(), ^{
        AVAssetTrack *vt = [va tracksWithMediaType:AVMediaTypeVideo].firstObject;
        AVAssetTrack *at = [aa tracksWithMediaType:AVMediaTypeAudio].firstObject;
        if (!vt) { completion(nil, @"Couldn't open the stream. Try Download instead."); return; }
        AVMutableComposition *comp = [AVMutableComposition composition];
        CMTime dur = va.duration;
        if (at && CMTIME_IS_NUMERIC(aa.duration) && CMTimeCompare(aa.duration, dur) < 0) dur = aa.duration;
        CMTimeRange range = CMTimeRangeMake(kCMTimeZero, dur);
        AVMutableCompositionTrack *ct = [comp addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        NSError *err = nil;
        [ct insertTimeRange:range ofTrack:vt atTime:kCMTimeZero error:&err];
        ct.preferredTransform = vt.preferredTransform;
        comp.naturalSize = vt.naturalSize;   // without this the player reports no picture size for a joined stream
        if (at) {
            AVMutableCompositionTrack *cat = [comp addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
            [cat insertTimeRange:range ofTrack:at atTime:kCMTimeZero error:&err];
        }
        if (err) { completion(nil, @"Couldn't open the stream. Try Download instead."); return; }
        completion([AVPlayerItem playerItemWithAsset:comp], nil);
    });
}

+ (instancetype)playerForStreamItem:(AVPlayerItem *)item video:(VGVideo *)video option:(VGOption *)option audio:(BOOL)audio {
    VGPlayerViewController *p = [VGPlayerViewController new];
    p.key = nil;
    p.titleText = video.title.length ? video.title : @"Video";
    p.audioOnly = audio;
    p.streamVideo = video;
    p.streamOption = option;
    p.fpsHint = FPSFromRes(option.res);
    p.keptPlayer = [AVPlayer playerWithPlayerItem:item];
    p.controlsVisible = YES;
    p.chaseTime = kCMTimeZero;
    p.modalPresentationStyle = UIModalPresentationFullScreen;
    p.modalPresentationCapturesStatusBarAppearance = YES;
    gPreparing = YES;
    return p;
}

#pragma mark Screen

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}
- (BOOL)shouldAutorotate { return YES; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (BOOL)prefersStatusBarHidden { return !self.controlsVisible; }
- (BOOL)prefersHomeIndicatorAutoHidden { return !self.controlsVisible; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    self.sizeIndex = MIN(MAX([d integerForKey:kAspectKey], 0), (NSInteger)Sizes().count - 1);

    self.videoView = [VGVideoView new];
    self.videoView.backgroundColor = UIColor.blackColor;
    self.videoView.playerLayer.player = self.keptPlayer;
    [self.view addSubview:self.videoView];
    self.bannerView = [[VGBannerView alloc] initWithFrame:self.view.bounds];
    self.bannerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.bannerView.hidden = YES;
    [self.view addSubview:self.bannerView];
    if (self.playlistMode && [NSUserDefaults.standardUserDefaults boolForKey:@"vgPlaylistVideoOff"]) _videoOff = YES;
    if (self.audioOnly) [self buildAudioArt];

    [self buildSubtitleBox];
    [self buildControls];
    [self buildMiniBar];   // last, so it stays on top of the buttons and their shading
    [self rebuildMenus];
    if (self.videoOff) [self applyVideoOff];
    if (self.playlistMode) {   // speed sticks from one playlist to the next
        double sp = [NSUserDefaults.standardUserDefaults doubleForKey:@"vgPlaylistSpeed"];
        if (sp > 0 && sp != 1) [self setSpeed:sp];
    }

    self.gestures = [[VGPlayerGestures alloc] initWithHost:self];
    [self.gestures attach];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];

    if (!self.audioOnly && AVPictureInPictureController.isPictureInPictureSupported) {
        self.pip = [[AVPictureInPictureController alloc] initWithPlayerLayer:self.videoView.playerLayer];
        self.pip.delegate = self;
        self.pip.canStartPictureInPictureAutomaticallyFromInline = YES;
    }
    self.pipButton.hidden = self.pip == nil;
    [self loadMediaOptions];
    [self buildMediaMenu];
    [self tick];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.onScreenCounted) { self.onScreenCounted = YES; gOnScreen++; }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    gPreparing = NO;
    [self scheduleHide];
}

- (NSInteger)activeSize {
    BOOL landscape = self.view.bounds.size.width > self.view.bounds.size.height;
    return landscape ? self.sizeIndex : self.portraitIndex;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    // Portrait always goes back to the default size; landscape brings back the one the viewer chose.
    if (size.height >= size.width) self.portraitIndex = 0;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> c) {
        [self layoutVideoAnimated:NO];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> c) {
        [self layoutVideoAnimated:NO];
        [self rebuildMenus];
        [self scheduleHide];   // turned sideways: the controls hide after a moment (upright they stay)
    }];
}

/// Portrait and landscape need different spacing: portrait with a playlist has eight buttons to fit across, and
/// the play buttons drop below the VidGrab logo when the video is off. Landscape keeps the original layout.
- (void)updateControlLayout {
    if (!self.buttonRow) return;
    BOOL portrait = self.view.bounds.size.height > self.view.bounds.size.width;
    BOOL tight = portrait && self.playlistMode;
    self.tracksHolder.hidden = !(self.playlistMode && portrait);
    self.rowTracks.hidden = !(self.playlistMode && !portrait);
    CGFloat d = tight ? 36 : 40;
    self.rowSpacer.hidden = tight;
    self.buttonRow.distribution = tight ? UIStackViewDistributionEqualSpacing : UIStackViewDistributionFill;
    self.buttonRow.spacing = tight ? 4 : 12;
    for (UIButton *b in @[self.speedButton, self.sizeButton, self.rotateButton, self.videoToggleButton, self.shuffleButton, self.repeatButton, self.captionsButton, self.saveButton]) {
        b.layer.cornerRadius = d / 2;
        for (NSLayoutConstraint *c in b.constraints) {
            if ((c.firstAttribute == NSLayoutAttributeHeight || (c.firstAttribute == NSLayoutAttributeWidth && c.relation == NSLayoutRelationEqual)) && c.secondItem == nil) c.constant = d;
        }
    }
    self.speedButton.contentEdgeInsets = UIEdgeInsetsMake(0, tight ? 12 : 16, 0, tight ? 12 : 16);
    for (NSLayoutConstraint *c in self.speedButton.constraints) if (c.firstAttribute == NSLayoutAttributeWidth && c.relation == NSLayoutRelationGreaterThanOrEqual) c.constant = tight ? 46 : 56;
    BOOL low = self.audioOnly || (self.playlistMode && portrait);   // same spot with the video on or off; the picture plays above them
    CGFloat want = low ? 150 : 0;
    UIView *mid = (UIView *)self.midCenterY.firstItem, *host = mid.superview;
    if (self.playlistMode && portrait && !self.tracksHolder.hidden && host && self.tracksHolder.superview && CGRectGetHeight(self.tracksHolder.frame) > 1) {
        // Sit just above the Tracks button, as far from the picture as possible.
        CGFloat top = [self.tracksHolder.superview convertRect:self.tracksHolder.frame toView:host].origin.y;
        CGFloat half = MAX(CGRectGetHeight(mid.bounds), 72) / 2;
        want = MAX(150, top - 42 - half - host.bounds.size.height / 2);
    }
    if (fabs(self.midCenterY.constant - want) > 0.5) self.midCenterY.constant = want;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateControlLayout];
    if (!self.controlsVisible && [self controlsPinned]) [self setControlsVisible:YES animated:NO];
    [self layoutVideoAnimated:NO];
    CGRect b = self.view.bounds;
    self.miniBar.frame = CGRectMake(0, b.size.height - 3, b.size.width, 3);
    [self applyMiniFill];   // from the saved fraction, not recalculated
}

// The same coral gradient as the brightness and volume bars. It shows only while the buttons are hidden
// (when switched on in Settings), so you can still see how much is left.
- (void)buildMiniBar {
    self.miniBar = [UIView new];
    self.miniBar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    self.miniBar.userInteractionEnabled = NO;
    self.miniBar.alpha = 0;
    self.miniFill = [VGGradientView new];
    self.miniFill.gradient.colors = @[(id)VGAccent.CGColor, (id)VGAccent2.CGColor];
    self.miniFill.gradient.startPoint = CGPointMake(0, 0.5);
    self.miniFill.gradient.endPoint = CGPointMake(1, 0.5);
    [self.miniBar addSubview:self.miniFill];
    [self.view addSubview:self.miniBar];
    [self applyMiniBarAnimated:NO];
}

// Where the video is, in seconds. Only moves when it has moved at least half a point, and never animates.
- (void)updateMiniBar:(double)seconds {
    double dur = [self duration];
    if (dur <= 0) return;   // length not known right now: leave the line where it is
    self.miniProgress = MIN(1, MAX(0, seconds / dur));
    CGSize s = self.miniBar.bounds.size;
    if (fabs(s.width * self.miniProgress - self.miniFill.frame.size.width) < 0.5 && s.height == self.miniFill.frame.size.height) return;
    [self applyMiniFill];
}

// Draws the coloured part from the saved fraction (0 to 1).
- (void)applyMiniFill {
    CGSize s = self.miniBar.bounds.size;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.miniFill.frame = CGRectMake(0, 0, s.width * self.miniProgress, s.height);
    [CATransaction commit];
}

// The line shows only while the buttons are hidden, so you never see two progress bars at once.
// It goes away quickly when the buttons come back, and returns softly once they have faded out.
- (void)applyMiniBarAnimated:(BOOL)animated {
    BOOL show = VGPlayerViewController.miniProgressEnabled && !self.controlsVisible;
    if (!animated) { self.miniBar.alpha = show ? 1 : 0; return; }
    [UIView animateWithDuration:show ? 0.5 : 0.1 delay:show ? 0.3 : 0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.miniBar.alpha = show ? 1 : 0; } completion:nil];
}

- (void)layoutVideoAnimated:(BOOL)animated {
    NSDictionary *m = Sizes()[[self activeSize]];
    CGRect b = self.view.bounds, f = b;
    double ratio = [m[@"ratio"] doubleValue];
    if (ratio > 0 && b.size.width > 0 && b.size.height > 0) {
        if (b.size.width / b.size.height > ratio) f = CGRectMake((b.size.width - b.size.height * ratio) / 2, 0, b.size.height * ratio, b.size.height);
        else f = CGRectMake(0, (b.size.height - b.size.width / ratio) / 2, b.size.width, b.size.width / ratio);
    }
    self.videoView.playerLayer.videoGravity = m[@"gravity"];
    // A playlist held upright keeps its buttons low and in the same place with the video on or off; the picture
    // moves up a little so it has room above them.
    if (self.playlistMode && b.size.height > b.size.width && f.size.height < b.size.height - 160) f.origin.y -= 50;
    if (animated) [UIView animateWithDuration:0.25 animations:^{ self.videoView.frame = f; }];
    else self.videoView.frame = f;
}

// For music and other audio: a coral cover in the middle instead of a picture.
- (void)buildAudioArt {
    UIView *art;
    if (self.artwork) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:self.artwork];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        art = iv;
    } else {
        VGGradientView *g = [VGGradientView new];
        g.gradient.colors = @[(id)VGAccent.CGColor, (id)VGAccent2.CGColor];
        g.gradient.startPoint = CGPointMake(0, 0);
        g.gradient.endPoint = CGPointMake(1, 1);
        UIImageView *note = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"music.note"]];
        note.tintColor = UIColor.whiteColor;
        note.contentMode = UIViewContentModeScaleAspectFit;
        note.translatesAutoresizingMaskIntoConstraints = NO;
        [g addSubview:note];
        [NSLayoutConstraint activateConstraints:@[
            [note.centerXAnchor constraintEqualToAnchor:g.centerXAnchor], [note.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
            [note.widthAnchor constraintEqualToConstant:84], [note.heightAnchor constraintEqualToConstant:84]]];
        art = g;
    }
    art.layer.cornerRadius = 28;
    art.layer.cornerCurve = kCACornerCurveContinuous;
    art.clipsToBounds = YES;
    art.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:art];
    self.audioArtView = art;
    [NSLayoutConstraint activateConstraints:@[
        [art.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [art.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
        [art.widthAnchor constraintEqualToConstant:200], [art.heightAnchor constraintEqualToConstant:200]]];
}

#pragma mark Controls

- (void)buildControls {
    UIView *c = [UIView new];
    c.frame = self.view.bounds;
    c.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.controls = c;
    [self.view addSubview:c];
    UILayoutGuide *safe = c.safeAreaLayoutGuide;

    // Soft shading so white buttons and text stay readable on bright video.
    VGGradientView *top = [VGGradientView new], *bottom = [VGGradientView new];
    top.gradient.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.62].CGColor, (id)UIColor.clearColor.CGColor];
    bottom.gradient.colors = @[(id)UIColor.clearColor.CGColor, (id)[UIColor colorWithWhite:0 alpha:0.78].CGColor];
    for (UIView *s in @[top, bottom]) { s.userInteractionEnabled = NO; s.translatesAutoresizingMaskIntoConstraints = NO; [c addSubview:s]; }
    [NSLayoutConstraint activateConstraints:@[
        [top.topAnchor constraintEqualToAnchor:c.topAnchor], [top.leadingAnchor constraintEqualToAnchor:c.leadingAnchor],
        [top.trailingAnchor constraintEqualToAnchor:c.trailingAnchor], [top.heightAnchor constraintEqualToConstant:140],
        [bottom.bottomAnchor constraintEqualToAnchor:c.bottomAnchor], [bottom.leadingAnchor constraintEqualToAnchor:c.leadingAnchor],
        [bottom.trailingAnchor constraintEqualToAnchor:c.trailingAnchor], [bottom.heightAnchor constraintEqualToConstant:230]]];

    // Top: close on the left, picture-in-picture and AirPlay on the right.
    self.closeButton = RoundButton(@"chevron.down", 44, 18);
    [self.closeButton addTarget:self action:@selector(minimize) forControlEvents:UIControlEventTouchUpInside];
    self.pipButton = RoundButton(@"pip.enter", 44, 18);
    [self.pipButton addTarget:self action:@selector(togglePiP) forControlEvents:UIControlEventTouchUpInside];
    self.routeButton = [[AVRoutePickerView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    self.routeButton.tintColor = UIColor.whiteColor;
    self.routeButton.activeTintColor = VGAccent;
    self.routeButton.prioritizesVideoDevices = !self.audioOnly;
    self.routeButton.backgroundColor = [VGSurface colorWithAlphaComponent:0.78];
    self.routeButton.layer.cornerRadius = 22;
    self.routeButton.layer.borderWidth = 1;
    self.routeButton.layer.borderColor = VGStroke.CGColor;
    self.routeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.routeButton.widthAnchor constraintEqualToConstant:44].active = YES;
    [self.routeButton.heightAnchor constraintEqualToConstant:44].active = YES;
    self.qualityLabel = [UIButton buttonWithType:UIButtonTypeCustom];
    self.qualityLabel.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [self.qualityLabel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.qualityLabel.tintColor = UIColor.whiteColor;
    self.qualityLabel.backgroundColor = [VGSurface colorWithAlphaComponent:0.78];
    self.qualityLabel.layer.cornerRadius = 15;
    self.qualityLabel.layer.borderWidth = 1;
    self.qualityLabel.layer.borderColor = VGStroke.CGColor;
    self.qualityLabel.clipsToBounds = YES;
    self.qualityLabel.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    self.qualityLabel.userInteractionEnabled = NO;   // only shows what is playing
    self.qualityLabel.hidden = YES;
    self.qualityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.qualityLabel.heightAnchor constraintEqualToConstant:30].active = YES;
    [self.qualityLabel.widthAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    self.heatPill = [UIButton buttonWithType:UIButtonTypeCustom];
    self.heatPill.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    self.heatPill.backgroundColor = [VGSurface colorWithAlphaComponent:0.78];
    self.heatPill.layer.cornerRadius = 15;
    self.heatPill.layer.borderWidth = 1;
    self.heatPill.layer.borderColor = VGStroke.CGColor;
    self.heatPill.clipsToBounds = YES;
    self.heatPill.userInteractionEnabled = NO;
    self.heatPill.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    self.heatPill.imageEdgeInsets = UIEdgeInsetsMake(0, -3, 0, 3);
    self.heatPill.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heatPill.heightAnchor constraintEqualToConstant:30].active = YES;
    [self refreshHeat];
    UIStackView *right = [[UIStackView alloc] initWithArrangedSubviews:@[self.heatPill, self.qualityLabel, self.pipButton, self.routeButton]];
    right.alignment = UIStackViewAlignmentCenter;
    right.spacing = 10;
    right.translatesAutoresizingMaskIntoConstraints = NO;
    self.topGroup = right;
    [c addSubview:self.closeButton];
    [c addSubview:right];
    [NSLayoutConstraint activateConstraints:@[
        [self.closeButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [right.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [right.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10]]];

    // Middle: back 10, play or pause, forward 10.
    self.backButton = RoundButton(@"gobackward.10", 54, 24);
    self.forwardButton = RoundButton(@"goforward.10", 54, 24);
    self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.playButton.backgroundColor = VGAccent;
    self.playButton.tintColor = UIColor.whiteColor;
    self.playButton.layer.cornerRadius = 36;
    self.playButton.layer.shadowColor = VGAccent.CGColor;
    self.playButton.layer.shadowOpacity = 0.45;
    self.playButton.layer.shadowRadius = 14;
    self.playButton.layer.shadowOffset = CGSizeMake(0, 4);
    [self.playButton.widthAnchor constraintEqualToConstant:72].active = YES;
    [self.playButton.heightAnchor constraintEqualToConstant:72].active = YES;
    SetSymbol(self.playButton, @"pause.fill", 30);
    [self.playButton addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
    [self.backButton addTarget:self action:@selector(skipBack) forControlEvents:UIControlEventTouchUpInside];
    [self.forwardButton addTarget:self action:@selector(skipForward) forControlEvents:UIControlEventTouchUpInside];
    self.prevTrackButton = RoundButton(@"backward.end.fill", 44, 20);
    self.nextTrackButton = RoundButton(@"forward.end.fill", 44, 20);
    self.prevTrackButton.accessibilityLabel = @"Previous track";
    self.nextTrackButton.accessibilityLabel = @"Next track";
    [self.prevTrackButton addTarget:self action:@selector(previousTrack) forControlEvents:UIControlEventTouchUpInside];
    [self.nextTrackButton addTarget:self action:@selector(nextTrack) forControlEvents:UIControlEventTouchUpInside];
    self.prevTrackButton.hidden = self.nextTrackButton.hidden = !self.playlistMode;
    UIStackView *mid = [[UIStackView alloc] initWithArrangedSubviews:@[self.prevTrackButton, self.backButton, self.playButton, self.forwardButton, self.nextTrackButton]];
    mid.spacing = 16;
    mid.alignment = UIStackViewAlignmentCenter;
    mid.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:mid];
    [NSLayoutConstraint activateConstraints:@[
        [mid.centerXAnchor constraintEqualToAnchor:c.centerXAnchor],
        (self.midCenterY = [mid.centerYAnchor constraintEqualToAnchor:c.centerYAnchor constant:self.audioOnly ? 150 : 0])]];

    // Bottom: title, progress bar with times, then the playback buttons.
    self.titleLabel = [UILabel new];
    self.titleLabel.text = self.positionText.length ? [NSString stringWithFormat:@"%@  ·  %@", self.positionText, self.titleText] : self.titleText;
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.font = VGFont(16, UIFontWeightSemibold);
    self.titleLabel.numberOfLines = 1;

    self.elapsedLabel = TimeLabel(NSTextAlignmentLeft);
    self.durationLabel = TimeLabel(NSTextAlignmentRight);
    self.scrubber = [VGScrubber new];
    self.scrubber.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrubber.heightAnchor constraintEqualToConstant:36].active = YES;
    [self.scrubber setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    __weak typeof(self) ws = self;
    self.scrubber.onBegin = ^{ [ws scrubBegan]; };
    self.scrubber.onMove = ^(double p) {
        VGPlayerViewController *me = ws;
        double s = p * [me duration];
        me.elapsedLabel.text = PClock(s);
        [me scrubToSeconds:s];
    };
    self.scrubber.onEnd = ^{ [ws scrubEnded]; };
    UIStackView *scrubRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.elapsedLabel, self.scrubber, self.durationLabel]];
    scrubRow.spacing = 4;
    scrubRow.alignment = UIStackViewAlignmentCenter;

    self.speedButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.speedButton.titleLabel.font = VGRounded(15, UIFontWeightBold);
    [self.speedButton setTitle:@"1×" forState:UIControlStateNormal];
    self.speedButton.backgroundColor = [VGSurface colorWithAlphaComponent:0.78];
    self.speedButton.layer.cornerRadius = 18;
    self.speedButton.layer.borderWidth = 1;
    self.speedButton.layer.borderColor = VGStroke.CGColor;
    self.speedButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    self.speedButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.speedButton.heightAnchor constraintEqualToConstant:36].active = YES;
    [self.speedButton.widthAnchor constraintGreaterThanOrEqualToConstant:46].active = YES;
    self.sizeButton = RoundButton(@"arrow.up.left.and.arrow.down.right", 36, 16);
    self.rotateButton = RoundButton(@"rotate.right", 36, 16);
    [self.rotateButton addTarget:self action:@selector(rotate) forControlEvents:UIControlEventTouchUpInside];
    self.captionsButton = RoundButton(@"captions.bubble", 36, 16);
    self.captionsButton.hidden = YES;
    self.saveButton = RoundButton(@"arrow.down.to.line", 36, 16);
    self.saveButton.hidden = self.streamVideo == nil;
    self.saveButton.accessibilityLabel = @"Download this video";
    [self.saveButton addTarget:self action:@selector(saveStream) forControlEvents:UIControlEventTouchUpInside];
    for (UIButton *b in @[self.speedButton, self.sizeButton, self.captionsButton])
        [b addTarget:self action:@selector(menuOpened) forControlEvents:UIControlEventMenuActionTriggered];
    if (self.audioOnly) { self.sizeButton.hidden = YES; self.rotateButton.hidden = YES; }
    self.shuffleButton = RoundButton(@"shuffle", 36, 16);
    self.repeatButton = RoundButton(@"repeat", 36, 16);
    [self.shuffleButton addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.repeatButton addTarget:self action:@selector(repeatTapped) forControlEvents:UIControlEventTouchUpInside];
    self.videoToggleButton = RoundButton(@"video.fill", 36, 16);
    [self.videoToggleButton addTarget:self action:@selector(toggleVideo) forControlEvents:UIControlEventTouchUpInside];
    self.videoToggleButton.accessibilityLabel = @"Turn video on or off";
    self.shuffleButton.hidden = self.repeatButton.hidden = self.videoToggleButton.hidden = !self.playlistMode;
    [self styleModeButtons];
    UIView *spacer = [UIView new];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    // With the playlist buttons there are eight, so they share the width evenly instead of being squeezed.
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.speedButton, self.sizeButton, self.rotateButton, self.videoToggleButton, self.shuffleButton, self.repeatButton, self.captionsButton, self.saveButton, spacer]];
    buttons.spacing = 12;
    self.buttonRow = buttons; self.rowSpacer = spacer;
    buttons.alignment = UIStackViewAlignmentCenter;

    // Playlist mode: a pill with an up arrow that opens the list of tracks.
    UIButtonConfiguration *tc = [UIButtonConfiguration plainButtonConfiguration];
    tc.title = @"Tracks";
    tc.image = [UIImage systemImageNamed:@"chevron.up" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold]];
    tc.imagePlacement = NSDirectionalRectEdgeLeading;
    tc.imagePadding = 6;
    tc.baseForegroundColor = UIColor.whiteColor;
    tc.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    tc.background.backgroundColor = [VGSurface colorWithAlphaComponent:0.78];
    tc.background.strokeColor = VGStroke; tc.background.strokeWidth = 1;
    tc.contentInsets = NSDirectionalEdgeInsetsMake(6, 16, 6, 16);
    tc.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *a) {
        NSMutableDictionary *d = [a mutableCopy]; d[NSFontAttributeName] = VGRounded(14, UIFontWeightBold); return d; };
    UIButton *tracksB = [UIButton buttonWithConfiguration:tc primaryAction:nil];
    tracksB.translatesAutoresizingMaskIntoConstraints = NO;
    tracksB.accessibilityLabel = @"Show the tracks in this playlist";
    [tracksB addTarget:self action:@selector(showTracks) forControlEvents:UIControlEventTouchUpInside];
    UIView *tracksHolder = [UIView new];
    [tracksHolder addSubview:tracksB];
    [NSLayoutConstraint activateConstraints:@[
        [tracksB.centerXAnchor constraintEqualToAnchor:tracksHolder.centerXAnchor], [tracksB.topAnchor constraintEqualToAnchor:tracksHolder.topAnchor],
        [tracksB.bottomAnchor constraintEqualToAnchor:tracksHolder.bottomAnchor constant:-2], [tracksHolder.heightAnchor constraintEqualToConstant:34]]];
    tracksHolder.hidden = !self.playlistMode;
    self.tracksHolder = tracksHolder;
    // Landscape: the same button sits in the bottom row, right beside the download button.
    UIButton *rowTracks = [UIButton buttonWithConfiguration:tc primaryAction:nil];
    rowTracks.translatesAutoresizingMaskIntoConstraints = NO;
    [rowTracks.heightAnchor constraintEqualToConstant:40].active = YES;
    rowTracks.accessibilityLabel = @"Show the tracks in this playlist";
    [rowTracks addTarget:self action:@selector(showTracks) forControlEvents:UIControlEventTouchUpInside];
    [buttons insertArrangedSubview:rowTracks atIndex:[buttons.arrangedSubviews indexOfObject:self.saveButton] + 1];
    self.rowTracks = rowTracks;
    UIStackView *bottomStack = [[UIStackView alloc] initWithArrangedSubviews:@[tracksHolder, self.titleLabel, scrubRow, buttons]];
    bottomStack.axis = UILayoutConstraintAxisVertical;
    bottomStack.spacing = 6;
    bottomStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomGroup = bottomStack;
    [c addSubview:bottomStack];
    [NSLayoutConstraint activateConstraints:@[
        [bottomStack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:22],
        [bottomStack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-22],
        [bottomStack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10]]];
}

// Speed and screen size are menus; they're rebuilt so the tick shows what's selected now.
- (void)rebuildMenus {
    __weak typeof(self) ws = self;
    NSMutableArray *speeds = [NSMutableArray array];
    NSArray *rates = @[@0.5, @0.75, @1.0, @1.25, @1.5, @2.0];
    NSArray *names = @[@"0.5×", @"0.75×", @"Normal", @"1.25×", @"1.5×", @"2×"];
    for (NSUInteger i = 0; i < rates.count; i++) {
        double r = [rates[i] doubleValue];
        UIAction *a = [UIAction actionWithTitle:names[i] image:nil identifier:nil handler:^(UIAction *x) { [ws setSpeed:r]; }];
        a.state = fabs(r - self.speed) < 0.01 ? UIMenuElementStateOn : UIMenuElementStateOff;
        [speeds addObject:a];
    }
    self.speedButton.menu = [UIMenu menuWithTitle:@"Playback speed" children:speeds];
    self.speedButton.showsMenuAsPrimaryAction = YES;

    NSMutableArray *sizes = [NSMutableArray array];
    NSArray *all = Sizes();
    for (NSUInteger i = 0; i < all.count; i++) {
        NSDictionary *m = all[i];
        UIAction *a = [UIAction actionWithTitle:m[@"name"] image:[UIImage systemImageNamed:m[@"icon"]] identifier:nil handler:^(UIAction *x) { [ws chooseSize:(NSInteger)i]; }];
        a.state = (NSInteger)i == [self activeSize] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [sizes addObject:a];
    }
    self.sizeButton.menu = [UIMenu menuWithTitle:@"Screen size" children:sizes];
    self.sizeButton.showsMenuAsPrimaryAction = YES;
    SetSymbol(self.sizeButton, all[[self activeSize]][@"icon"], 16);
}

- (void)setSpeed:(double)speed {
    _speed = speed;
    if (self.playlistMode) [NSUserDefaults.standardUserDefaults setDouble:speed forKey:@"vgPlaylistSpeed"];
    if (self.keptPlayer.timeControlStatus != AVPlayerTimeControlStatusPaused) self.keptPlayer.rate = (float)speed;
    NSString *t = speed == 1.0 ? @"1×" : [NSString stringWithFormat:@"%g×", speed];
    [self.speedButton setTitle:t forState:UIControlStateNormal];
    self.speedButton.tintColor = UIColor.whiteColor;
    [self.speedButton setTitleColor:speed == 1.0 ? UIColor.whiteColor : VGAccent forState:UIControlStateNormal];
    [self rebuildMenus];
    [self updateNowPlaying];
    [self showControls];
}

- (void)chooseSize:(NSInteger)i {
    if (self.view.bounds.size.width > self.view.bounds.size.height) {
        self.sizeIndex = i;
        [NSUserDefaults.standardUserDefaults setInteger:i forKey:kAspectKey];
    } else {
        self.portraitIndex = i;
    }
    [self layoutVideoAnimated:YES];
    [self rebuildMenus];
    [self toast:Sizes()[i][@"name"] icon:Sizes()[i][@"icon"]];
    [self showControls];
}

- (void)menuOpened { [self holdControlsFor:6]; }

#pragma mark Showing and hiding the controls

- (void)tapped { [self setControlsVisible:!self.controlsVisible animated:YES]; if (self.controlsVisible) [self scheduleHide]; }

/// A streamed playlist held upright keeps its buttons on screen (like a music player), so they never hide.
- (BOOL)controlsPinned {
    return self.playlistMode && self.view.bounds.size.height > self.view.bounds.size.width;
}

- (void)setControlsVisible:(BOOL)visible animated:(BOOL)animated {
    if (!visible && [self controlsPinned]) visible = YES;
    self.controlsVisible = visible;
    if (visible) [self tick];
    self.controls.userInteractionEnabled = visible;
    // Hiding: the top buttons slide up and fade, the bottom ones slide down and fade. Showing runs the same in reverse.
    CGAffineTransform up = CGAffineTransformMakeTranslation(0, -36), down = CGAffineTransformMakeTranslation(0, 48);
    [UIView animateWithDuration:animated ? 0.3 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.controls.alpha = visible ? 1 : 0;
        self.closeButton.transform = visible ? CGAffineTransformIdentity : up;
        self.topGroup.transform = visible ? CGAffineTransformIdentity : up;
        self.bottomGroup.transform = visible ? CGAffineTransformIdentity : down;
        self.subtitleBottom.constant = visible ? -150 : -26;
        [self.view layoutIfNeeded];
        [self setNeedsStatusBarAppearanceUpdate];
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    } completion:nil];
    [self applyMiniBarAnimated:animated];
}

- (void)showControls {
    if (!self.controlsVisible) [self setControlsVisible:YES animated:YES];
    [self scheduleHide];
}

- (void)holdControlsFor:(NSTimeInterval)seconds {
    self.holdUntil = [NSDate timeIntervalSinceReferenceDate] + seconds;
    [self scheduleHide];
}

- (void)scheduleHide {
    NSInteger token = ++self.hideToken;
    BOOL portrait = self.view.bounds.size.height > self.view.bounds.size.width;
    if ((self.audioOnly && portrait) || self.scrubbing || [self controlsPinned] || self.keptPlayer.timeControlStatus == AVPlayerTimeControlStatusPaused) return;   // landscape always hides after a moment
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        VGPlayerViewController *me = ws;
        if (!me || me.hideToken != token) return;
        if ([NSDate timeIntervalSinceReferenceDate] < me.holdUntil) { [me scheduleHide]; return; }
        if (me.scrubbing || me.keptPlayer.timeControlStatus == AVPlayerTimeControlStatusPaused) return;
        [me setControlsVisible:NO animated:YES];
    });
}

- (void)toast:(NSString *)text icon:(NSString *)icon {
    [self.toastView removeFromSuperview];
    UIVisualEffectView *t = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    t.layer.cornerRadius = 21;
    t.clipsToBounds = YES;
    t.layer.borderWidth = 1;
    t.layer.borderColor = VGStroke.CGColor;
    t.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *tint = [UIView new];
    tint.backgroundColor = [VGSurface colorWithAlphaComponent:0.62];
    tint.translatesAutoresizingMaskIntoConstraints = NO;
    [t.contentView addSubview:tint];
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    iv.tintColor = VGAccent;
    UILabel *l = [UILabel new];
    l.text = text;
    l.textColor = UIColor.whiteColor;
    l.font = VGFont(15, UIFontWeightSemibold);
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[iv, l]];
    s.spacing = 8;
    s.alignment = UIStackViewAlignmentCenter;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [t.contentView addSubview:s];
    [self.view addSubview:t];
    [NSLayoutConstraint activateConstraints:@[
        [tint.topAnchor constraintEqualToAnchor:t.contentView.topAnchor], [tint.bottomAnchor constraintEqualToAnchor:t.contentView.bottomAnchor],
        [tint.leadingAnchor constraintEqualToAnchor:t.contentView.leadingAnchor], [tint.trailingAnchor constraintEqualToAnchor:t.contentView.trailingAnchor],
        [s.leadingAnchor constraintEqualToAnchor:t.contentView.leadingAnchor constant:18], [s.trailingAnchor constraintEqualToAnchor:t.contentView.trailingAnchor constant:-18],
        [s.centerYAnchor constraintEqualToAnchor:t.contentView.centerYAnchor],
        [t.heightAnchor constraintEqualToConstant:42],
        [t.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [t.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:72]]];
    self.toastView = t;
    t.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ t.alpha = 1; } completion:^(BOOL f) {
        [UIView animateWithDuration:0.3 delay:1.4 options:0 animations:^{ t.alpha = 0; } completion:^(BOOL f2) { [t removeFromSuperview]; }];
    }];
}

#pragma mark Touches

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    for (UIView *v = touch.view; v && v != g.view; v = v.superview)
        if ([v isKindOfClass:UIControl.class] || [NSStringFromClass(v.class) isEqualToString:@"VGSaveCard"] || [NSStringFromClass(v.class) isEqualToString:@"VGTrackSheet"]) return NO;   // buttons, the save card and the track list handle their own touches
    return YES;
}

#pragma mark Playing

- (double)duration {
    if (self.live && self.live.duration > 0) return self.live.duration;
    double s = CMTimeGetSeconds(self.keptPlayer.currentItem.duration);
    return isfinite(s) && s > 0 ? s : 0;
}

- (double)position {
    double s = CMTimeGetSeconds(self.keptPlayer.currentTime);
    return isfinite(s) ? MAX(0, s) + self.liveOffset : 0;
}

- (BOOL)isPlaying { return self.keptPlayer.timeControlStatus != AVPlayerTimeControlStatusPaused; }

- (void)resume {
    double dur = [self duration];
    if (dur > 0 && [self position] >= dur - 0.3) [self.keptPlayer seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    self.keptPlayer.rate = (float)self.speed;
    [self refreshPlayState];
    [self scheduleHide];
    [self updateNowPlaying];
}

- (void)pausePlayback {
    self.wantPlay = NO;
    [self.keptPlayer pause];
    [self refreshPlayState];
    [self showControls];
    [self updateNowPlaying];
}

- (void)togglePlay { if ([self isPlaying]) [self pausePlayback]; else [self resume]; }

- (void)skip:(double)delta {
    double dur = [self duration];
    double to = MIN(MAX([self position] + delta, 0), dur > 0 ? dur : 0);
    [self.keptPlayer seekToTime:CMTimeMakeWithSeconds(MAX(0, to - self.liveOffset), 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self tickWithPosition:to];
    [self showControls];
    [self updateNowPlaying];
}

- (void)skipBack { [self skip:-10]; }
- (void)skipForward { [self skip:10]; }

- (void)refreshPlayState {
    BOOL playing = [self isPlaying];
    NSInteger state = playing ? 1 : 2;
    if (state == self.shownPlaying) return;
    self.shownPlaying = state;
    SetSymbol(self.playButton, playing ? @"pause.fill" : @"play.fill", 30);
    self.playButton.imageEdgeInsets = playing ? UIEdgeInsetsZero : UIEdgeInsetsMake(0, 3, 0, 0);
}

- (void)tick { if (self.videoOff) [self syncVideoTracks]; [self tickWithPosition:[self position]]; }

/// Shows the real size of the video being played (4K, 2K, 1080p60...). Display only.
- (void)updateQualityLabel {
    if (self.audioOnly) return;
    AVPlayerItem *cur = self.keptPlayer.currentItem;
    CGFloat h = cur.presentationSize.height;
    if (h <= 0 && cur.status == AVPlayerItemStatusReadyToPlay) {
        // Joined streams can report no size; read it from the picture track instead.
        for (AVPlayerItemTrack *t in cur.tracks) {
            if ([t.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) {
                CGSize n = CGSizeApplyAffineTransform(t.assetTrack.naturalSize, t.assetTrack.preferredTransform);
                h = fabs(n.height);
                break;
            }
        }
    }
    if (h <= 0 || h == self.shownQualityHeight) return;
    self.shownQualityHeight = h;
    NSString *t;
    if (h >= 2000) t = @"4K";
    else if (h >= 1300) t = @"2K";
    else t = [NSString stringWithFormat:@"%ldp", (long)h];
    if (h < 2000 && self.fpsHint.length) t = [t stringByAppendingString:self.fpsHint];
    [self.qualityLabel setTitle:t forState:UIControlStateNormal];
    self.qualityLabel.hidden = NO;
    [self reconcileQuality:h];
    [self buildQualityMenu];
}

/// The label always shows what is really playing. If that is not what was asked for, say so and tick the real one.
- (void)reconcileQuality:(CGFloat)h {
    if (!self.streamVideo || self.audioOnly) return;
    VGOption *asked = self.streamOption, *real = nil;
    NSInteger bestGap = 1000000;
    for (VGOption *o in self.streamVideo.options) {
        if (o.audio) continue;
        NSInteger gap = labs(OptHeight(o) - (NSInteger)lround(h));
        if (gap < bestGap) { bestGap = gap; real = o; }
    }
    if (NO && asked && !asked.audio && labs(OptHeight(asked) - (NSInteger)lround(h)) > 60) {
        NSString *msg = [NSString stringWithFormat:@"%@ can not play as a stream on iPhone. Showing %ldp. Download it to get %@", asked.res, (long)lround(h), asked.res];
        [self toast:msg icon:@"info.circle"];
    }
    if (real) { self.streamOption = real; self.fpsHint = FPSFromRes(real.res); }
}

/// Streams only: lets the viewer switch to another quality of the same video.
/// The quality pill only shows what is playing; it is not a button.
- (void)buildQualityMenu {
    self.qualityLabel.menu = nil;
    self.qualityLabel.userInteractionEnabled = NO;
    [self.qualityLabel setImage:nil forState:UIControlStateNormal];
}

- (void)offerDownloadFor:(VGOption *)o {
    for (UIView *v in self.view.subviews) if ([v isKindOfClass:VGSaveCard.class]) return;
    VGSaveCard *card = [[VGSaveCard alloc] initWithVideo:self.streamVideo playing:self.streamOption];
    [card choose:o];
    __weak typeof(self) ws = self;
    card.onPick = ^(VGOption *picked) { [ws startSave:picked]; };
    [card presentIn:self.view];
    [self toast:[NSString stringWithFormat:@"%@ can not play as a stream on iPhone. You can download it", o.res] icon:@"info.circle"];
}

/// 4K and 2K (VP9) cannot be streamed by the iPhone's player. They are prepared on the phone (saved to Downloads), then played from there.
- (void)playConverted:(VGOption *)opt {
    if (self.preparingHigh) { [self toast:@"Still preparing. It will play when ready" icon:@"hourglass"]; return; }
    self.preparingHigh = YES;
    [self toast:[NSString stringWithFormat:@"Preparing %@. It plays when ready, and is saved to Downloads", opt.res] icon:@"arrow.down.circle.fill"];
    __weak typeof(self) ws = self;
    [[VGEngine shared] download:self.streamVideo option:opt progress:^(double fraction, NSString *stage, NSString *detail) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ws.preparingHigh) return;
            [ws.qualityLabel setTitle:[NSString stringWithFormat:@"%@ %d%%", opt.res, (int)round(fraction * 100)] forState:UIControlStateNormal];
        });
    } completion:^(VGItem *item, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL still = ws.preparingHigh;   // NO when the viewer picked another quality meanwhile
            ws.preparingHigh = NO;
            if (!item || !still || !ws.view.window) {
                ws.shownQualityHeight = 0;
                if (!item) [ws toast:@"Couldn't prepare that quality" icon:@"exclamationmark.circle"];
                return;
            }
            AVPlayer *pl = ws.keptPlayer;
            CMTime at = pl.currentTime;
            BOOL playing = pl.timeControlStatus != AVPlayerTimeControlStatusPaused;
            ws.streamOption = opt;
            ws.fpsHint = FPSFromRes(opt.res);
            ws.shownQualityHeight = 0;
            [pl replaceCurrentItemWithPlayerItem:[AVPlayerItem playerItemWithURL:item.fileURL]];
            if (CMTIME_IS_NUMERIC(at) && CMTimeGetSeconds(at) > 0) [pl seekToTime:at];
            if (playing) [pl play];
            [ws buildQualityMenu];
        });
    }];
}

- (NSDictionary *)variantFor:(VGOption *)o {
    id v = self.streamVariants[[NSString stringWithFormat:@"%ld", (long)OptHeight(o)]];
    return [v isKindOfClass:NSDictionary.class] ? v : nil;
}

/// Opens every other quality ahead of time (just the first bytes), so choosing one starts at once.
- (void)warmVariants {
    if (!self.streamVariants.count) return;
    if (!self.warmItems) { self.warmItems = [NSMutableDictionary dictionary]; self.warming = [NSMutableSet set]; }
    __weak typeof(self) ws = self;
    for (NSString *key in self.streamVariants) {
        NSDictionary *v = self.streamVariants[key];
        if (![v isKindOfClass:NSDictionary.class] || self.warmItems[key] || [self.warming containsObject:key]) continue;
        [self.warming addObject:key];
        [VGPlayerViewController prepareStream:v completion:^(AVPlayerItem *item, NSString *err) {
            if (!ws) return;
            [ws.warming removeObject:key];
            if (!item) return;
            ws.warmItems[key] = item;
            [item.asset loadValuesAsynchronouslyForKeys:@[@"playable", @"tracks", @"duration"] completionHandler:nil];
        }];
    }
}

- (void)stopLive {
    self.liveToken++;
    self.livePending = NO;
    [self.live stop];
    self.live = nil;
    self.liveOffset = 0;
}

/// 2K and 4K (VP9): decoded and re-encoded on the phone while playing. Starts from the beginning.
- (void)playLiveOption:(VGOption *)opt {
    double from = [self position];   // 2K carries on from the second the viewer is at
    [self stopLive];
    self.livePending = YES;
    [self.keptPlayer pause];
    NSUInteger tk = self.liveToken;
    self.streamOption = opt;
    self.fpsHint = FPSFromRes(opt.res);
    [self.qualityLabel setTitle:[NSString stringWithFormat:@"%@ …", opt.res] forState:UIControlStateNormal];
    [self toast:[NSString stringWithFormat:@"Getting %@ ready. It starts in a few seconds", opt.res] icon:@"hourglass"];
    __weak typeof(self) ws = self;
    [[VGEngine shared] liveLinkFor:self.streamVideo option:opt completion:^(NSDictionary *info, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ws || ws.liveToken != tk) return;
            NSDictionary *v = info[@"video"];
            if (![v isKindOfClass:NSDictionary.class] || !v[@"url"]) {
                [ws toast:error.length ? error : @"Couldn't get that quality" icon:@"exclamationmark.circle"];
                [ws offerDownloadFor:opt];
                return;
            }
            NSDictionary *a = [info[@"audio"] isKindOfClass:NSDictionary.class] ? info[@"audio"] : nil;
            VGLiveStream *ls = [[VGLiveStream alloc] initWithVideo:v audio:a fps:[v[@"fps"] doubleValue] duration:[info[@"duration"] doubleValue]];
            ls.startAt = from;
            ws.live = ls;
            [ls startWithReady:^(NSURL *playlist) {
                if (ws.liveToken != tk) return;
                AVPlayer *pl = ws.keptPlayer;
                BOOL playing = pl.timeControlStatus != AVPlayerTimeControlStatusPaused;
                ws.livePending = NO;
                ws.liveOffset = from > 1 ? from : 0;
                AVPlayerItem *item = [AVPlayerItem playerItemWithURL:playlist];
                item.preferredForwardBufferDuration = 3;
                ws.shownQualityHeight = 0;
                ws.streamFailed = NO;
                ws.streamMaster = NO;
                [pl replaceCurrentItemWithPlayerItem:item];
                [pl play]; (void)playing;
                [ws buildQualityMenu];
            } failed:^(NSString *err) {
                if (ws.liveToken != tk) return;
                [ws stopLive];
                [ws toast:err.length ? err : @"Couldn't convert that quality" icon:@"exclamationmark.circle"];
                [ws offerDownloadFor:opt];
            }];
        });
    }];
}

- (void)switchToOption:(VGOption *)opt {
    if (opt.convert && ![self variantFor:opt]) {
        [self playLiveOption:opt];
        return;
    }
    [self stopLive];
    self.preparingHigh = NO;
    if ([opt.identifier isEqualToString:self.streamOption.identifier]) return;
    NSInteger want = OptHeight(opt);
    // The tick and the label move at once, so the choice always shows.
    self.streamOption = opt;
    self.fpsHint = FPSFromRes(opt.res);
    [self.qualityLabel setTitle:@"…" forState:UIControlStateNormal];
    [self buildQualityMenu];

    NSDictionary *known = [self.streamVariants[[NSString stringWithFormat:@"%ld", (long)want]] isKindOfClass:NSDictionary.class] ? self.streamVariants[[NSString stringWithFormat:@"%ld", (long)want]] : nil;
    if (known) {
        // Like any video player: load that exact quality and carry on from the same second. Everything needed was worked out when the stream opened.
        NSUInteger tk = ++self.switchToken;
        self.switchPending = YES;
        NSString *key = [NSString stringWithFormat:@"%ld", (long)want];
        AVPlayerItem *ready = self.warmItems[key];
        [self.warmItems removeObjectForKey:key];
        if (ready && ready.status == AVPlayerItemStatusFailed) ready = nil;
        __weak typeof(self) ws = self;
        void (^go)(AVPlayerItem *, NSString *) = ^(AVPlayerItem *item, NSString *err) {
            if (!ws || ws.switchToken != tk) return;
            ws.switchPending = NO;
            if (!item) { [ws toast:err.length ? err : @"Couldn't switch quality" icon:@"exclamationmark.circle"]; return; }
            AVPlayer *pl = ws.keptPlayer;
            CMTime at = pl.currentTime;
            BOOL playing = pl.timeControlStatus != AVPlayerTimeControlStatusPaused;
            ws.shownQualityHeight = 0;
            ws.streamFailed = NO;
            ws.streamMaster = NO;
            item.preferredForwardBufferDuration = 3;   // start as soon as a little is ready
            pl.automaticallyWaitsToMinimizeStalling = NO;
            [pl replaceCurrentItemWithPlayerItem:item];
            if (CMTIME_IS_NUMERIC(at) && CMTimeGetSeconds(at) > 0) [pl seekToTime:at];
            if (playing) [pl play];
            [ws buildQualityMenu];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ws.keptPlayer.automaticallyWaitsToMinimizeStalling = YES;
                item.preferredForwardBufferDuration = 0;
            });
            [ws warmVariants];
        };
        if (ready) go(ready, nil);
        else [VGPlayerViewController prepareStream:known completion:go];
        return;
    }

    AVPlayerItem *cur = self.keptPlayer.currentItem;
    if (self.streamMaster && cur) {
        // One main playlist holds every quality: just limit it, no reloading and no gap in the video.
        BOOL top = [self.streamVideo.options.firstObject.identifier isEqualToString:opt.identifier];
        CGSize ps = cur.presentationSize;
        BOOL portrait = ps.width > 0 && ps.width < ps.height;
        cur.preferredMaximumResolution = top ? CGSizeZero : (portrait ? CGSizeMake(want, want * 2) : CGSizeMake(want * 2.4, want));
        NSString *t = top ? @"Auto" : [NSString stringWithFormat:@"%ldp", (long)want];
        [self.qualityLabel setTitle:t forState:UIControlStateNormal];
        [self toast:[NSString stringWithFormat:@"Switching to %@…", opt.res] icon:@"arrow.triangle.2.circlepath"];
        // After a few seconds show what is really playing, whatever the player decided.
        __weak typeof(self) wk = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (wk) wk.shownQualityHeight = 0;
        });
        return;
    }

    NSUInteger token = ++self.switchToken;
    [self toast:[NSString stringWithFormat:@"Switching to %@…", opt.res] icon:@"arrow.triangle.2.circlepath"];
    __weak typeof(self) ws = self;
    void (^fail)(NSString *) = ^(NSString *why) {
        if (!ws || ws.switchToken != token) return;
        ws.shownQualityHeight = 0;
        [ws toast:why.length ? why : @"Couldn't switch quality" icon:@"exclamationmark.circle"];
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (ws && ws.switchToken == token && ws.switchPending) { ws.switchPending = NO; fail(@"This quality is taking too long to open"); }
    });
    self.switchPending = YES;
    [[VGEngine shared] streamLinkFor:self.streamVideo option:opt completion:^(NSDictionary *info, NSString *error) {
        if (!ws || ws.switchToken != token) return;
        if (!info) { ws.switchPending = NO; fail(error); return; }
        [VGPlayerViewController prepareStream:info completion:^(AVPlayerItem *item, NSString *err) {
            if (!ws || ws.switchToken != token) return;
            ws.switchPending = NO;
            if (!item) { fail(err); return; }
            AVPlayer *pl = ws.keptPlayer;
            CMTime at = pl.currentTime;
            BOOL playing = pl.timeControlStatus != AVPlayerTimeControlStatusPaused;
            ws.shownQualityHeight = 0;
            ws.streamFailed = NO;
            ws.streamMaster = [info[@"master"] boolValue];
            [pl replaceCurrentItemWithPlayerItem:item];
            if (CMTIME_IS_NUMERIC(at) && CMTimeGetSeconds(at) > 0) [pl seekToTime:at];
            if (playing) [pl play];
            [ws buildQualityMenu];
        }];
    }];
}

/// Device heat: the real chip temperature when iOS lets the app read it, otherwise iOS's own heat level.
- (void)refreshHeat {
    NSString *text; UIColor *tint; float c = VGCPUTemperature();
    NSProcessInfoThermalState st = NSProcessInfo.processInfo.thermalState;
    if (c > 0) {
        text = [NSString stringWithFormat:@"%.0f°C", c];
        tint = c < 40 ? [UIColor systemGreenColor] : c < 48 ? [UIColor systemYellowColor] : c < 55 ? [UIColor systemOrangeColor] : [UIColor systemRedColor];
    } else {
        switch (st) {
            case NSProcessInfoThermalStateNominal: text = @"Cool"; tint = [UIColor systemGreenColor]; break;
            case NSProcessInfoThermalStateFair: text = @"Warm"; tint = [UIColor systemYellowColor]; break;
            case NSProcessInfoThermalStateSerious: text = @"Hot"; tint = [UIColor systemOrangeColor]; break;
            default: text = @"Very hot"; tint = [UIColor systemRedColor]; break;
        }
    }
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold];
    [self.heatPill setImage:[UIImage systemImageNamed:@"thermometer.medium" withConfiguration:cfg] forState:UIControlStateNormal];
    [self.heatPill setTitle:text forState:UIControlStateNormal];
    [self.heatPill setTitleColor:tint forState:UIControlStateNormal];
    self.heatPill.tintColor = tint;
}

- (void)tickWithPosition:(double)pos {
    if (self.livePending && self.keptPlayer.timeControlStatus != AVPlayerTimeControlStatusPaused) [self.keptPlayer pause];
    if (CACurrentMediaTime() - self.lastHeatCheck > 3) { self.lastHeatCheck = CACurrentMediaTime(); [self refreshHeat]; }
    if (self.streamVideo && !self.streamFailed && self.keptPlayer.currentItem.status == AVPlayerItemStatusFailed) {
        self.streamFailed = YES;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Couldn't play this stream"
            message:@"The site didn't let the player open it. You can still download the video instead." preferredStyle:UIAlertControllerStyleAlert];
        __weak typeof(self) ws = self;
        [a addAction:[UIAlertAction actionWithTitle:@"Download instead" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [ws startSave:nil]; [ws close]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { [ws close]; }]];
        [self presentViewController:a animated:YES completion:nil];
    }
    if (self.live) self.live.playhead = MAX(0, pos - self.liveOffset);
    [self updateMiniBar:pos];
    [self updateQualityLabel];
    if (self.subs) {
        if (!self.scrubbing) [self.subs setPlayhead:pos];
        [self refreshSubtitleAt:pos];
    }
    [self refreshPlayState];
    if (self.scrubbing || !self.controlsVisible) return;   // hidden buttons don't need updating
    double dur = [self duration];
    self.elapsedLabel.text = PClock(pos);
    self.durationLabel.text = dur > 0 ? PClock(dur) : @"--:--";
    self.scrubber.progress = dur > 0 ? pos / dur : 0;
}

// Moving through the video: it pauses, shows each frame as you go, and carries on when you let go.
- (void)scrubBegan {
    self.scrubbing = YES;
    self.resumeAfterScrub = [self isPlaying];
    [self.keptPlayer pause];
    self.chaseTime = self.keptPlayer.currentTime;
    self.hideToken++;
}

- (void)scrubToSeconds:(double)seconds {
    double dur = [self duration];
    seconds = MIN(MAX(seconds, 0), dur);
    self.chaseTime = CMTimeMakeWithSeconds(MAX(0, seconds - self.liveOffset), 600);
    [self updateMiniBar:seconds];
    if (self.subs) [self refreshSubtitleAt:seconds];
    [self chase];
}

// One seek at a time, always toward the latest spot, so frames keep up with your finger.
- (void)chase {
    if (self.seeking) return;
    self.seeking = YES;
    CMTime target = self.chaseTime;
    __weak typeof(self) ws = self;
    [self.keptPlayer seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            VGPlayerViewController *me = ws;
            if (!me) return;
            me.seeking = NO;
            if (CMTimeCompare(target, me.chaseTime) != 0) [me chase];
        });
    }];
}

- (void)scrubEnded {
    if (!self.scrubbing) return;
    self.scrubbing = NO;
    [self.subs setPlayhead:CMTimeGetSeconds(self.chaseTime)];
    if (self.resumeAfterScrub) self.keptPlayer.rate = (float)self.speed;
    [self tickWithPosition:CMTimeGetSeconds(self.chaseTime)];
    [self scheduleHide];
    [self updateNowPlaying];
}

#pragma mark Gesture host

- (AVPlayer *)gesturePlayer { return self.keptPlayer; }
- (void)gestureScrubBegan { [self scrubBegan]; }
- (void)gestureScrubToSeconds:(double)seconds { [self scrubToSeconds:seconds]; }
- (void)gestureScrubEnded { [self scrubEnded]; }

#pragma mark Starting and stopping

- (void)start {
    if (self.started) return;
    self.started = YES;
    [VGMiniVideoView closeOthersThan:self];
    [VGMusicPlayer.shared pause];   // the Library's music bar gives way to a video
    gOpenPlayers++;
    self.counted = YES;
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeMoviePlayback options:0 error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];

    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:[VGPlayerViewController positionsKey]];
    double at = self.key ? [saved[self.key] doubleValue] : 0;
    AVPlayer *pl = self.keptPlayer;
    if (at > 5) [pl seekToTime:CMTimeMakeWithSeconds(at, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    pl.rate = (float)self.speed;

    __weak typeof(self) ws = self;
    self.timeObserver = [pl addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.25, 600) queue:dispatch_get_main_queue()
                                                    usingBlock:^(CMTime t) { if (ws.keptPlayer.rate > 0) ws.wantPlay = YES; [ws tick]; }];
    self.saveObserver = [pl addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(5, 1) queue:dispatch_get_main_queue()
                                                    usingBlock:^(CMTime t) { [ws savePosition]; [ws updateNowPlaying]; }];
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    [nc addObserver:self selector:@selector(toBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(toForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(finished:) name:AVPlayerItemDidPlayToEndTimeNotification object:pl.currentItem];
    [self setupRemote];
    [self updateNowPlaying];
    [self refreshPlayState];
    [self scheduleHide];
    if (VGSubtitles.enabled && VGSubtitles.startOn && VGSubtitles.currentModelReady) [self startSubtitles];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

/// The down arrow: the player goes away but the video keeps playing in a small bar, like the YouTube app.
- (void)minimize {
    if (!self.started || self.pip.isPictureInPictureActive || !self.keptPlayer.currentItem) { [self close]; return; }
    self.minimized = YES;
    __weak typeof(self) ws = self;
    [self dismissViewControllerAnimated:YES completion:^{
        VGPlayerViewController *me = ws;
        if (me && me.minimized) [VGMiniVideoView showFor:me];
    }];
}

- (void)savePosition {
    AVPlayer *pl = self.keptPlayer;
    if (!pl.currentItem || !self.key) return;
    double now = CMTimeGetSeconds(pl.currentTime) + self.liveOffset, total = self.live ? self.live.duration : CMTimeGetSeconds(pl.currentItem.duration);
    NSMutableDictionary *d = [[NSUserDefaults.standardUserDefaults dictionaryForKey:[VGPlayerViewController positionsKey]] mutableCopy] ?: [NSMutableDictionary dictionary];
    // Near the start or the end: nothing to resume.
    if (!(now > 5) || (total > 0 && now > total - 10)) [d removeObjectForKey:self.key];
    else d[self.key] = @(now);
    if (d.count > 300) [d removeAllObjects];
    [NSUserDefaults.standardUserDefaults setObject:d forKey:[VGPlayerViewController positionsKey]];
}

- (void)finished:(NSNotification *)n {
    if (self.onEnded) { void (^cb)(VGPlayerViewController *) = self.onEnded; if (!self.playlistMode) self.onEnded = nil; cb(self); return; }
    if (!self.key) { [self refreshPlayState]; [self showControls]; [self updateNowPlaying]; return; }
    NSMutableDictionary *d = [[NSUserDefaults.standardUserDefaults dictionaryForKey:[VGPlayerViewController positionsKey]] mutableCopy];
    [d removeObjectForKey:self.key];
    if (d) [NSUserDefaults.standardUserDefaults setObject:d forKey:[VGPlayerViewController positionsKey]];
    [self refreshPlayState];
    [self showControls];
    [self updateNowPlaying];
}

// Taking the picture off the player lets the sound keep going when the phone locks or you switch apps.
- (void)toBackground {
    [self savePosition];
    if (!self.inPiP && !self.pip.isPictureInPictureActive && self.keptPlayer.rate > 0) self.videoView.playerLayer.player = nil;
}

/// A call or another app's sound stops the video; carry on afterwards if it was playing.
- (void)audioInterrupted:(NSNotification *)n {
    NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type != AVAudioSessionInterruptionTypeEnded || !self.wantPlay) return;
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!ws || !ws.wantPlay || ws.keptPlayer.rate > 0) return;
        [AVAudioSession.sharedInstance setActive:YES error:nil];
        [ws resume];
    });
}

- (void)toForeground {
    if (self.videoView.playerLayer.player != self.keptPlayer) self.videoView.playerLayer.player = self.keptPlayer;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.onScreenCounted) { self.onScreenCounted = NO; gOnScreen = MAX(0, gOnScreen - 1); }
    [self savePosition];
    [self.gestures restoreBrightness];   // brightness goes back to normal when the player leaves the screen
    if (!self.inPiP && !self.restoring && !self.minimized) [self shutDown];
    dispatch_async(dispatch_get_main_queue(), ^{ [UIViewController attemptRotationToDeviceOrientation]; });   // back to upright
}

- (void)shutDown {
    gPreparing = NO;
    [self stopLive];
    [self stopSubtitles];
    [self.gestures detach];
    self.gestures = nil;
    [self.keptPlayer pause];
    if (self.timeObserver) { [self.keptPlayer removeTimeObserver:self.timeObserver]; self.timeObserver = nil; }
    if (self.saveObserver) { [self.keptPlayer removeTimeObserver:self.saveObserver]; self.saveObserver = nil; }
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self teardownRemote];
    if (self.counted) { self.counted = NO; gOpenPlayers = MAX(0, gOpenPlayers - 1); [VGKeepAlive playerClosed]; }
}

#pragma mark Lock screen and headphone controls

- (void)setupRemote {
    MPRemoteCommandCenter *cc = MPRemoteCommandCenter.sharedCommandCenter;
    self.remoteTokens = [NSMutableArray array];
    __weak typeof(self) ws = self;
    void (^add)(MPRemoteCommand *, MPRemoteCommandHandlerStatus (^)(MPRemoteCommandEvent *)) = ^(MPRemoteCommand *cmd, MPRemoteCommandHandlerStatus (^h)(MPRemoteCommandEvent *)) {
        cmd.enabled = YES;
        id token = [cmd addTargetWithHandler:h];
        [ws.remoteTokens addObject:@[cmd, token]];
    };
    add(cc.playCommand, ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [ws resume]; return MPRemoteCommandHandlerStatusSuccess; });
    add(cc.pauseCommand, ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [ws pausePlayback]; return MPRemoteCommandHandlerStatusSuccess; });
    add(cc.togglePlayPauseCommand, ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [ws togglePlay]; return MPRemoteCommandHandlerStatusSuccess; });
    cc.skipForwardCommand.preferredIntervals = @[@10];
    cc.skipBackwardCommand.preferredIntervals = @[@10];
    add(cc.skipForwardCommand, ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [ws skip:10]; return MPRemoteCommandHandlerStatusSuccess; });
    add(cc.skipBackwardCommand, ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [ws skip:-10]; return MPRemoteCommandHandlerStatusSuccess; });
    add(cc.nextTrackCommand, ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { if (!ws.playlistMode) return MPRemoteCommandHandlerStatusCommandFailed; [ws nextTrack]; return MPRemoteCommandHandlerStatusSuccess; });
    add(cc.previousTrackCommand, ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { if (!ws.playlistMode) return MPRemoteCommandHandlerStatusCommandFailed; [ws previousTrack]; return MPRemoteCommandHandlerStatusSuccess; });
    [self refreshRemoteMode];
    add(cc.changePlaybackPositionCommand, ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        double to = ((MPChangePlaybackPositionCommandEvent *)e).positionTime;
        [ws.keptPlayer seekToTime:CMTimeMakeWithSeconds(MAX(0, to - ws.liveOffset), 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        [ws updateNowPlaying];
        return MPRemoteCommandHandlerStatusSuccess;
    });
}

/// Playlists get previous/next on the lock screen; single videos keep the 10 second buttons.
- (void)refreshRemoteMode {
    if (!self.remoteTokens) return;
    MPRemoteCommandCenter *cc = MPRemoteCommandCenter.sharedCommandCenter;
    BOOL pl = self.playlistMode;
    cc.nextTrackCommand.enabled = cc.previousTrackCommand.enabled = pl;
    cc.skipForwardCommand.enabled = cc.skipBackwardCommand.enabled = !pl;
}

- (void)teardownRemote {
    for (NSArray *pair in self.remoteTokens) [(MPRemoteCommand *)pair[0] removeTarget:pair[1]];
    self.remoteTokens = nil;
    MPRemoteCommandCenter.sharedCommandCenter.nextTrackCommand.enabled = NO;
    MPRemoteCommandCenter.sharedCommandCenter.previousTrackCommand.enabled = NO;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nil;
}

/// Tries each picture address in turn; the first one that is a real image becomes the lock screen cover.
- (void)fetchArtworkFrom:(NSArray<NSString *> *)urls index:(NSUInteger)i key:(NSString *)key owner:(VGPlayerViewController *)owner {
    __weak typeof(self) ws = self;
    void (^retryLater)(void) = ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VGPlayerViewController *me = ws;
            if (me && !me.artwork && [me.artFetchURL isEqualToString:key]) { me.artFetchURL = nil; [me updateNowPlaying]; }   // another go
        });
    };
    if (i >= urls.count) { retryLater(); return; }
    NSURL *u = [NSURL URLWithString:urls[i]];
    if (!u) { [self fetchArtworkFrom:urls index:i + 1 key:key owner:owner]; return; }
    [[NSURLSession.sharedSession dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        NSInteger code = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 200;
        UIImage *img = (data && code < 400) ? [UIImage imageWithData:data] : nil;
        if (!img || img.size.width < 40) {
            dispatch_async(dispatch_get_main_queue(), ^{ [ws fetchArtworkFrom:urls index:i + 1 key:key owner:ws]; });
            return;
        }
        CGFloat side = MIN(img.size.width, img.size.height);
        CGRect crop = CGRectMake((img.size.width - side) / 2 * img.scale, (img.size.height - side) / 2 * img.scale, side * img.scale, side * img.scale);
        CGImageRef cg = CGImageCreateWithImageInRect(img.CGImage, crop);
        UIImage *sq = cg ? [UIImage imageWithCGImage:cg scale:img.scale orientation:img.imageOrientation] : img;
        if (cg) CGImageRelease(cg);
        dispatch_async(dispatch_get_main_queue(), ^{
            VGPlayerViewController *me = ws;
            if (!me || ![me.artFetchURL isEqualToString:key] || me.artwork) return;   // another song started meanwhile
            me.artwork = sq;
            [me updateNowPlaying];
        });
    }] resume];
}

- (void)updateNowPlaying {
    if (!self.counted) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = self.titleText ?: @"VidGrab";
    if (self.artistText.length) info[MPMediaItemPropertyArtist] = self.artistText;
    if (self.albumText.length) info[MPMediaItemPropertyAlbumTitle] = self.albumText;
    info[MPMediaItemPropertyPlaybackDuration] = @([self duration]);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @([self position]);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @([self isPlaying] ? self.speed : 0);
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = @1.0;
    if (self.streamVideo && !self.artistText.length && self.streamVideo.uploader.length) info[MPMediaItemPropertyArtist] = self.streamVideo.uploader;
    // A streamed song has no saved cover: use the video's own picture (square, from the middle) on the lock screen.
    // If the first address doesn't give a picture, the site's standard picture for that video is tried, and the whole
    // thing is tried again a little later instead of staying grey for the rest of the song.
    NSString *turl = self.streamVideo.thumbnail;
    NSString *vurl = self.streamVideo.url;
    if (!self.artwork && (turl.length || vurl.length) && ![self.artFetchURL isEqualToString:turl ?: vurl]) {
        NSString *key = turl ?: vurl;
        self.artFetchURL = key;
        NSMutableArray<NSString *> *cands = [NSMutableArray array];
        if (turl.length) [cands addObject:turl];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?:v=|youtu\\.be/|shorts/)([\\w-]{11})" options:0 error:nil];
        NSTextCheckingResult *m = vurl.length ? [re firstMatchInString:vurl options:0 range:NSMakeRange(0, vurl.length)] : nil;
        if (m) {
            NSString *vid = [vurl substringWithRange:[m rangeAtIndex:1]];
            [cands addObject:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg", vid]];
            [cands addObject:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/mqdefault.jpg", vid]];
        }
        __weak typeof(self) ws = self;
        [self fetchArtworkFrom:cands index:0 key:key owner:ws];
    }
    UIImage *art = self.artwork;
    if (art) info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:art.size requestHandler:^UIImage *(CGSize s) { return art; }];
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
}

#pragma mark Playlist

- (void)setPlaylistMode:(BOOL)on {
    _playlistMode = on;
    self.prevTrackButton.hidden = self.nextTrackButton.hidden = !on;
    self.shuffleButton.hidden = self.repeatButton.hidden = self.videoToggleButton.hidden = !on;
    [self refreshRemoteMode];
    [self updateControlLayout];
}

- (void)styleModeButtons {
    UIColor *on = VGAccent, *off = UIColor.whiteColor;
    self.shuffleButton.tintColor = self.shuffleOn ? on : off;
    self.repeatButton.tintColor = self.repeatMode ? on : off;
    NSString *name = self.repeatMode == 2 ? @"repeat.1" : @"repeat";
    SetSymbol(self.repeatButton, name, 16);
    self.repeatButton.tintColor = self.repeatMode ? on : off;
    SetSymbol(self.shuffleButton, @"shuffle", 16);
    self.shuffleButton.tintColor = self.shuffleOn ? on : off;
}


- (BOOL)videoOff { return _videoOff && self.playlistMode; }

- (void)setVideoOff:(BOOL)off {
    _videoOff = off;
    [self applyVideoOff];
}

- (void)toggleVideo {
    _videoOff = !_videoOff;
    [NSUserDefaults.standardUserDefaults setBool:_videoOff forKey:@"vgPlaylistVideoOff"];
    [self applyVideoOff];
    [self showMessage:_videoOff ? @"Video off" : @"Video on"];
    [self showControls];
}

/// Off: the VidGrab banner replaces the picture and the player stops loading it when it can. The sound keeps playing.
- (void)applyVideoOff {
    BOOL off = self.videoOff;
    self.videoView.hidden = off;
    self.bannerView.hidden = !off;
    self.audioArtView.hidden = off || !self.audioOnly;
    self.pipButton.hidden = off || self.pip == nil;
    [self updateControlLayout];
    SetSymbol(self.videoToggleButton, off ? @"video.slash.fill" : @"video.fill", 16);
    self.videoToggleButton.tintColor = off ? VGAccent : UIColor.whiteColor;
    [self syncVideoTracks];
}

- (void)syncVideoTracks {
    BOOL off = self.videoOff;
    for (AVPlayerItemTrack *t in self.keptPlayer.currentItem.tracks) {
        if ([t.assetTrack.mediaType isEqualToString:AVMediaTypeVideo] && t.enabled == off) t.enabled = !off;
    }
}

- (void)shuffleTapped {
    self.shuffleOn = !self.shuffleOn;
    [self styleModeButtons];
    [self showMessage:self.shuffleOn ? @"Shuffle on" : @"Shuffle off"];
    if (self.onModeChange) self.onModeChange(self.shuffleOn, self.repeatMode);
    [self showControls];
}

- (void)repeatTapped {
    self.repeatMode = (self.repeatMode + 1) % 3;
    [self styleModeButtons];
    [self showMessage:@[@"Repeat off", @"Repeat all", @"Repeat one"][self.repeatMode]];
    if (self.onModeChange) self.onModeChange(self.shuffleOn, self.repeatMode);
    [self showControls];
}

- (CGFloat)trackSheetLift {
    for (UIView *v in self.view.subviews) if ([v isKindOfClass:VGTrackSheet.class]) return ((VGTrackSheet *)v).card.bounds.size.height + 20;
    return 0;
}

/// Short messages ("Opening 3 of 81..."): top centre, level with the top buttons in landscape and just under them in
/// portrait; above the Tracks list when that is open, so it is never hidden behind it.
- (void)say:(NSString *)text icon:(NSString *)icon {
    CGFloat sheet = [self trackSheetLift];
    BOOL portrait = self.view.bounds.size.height > self.view.bounds.size.width;
    if (sheet > 0) [VGActions toast:text icon:icon in:self.view bottom:sheet];
    else [VGActions toast:text icon:icon in:self.view top:portrait ? 62 : 8];
}

- (void)showTracks {
    if (!self.trackProvider) return;
    NSDictionary *d = self.trackProvider();
    NSArray *titles = d[@"titles"];
    if (![titles isKindOfClass:NSArray.class] || !titles.count) return;
    for (UIView *v in self.view.subviews) if ([v isKindOfClass:VGTrackSheet.class]) return;
    VGTrackSheet *sheet = [[VGTrackSheet alloc] initWithTitles:titles current:[d[@"current"] integerValue]];
    __weak typeof(self) ws = self;
    sheet.provider = self.trackProvider;
    sheet.onPick = ^(NSInteger pos) { if (ws.onPickTrack) ws.onPickTrack(pos); [ws showControls]; };
    [sheet presentIn:self.view];
}

- (void)nextTrack { if (self.onSkip) self.onSkip(self, 1); [self showControls]; }
- (void)previousTrack { if (self.onSkip) self.onSkip(self, -1); [self showControls]; }

- (double)currentSeconds { return [self position]; }

- (void)showMessage:(NSString *)text { [self toast:text icon:@"info.circle"]; }

- (void)restartTrack {
    AVPlayer *pl = self.keptPlayer;
    [pl seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    pl.rate = (float)self.speed;
    [self refreshPlayState];
    [self updateNowPlaying];
}

- (void)showFinished {
    [self refreshPlayState];
    [self showControls];
    [self updateNowPlaying];
}

/// Swaps the picture and sound for the next track while the player stays on screen.
- (void)swapToStreamItem:(AVPlayerItem *)item video:(VGVideo *)video audio:(BOOL)audio master:(BOOL)master variants:(NSDictionary *)variants position:(NSString *)position {
    AVPlayer *pl = self.keptPlayer;
    [self stopSubtitles];
    [NSNotificationCenter.defaultCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:pl.currentItem];
    self.switchToken++;
    self.switchPending = NO;
    self.preparingHigh = NO;
    [self.warmItems removeAllObjects];
    [self.warming removeAllObjects];
    self.streamVideo = video;
    self.artwork = nil; self.artFetchURL = nil;   // the last song's picture is not this one's
    self.streamOption = nil;
    self.fpsHint = nil;
    self.streamFailed = NO;
    self.savingStream = NO;
    self.streamMaster = master;
    self.streamVariants = variants;
    self.shownQualityHeight = 0;
    self.tracksLoaded = NO;
    self.positionText = position;
    self.titleText = video.title.length ? video.title : @"Video";
    self.titleLabel.text = position.length ? [NSString stringWithFormat:@"%@  ·  %@", position, self.titleText] : self.titleText;
    // Music and video look different; change the screen without rebuilding it.
    self.audioOnly = audio;
    if (audio && !self.audioArtView) [self buildAudioArt];
    self.audioArtView.hidden = !audio || self.videoOff;
    self.sizeButton.hidden = self.rotateButton.hidden = audio;
    self.midCenterY.constant = audio ? 150 : 0;
    [self updateControlLayout];
    self.qualityLabel.hidden = YES;
    self.saveButton.hidden = NO;
    [pl replaceCurrentItemWithPlayerItem:item];
    pl.rate = (float)self.speed;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(finished:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [self loadMediaOptions];
    [self buildMediaMenu];
    [self buildQualityMenu];
    [self tickWithPosition:0];
    [self syncVideoTracks];
    [self refreshPlayState];
    [self updateNowPlaying];
    [self showControls];
    [self scheduleHide];
}

#pragma mark Subtitles and audio tracks

- (void)loadMediaOptions {
    AVAsset *asset = self.keptPlayer.currentItem.asset;
    if (!asset || self.audioOnly) return;
    __weak typeof(self) ws = self;
    [asset loadValuesAsynchronouslyForKeys:@[@"availableMediaCharacteristicsWithMediaSelectionOptions"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{ ws.tracksLoaded = YES; [ws buildMediaMenu]; });
    }];
}

- (void)buildMediaMenu {
    AVPlayerItem *item = self.keptPlayer.currentItem;
    AVAsset *asset = item.asset;
    if (!item) return;
    __weak typeof(self) ws = self;
    NSMutableArray *kids = [NSMutableArray array];
    if (VGSubtitles.enabled) {
        UIAction *autoItem = [UIAction actionWithTitle:@"Auto English subtitles" image:[UIImage systemImageNamed:@"waveform"] identifier:nil handler:^(UIAction *x) { [ws toggleSubtitles]; }];
        autoItem.state = self.subs ? UIMenuElementStateOn : UIMenuElementStateOff;
        [kids addObject:autoItem];
    }
    AVMediaSelectionGroup *audio = self.tracksLoaded ? [asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible] : nil;
    AVMediaSelectionGroup *subs = self.tracksLoaded ? [asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicLegible] : nil;

    if (audio.options.count > 1) {
        AVMediaSelectionOption *current = [item.currentMediaSelection selectedMediaOptionInMediaSelectionGroup:audio];
        NSMutableArray *acts = [NSMutableArray array];
        for (AVMediaSelectionOption *o in audio.options) {
            UIAction *a = [UIAction actionWithTitle:o.displayName image:nil identifier:nil handler:^(UIAction *x) {
                [item selectMediaOption:o inMediaSelectionGroup:audio]; [ws buildMediaMenu]; [ws showControls];
            }];
            a.state = o == current ? UIMenuElementStateOn : UIMenuElementStateOff;
            [acts addObject:a];
        }
        [kids addObject:[UIMenu menuWithTitle:@"Audio" image:[UIImage systemImageNamed:@"speaker.wave.2"] identifier:nil options:0 children:acts]];
    }
    if (subs.options.count > 0) {
        AVMediaSelectionOption *current = [item.currentMediaSelection selectedMediaOptionInMediaSelectionGroup:subs];
        NSMutableArray *acts = [NSMutableArray array];
        UIAction *off = [UIAction actionWithTitle:@"Off" image:nil identifier:nil handler:^(UIAction *x) {
            [item selectMediaOption:nil inMediaSelectionGroup:subs]; [ws buildMediaMenu]; [ws showControls];
        }];
        off.state = current == nil ? UIMenuElementStateOn : UIMenuElementStateOff;
        [acts addObject:off];
        for (AVMediaSelectionOption *o in subs.options) {
            UIAction *a = [UIAction actionWithTitle:o.displayName image:nil identifier:nil handler:^(UIAction *x) {
                [item selectMediaOption:o inMediaSelectionGroup:subs]; [ws buildMediaMenu]; [ws showControls];
            }];
            a.state = o == current ? UIMenuElementStateOn : UIMenuElementStateOff;
            [acts addObject:a];
        }
        [kids addObject:[UIMenu menuWithTitle:@"Subtitles" image:[UIImage systemImageNamed:@"captions.bubble"] identifier:nil options:0 children:acts]];
    }
    self.captionsButton.hidden = kids.count == 0;
    if (kids.count) {
        self.captionsButton.menu = [UIMenu menuWithTitle:@"" children:kids];
        self.captionsButton.showsMenuAsPrimaryAction = YES;
    }
}

#pragma mark Auto subtitles

// The line of text near the bottom. It sits above the buttons while they show, and drops down when they fade.
- (void)buildSubtitleBox {
    UIView *box = [UIView new];
    box.backgroundColor = [UIColor colorWithWhite:0 alpha:0.64];
    box.layer.cornerRadius = 11;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.alpha = 0;
    box.userInteractionEnabled = NO;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *l = [UILabel new];
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:l];
    [self.view addSubview:box];
    self.subtitleBox = box;
    self.subtitleLabel = l;
    self.subtitleBottom = [box.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-26];
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:13], [l.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-13],
        [l.topAnchor constraintEqualToAnchor:box.topAnchor constant:7], [l.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-7],
        [box.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [box.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor multiplier:0.86],
        self.subtitleBottom]];
}

- (void)refreshSubtitleAt:(double)pos {
    NSString *line = [self.subs textAt:pos];
    BOOL isStatus = NO;
    if (!line.length && self.subs.status.length) { line = self.subs.status; isStatus = YES; }
    NSString *shown = line.length ? (isStatus ? [@"\u200B" stringByAppendingString:line] : line) : nil;   // the invisible mark tells a status from a line
    if ((shown == nil && self.shownSubtitle == nil) || [shown isEqualToString:self.shownSubtitle]) return;
    self.shownSubtitle = shown;
    if (line.length) {
        self.subtitleLabel.font = isStatus ? VGFont(14, UIFontWeightMedium) : VGFont(17, UIFontWeightSemibold);
        self.subtitleLabel.textColor = isStatus ? VGSecondary : UIColor.whiteColor;
        self.subtitleLabel.text = line;
    }
    [UIView animateWithDuration:0.15 animations:^{ self.subtitleBox.alpha = line.length ? 1 : 0; }];
}

- (void)startSubtitles {
    if (self.subs || !self.fileURL) return;
    VGSubtitleEngine *e = [[VGSubtitleEngine alloc] initWithURL:self.fileURL key:self.key ?: self.fileURL.lastPathComponent quality:VGSubtitles.quality];
    __weak typeof(self) ws = self;
    e.onChange = ^{ VGPlayerViewController *me = ws; if (me.subs) [me refreshSubtitleAt:[me position]]; };
    [e setPlayhead:[self position]];
    self.subs = e;
    [e start];
    [self refreshSubtitleAt:[self position]];
}

- (void)stopSubtitles {
    [self.subs stop];
    self.subs = nil;
    self.shownSubtitle = nil;
    self.subtitleBox.alpha = 0;
}

/// Opens the quality picker. The download only starts once a quality is chosen.
- (void)saveStream {
    if (!self.streamVideo.options.count) {
        // A video picked from a playlist only has its link so far: look up its qualities, then show the choices.
        VGVideo *current = self.streamVideo;
        if (!current.url.length || self.savingStream) { [self toast:@"Can't download this one" icon:@"exclamationmark.circle"]; return; }
        self.savingStream = YES;
        [self toast:@"Getting download choices…" icon:@"arrow.down.circle"];
        [self holdControlsFor:6];
        __weak typeof(self) ws = self;
        [[VGEngine shared] fetch:current.url completion:^(VGVideo *full, NSString *error) {
            ws.savingStream = NO;
            if (!ws) return;
            if (!full.options.count) { [ws toast:@"Can't download this one" icon:@"exclamationmark.circle"]; return; }
            current.options = full.options;
            if (!current.thumbnail.length) current.thumbnail = full.thumbnail;
            if (ws.streamVideo == current) [ws saveStream];   // still the same track: show the choices
        }];
        return;
    }
    VGOption *autoOpt = [VGDownloadDefaults autoPickFrom:self.streamVideo.options];   // Settings > Downloads
    if (autoOpt) { [self startSave:autoOpt]; return; }
    for (UIView *v in self.view.subviews) if ([v isKindOfClass:VGSaveCard.class]) return;
    VGSaveCard *card = [[VGSaveCard alloc] initWithVideo:self.streamVideo playing:self.streamOption];
    __weak typeof(self) ws = self;
    card.onPick = ^(VGOption *o) { [ws startSave:o]; };
    [card presentIn:self.view];
}

- (void)startSave:(VGOption *)opt {
    if (!opt) opt = self.streamOption ?: self.streamVideo.options.firstObject;
    if (!opt || !self.streamVideo) return;
    [self.saveButton setImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    [self toast:[NSString stringWithFormat:@"Downloading %@. Find it in Downloads", opt.audio ? @"audio" : opt.res] icon:@"arrow.down.circle.fill"];
    [self holdControlsFor:4];
    [[VGEngine shared] download:self.streamVideo option:opt progress:nil completion:nil];
}

- (void)toggleSubtitles {
    if (self.streamVideo) {
        [self toast:@"Auto subtitles work on downloaded videos" icon:@"captions.bubble"];
        return;
    }
    if (self.subs) {
        [self stopSubtitles];
        VGSubtitles.startOn = NO;
        [self toast:@"Auto subtitles off" icon:@"captions.bubble"];
    } else if (![VGSubtitles currentModelReady]) {
        [self toast:@"Download the speech model in Settings first" icon:@"arrow.down.circle"];
    } else {
        VGSubtitles.startOn = YES;
        [self startSubtitles];
        [self toast:@"Auto English subtitles on" icon:@"captions.bubble.fill"];
    }
    [self buildMediaMenu];
    [self showControls];
}

#pragma mark Rotate

- (void)rotate {
    BOOL landscape = self.view.bounds.size.width > self.view.bounds.size.height;
    [self showControls];
    if (@available(iOS 16.0, *)) {
        UIInterfaceOrientationMask want = landscape ? UIInterfaceOrientationMaskPortrait : UIInterfaceOrientationMaskLandscape;
        UIWindowSceneGeometryPreferencesIOS *prefs = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:want];
        [self.view.window.windowScene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *e) {}];
    } else {
        [UIDevice.currentDevice setValue:@(landscape ? UIInterfaceOrientationPortrait : UIInterfaceOrientationLandscapeRight) forKey:@"orientation"];
        [UIViewController attemptRotationToDeviceOrientation];
    }
}

#pragma mark Picture in picture

- (void)togglePiP {
    if (self.pip.isPictureInPictureActive) { [self.pip stopPictureInPicture]; return; }
    if (!self.pip.isPictureInPicturePossible) { [self toast:@"Picture in Picture isn't ready yet" icon:@"pip.enter"]; return; }
    [self.pip startPictureInPicture];
}

- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)p {
    self.inPiP = YES;
    if (!gPiPPlayers) gPiPPlayers = [NSMutableSet set];
    [gPiPPlayers addObject:self];
}

// Like the system player: step aside so the app shows behind the little window.
- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)p {
    if (self.presentingViewController && !self.isBeingDismissed) [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)p failedToStartPictureInPictureWithError:(NSError *)error {
    self.inPiP = NO;
    [gPiPPlayers removeObject:self];
    [self toast:@"Couldn't start Picture in Picture" icon:@"pip.enter"];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)p {
    self.inPiP = NO;
    [self savePosition];
    // Closed the little window with X (not the enlarge button): stop for real.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.restoring && !self.view.window) [self shutDown];
        [gPiPPlayers removeObject:self];
    });
}

// The enlarge button in the little window: bring the full player back on screen and keep playing.
- (void)pictureInPictureController:(AVPictureInPictureController *)p
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))done {
    if (self.view.window) { done(YES); return; }
    self.restoring = YES;
    gPreparing = YES;
    [gPiPPlayers addObject:self];   // keep alive until it's back on screen
    __weak typeof(self) ws = self;
    void (^show)(void) = ^{
        VGPlayerViewController *me = ws;
        UIViewController *host = [VGPlayerViewController hostForRestore];
        if (!me || !host) { if (me) me.restoring = NO; done(NO); return; }
        if (me.videoView.playerLayer.player != me.keptPlayer) me.videoView.playerLayer.player = me.keptPlayer;
        me.modalPresentationStyle = UIModalPresentationFullScreen;
        [host presentViewController:me animated:YES completion:^{
            me.restoring = NO;
            done(YES);
            if (me.keptPlayer.rate == 0) [me resume];
        }];
    };
    // Tapped while VidGrab was in the background: wait until the app is on screen.
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) show();
    else {
        __block id token = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                                           queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            [NSNotificationCenter.defaultCenter removeObserver:token];
            show();
        }];
    }
}

+ (UIViewController *)hostForRestore {
    UIWindow *win = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) if (w.isKeyWindow) win = w;
    }
    if (!win) win = UIApplication.sharedApplication.delegate.window;
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

@end

#pragma mark - The small bar

static VGMiniVideoView *gMiniBar;

@interface VGMiniVideoView ()
@property (nonatomic, strong) VGPlayerViewController *player;
@property (nonatomic, strong) AVPlayerLayer *picture;
@property (nonatomic, strong) UIView *pictureHolder, *progress;
@property (nonatomic, strong) UILabel *titleLabel, *stateLabel;
@property (nonatomic, strong) UIButton *playB, *closeB;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation VGMiniVideoView

+ (BOOL)activeFor:(VGPlayerViewController *)player { return gMiniBar && gMiniBar.player == player; }

+ (void)closeOthersThan:(VGPlayerViewController *)player {
    if (gMiniBar && gMiniBar.player != player) [gMiniBar closeNow];
}

+ (void)showFor:(VGPlayerViewController *)player {
    if (gMiniBar) { if (gMiniBar.player == player) return; [gMiniBar closeNow]; }
    UIWindow *win = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) if (w.isKeyWindow) win = w;
    }
    if (!win) { [player shutDown]; return; }
    VGMiniVideoView *m = [[VGMiniVideoView alloc] initWithPlayer:player];
    UIViewController *root = win.rootViewController;
    UIView *host = win;
    NSLayoutYAxisAnchor *bottom = win.safeAreaLayoutGuide.bottomAnchor;
    CGFloat gap = -8;
    if ([root isKindOfClass:UITabBarController.class]) {
        UITabBarController *tbc = (UITabBarController *)root;
        host = tbc.view; bottom = tbc.tabBar.topAnchor; gap = -8;
    }
    m.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:m];
    [NSLayoutConstraint activateConstraints:@[
        [m.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:10], [m.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-10],
        [m.bottomAnchor constraintEqualToAnchor:bottom constant:gap], [m.heightAnchor constraintEqualToConstant:66]]];
    gMiniBar = m;
    m.alpha = 0; m.transform = CGAffineTransformMakeTranslation(0, 24);
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{ m.alpha = 1; m.transform = CGAffineTransformIdentity; } completion:nil];
}

- (instancetype)initWithPlayer:(VGPlayerViewController *)player {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.player = player;
    self.backgroundColor = VGSurface2;
    self.layer.cornerRadius = 16;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1;
    self.layer.borderColor = VGStroke.CGColor;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.35; self.layer.shadowRadius = 10; self.layer.shadowOffset = CGSizeMake(0, 3);

    self.pictureHolder = [UIView new];
    self.pictureHolder.backgroundColor = UIColor.blackColor;
    self.pictureHolder.layer.cornerRadius = 9;
    self.pictureHolder.layer.cornerCurve = kCACornerCurveContinuous;
    self.pictureHolder.clipsToBounds = YES;
    self.pictureHolder.translatesAutoresizingMaskIntoConstraints = NO;
    self.picture = [AVPlayerLayer playerLayerWithPlayer:player.keptPlayer];
    self.picture.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.pictureHolder.layer addSublayer:self.picture];

    self.titleLabel = [UILabel new]; self.titleLabel.font = VGFont(14, UIFontWeightSemibold); self.titleLabel.textColor = VGText;
    self.titleLabel.text = player.titleText.length ? player.titleText : @"Video";
    self.stateLabel = [UILabel new]; self.stateLabel.font = VGFont(12, UIFontWeightMedium); self.stateLabel.textColor = VGSecondary;
    UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.stateLabel]];
    labels.axis = UILayoutConstraintAxisVertical; labels.spacing = 2;
    labels.translatesAutoresizingMaskIntoConstraints = NO;

    self.playB = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeB = [UIButton buttonWithType:UIButtonTypeSystem];
    for (UIButton *b in @[self.playB, self.closeB]) { b.tintColor = VGText; b.translatesAutoresizingMaskIntoConstraints = NO; }
    [self.closeB setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    self.closeB.tintColor = VGSecondary;
    self.closeB.accessibilityLabel = @"Close video";
    [self.playB addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
    [self.closeB addTarget:self action:@selector(closeNow) forControlEvents:UIControlEventTouchUpInside];

    self.progress = [UIView new];
    self.progress.backgroundColor = VGAccent;
    self.progress.layer.cornerRadius = 1.5;

    for (UIView *v in @[self.pictureHolder, labels, self.playB, self.closeB]) [self addSubview:v];
    [self addSubview:self.progress];
    [NSLayoutConstraint activateConstraints:@[
        [self.pictureHolder.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:9],
        [self.pictureHolder.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.pictureHolder.widthAnchor constraintEqualToConstant:84], [self.pictureHolder.heightAnchor constraintEqualToConstant:48],
        [labels.leadingAnchor constraintEqualToAnchor:self.pictureHolder.trailingAnchor constant:10],
        [labels.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-2],
        [labels.trailingAnchor constraintEqualToAnchor:self.playB.leadingAnchor constant:-4],
        [self.playB.widthAnchor constraintEqualToConstant:44], [self.playB.heightAnchor constraintEqualToConstant:44],
        [self.playB.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.playB.trailingAnchor constraintEqualToAnchor:self.closeB.leadingAnchor],
        [self.closeB.widthAnchor constraintEqualToConstant:40], [self.closeB.heightAnchor constraintEqualToConstant:44],
        [self.closeB.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.closeB.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
    ]];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(expand)]];
    UISwipeGestureRecognizer *down = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(closeNow)];
    down.direction = UISwipeGestureRecognizerDirectionDown;
    [self addGestureRecognizer:down];

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(toBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(toForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(musicStarted) name:VGMusicChangedNotification object:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [self refresh];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.picture.frame = self.pictureHolder.bounds;
    double d = [self.player duration], pos = [self.player position];
    CGFloat w = d > 0 ? (self.bounds.size.width - 28) * MIN(1, pos / d) : 0;
    self.progress.frame = CGRectMake(14, self.bounds.size.height - 4, MAX(0, w), 3);
}

- (void)refresh {
    BOOL pl = [self.player isPlaying];
    [self.playB setImage:[UIImage systemImageNamed:pl ? @"pause.fill" : @"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    self.stateLabel.text = pl ? @"Playing" : @"Paused";
    [self setNeedsLayout];
}

- (void)togglePlay {
    if ([self.player isPlaying]) [self.player pausePlayback]; else [self.player resume];
    [self refresh];
}

- (void)toBackground { self.picture.player = nil; }   // so the sound keeps going when the phone locks
- (void)toForeground { self.picture.player = self.player.keptPlayer; }

/// A song started in the Library: the video steps aside.
- (void)musicStarted {
    if (VGMusicPlayer.shared.playing) [self closeNow];
}

- (void)teardown {
    [self.timer invalidate]; self.timer = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    self.picture.player = nil;
    if (gMiniBar == self) gMiniBar = nil;
}

- (void)closeNow {
    VGPlayerViewController *p = self.player;
    [self teardown];
    p.minimized = NO;
    [p shutDown];
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; self.transform = CGAffineTransformMakeTranslation(0, 20); } completion:^(BOOL f) { [self removeFromSuperview]; }];
}

/// Tap the bar: the full player comes back and the video carries on from the same second.
- (void)expand {
    VGPlayerViewController *p = self.player;
    UIViewController *host = [VGPlayerViewController hostForRestore];
    if (!host) return;
    [self teardown];
    p.minimized = NO;
    if (p.videoView.playerLayer.player != p.keptPlayer) p.videoView.playerLayer.player = p.keptPlayer;
    p.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:p animated:YES completion:^{ if (p.keptPlayer.rate == 0 && p.keptPlayer.timeControlStatus == AVPlayerTimeControlStatusPaused) { /* stays as the viewer left it */ } }];
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; } completion:^(BOOL f) { [self removeFromSuperview]; }];
}

@end
