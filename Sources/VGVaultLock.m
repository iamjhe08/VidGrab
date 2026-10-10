#import "VGVaultLock.h"
#import "VGTheme.h"
#import "VGActions.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

static NSString *const kMethodKey = @"vgVaultLock";   // "both", "passcode" or "bio"
static NSString *const kService = @"com.t4mag0.vidgrab.vault";
static const NSUInteger kDigits = 6;


#pragma mark - First-time warning

static NSString *const kWarnedKey = @"vgVaultWarned";

/// The one-time heads-up shown when the vault is first set up. OK works after a 7 second wait.
@interface VGVaultWarning : UIViewController
@property (nonatomic, copy) void (^finished)(void);
@property (nonatomic, strong) UIButton *ok;
@property (nonatomic, strong) UILabel *count;
@property (nonatomic, strong) UIView *ringBox;
@property (nonatomic, strong) CAShapeLayer *ring;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) NSInteger left;
@end

@implementation VGVaultWarning

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    self.left = 7;

    UIView *card = [UIView new];
    card.backgroundColor = VGSurface;
    card.layer.cornerRadius = 28;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1;
    card.layer.borderColor = VGStroke.CGColor;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.45;
    card.layer.shadowRadius = 30;
    card.layer.shadowOffset = CGSizeMake(0, 12);
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    UIView *badge = [UIView new];
    badge.backgroundColor = [VGAccent colorWithAlphaComponent:0.16];
    badge.layer.cornerRadius = 30;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.shield.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold]]];
    icon.tintColor = VGAccent;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:60], [badge.heightAnchor constraintEqualToConstant:60],
        [icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor], [icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor]]];
    UIView *badgeRow = [UIView new];
    [badgeRow addSubview:badge];
    [badge.centerXAnchor constraintEqualToAnchor:badgeRow.centerXAnchor].active = YES;
    [badge.topAnchor constraintEqualToAnchor:badgeRow.topAnchor].active = YES;
    [badge.bottomAnchor constraintEqualToAnchor:badgeRow.bottomAnchor].active = YES;

    UILabel *title = [UILabel new];
    title.text = @"Private Vault 2.0\nWarning!";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 0;

    UIView *line = [UIView new];
    line.backgroundColor = VGStroke;
    [line.heightAnchor constraintEqualToConstant:1].active = YES;

    UILabel *lead = [UILabel new];
    lead.text = @"This feature was made for privacy.";
    lead.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    lead.textColor = UIColor.whiteColor;
    lead.textAlignment = NSTextAlignmentCenter;
    lead.numberOfLines = 0;
    UILabel *body = [UILabel new];
    body.text = @"What you use that privacy for is between you, your phone, and your search history.";
    body.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    body.textColor = [UIColor colorWithWhite:1 alpha:0.68];
    body.textAlignment = NSTextAlignmentCenter;
    body.numberOfLines = 0;

    self.ok = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.ok setTitle:@"OK" forState:UIControlStateNormal];
    self.ok.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.ok.layer.cornerRadius = 25;
    self.ok.layer.cornerCurve = kCACornerCurveContinuous;
    [self.ok addTarget:self action:@selector(okTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.ok.heightAnchor constraintEqualToConstant:50].active = YES;

    // A thin ring empties over the 7 seconds, with the seconds left inside it.
    self.ringBox = [UIView new];
    self.ringBox.translatesAutoresizingMaskIntoConstraints = NO;
    [self.ringBox.widthAnchor constraintEqualToConstant:46].active = YES;
    [self.ringBox.heightAnchor constraintEqualToConstant:46].active = YES;
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(23, 23) radius:20 startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
    CAShapeLayer *track = [CAShapeLayer layer];
    track.path = path.CGPath; track.fillColor = nil; track.lineWidth = 3;
    track.strokeColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    self.ring = [CAShapeLayer layer];
    self.ring.path = path.CGPath; self.ring.fillColor = nil; self.ring.lineWidth = 3; self.ring.lineCap = kCALineCapRound;
    self.ring.strokeColor = VGAccent.CGColor;
    [self.ringBox.layer addSublayer:track];
    [self.ringBox.layer addSublayer:self.ring];
    self.count = [UILabel new];
    self.count.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightSemibold];
    self.count.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    self.count.textAlignment = NSTextAlignmentCenter;
    self.count.translatesAutoresizingMaskIntoConstraints = NO;
    [self.ringBox addSubview:self.count];
    [NSLayoutConstraint activateConstraints:@[
        [self.count.centerXAnchor constraintEqualToAnchor:self.ringBox.centerXAnchor], [self.count.centerYAnchor constraintEqualToAnchor:self.ringBox.centerYAnchor]]];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.ok, self.ringBox]];
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[badgeRow, title, line, lead, body, row]];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 10;
    col.alignment = UIStackViewAlignmentFill;
    [col setCustomSpacing:16 afterView:badgeRow];
    [col setCustomSpacing:14 afterView:title];
    [col setCustomSpacing:14 afterView:line];
    [col setCustomSpacing:22 afterView:body];
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:col];

    NSLayoutConstraint *fill = [card.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-48];
    fill.priority = 750;
    [NSLayoutConstraint activateConstraints:@[
        fill,
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.widthAnchor constraintLessThanOrEqualToConstant:360],
        [col.topAnchor constraintEqualToAnchor:card.topAnchor constant:28], [col.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-22],
        [col.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24], [col.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24]]];

    [self refresh];
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    a.fromValue = @1; a.toValue = @0; a.duration = 7; a.fillMode = kCAFillModeForwards; a.removedOnCompletion = NO;
    [self.ring addAnimation:a forKey:@"empty"];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tickDown) userInfo:nil repeats:YES];
}

- (void)refresh {
    BOOL ready = self.left <= 0;
    self.ok.enabled = ready;
    self.ok.backgroundColor = ready ? VGAccent : [UIColor colorWithWhite:1 alpha:0.10];
    [self.ok setTitleColor:ready ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.38] forState:UIControlStateNormal];
    self.count.text = ready ? @"" : [NSString stringWithFormat:@"%ld", (long)self.left];
    self.ringBox.hidden = ready;
}

- (void)tickDown {
    self.left--;
    [self refresh];
    if (self.left <= 0) [self.timer invalidate];
}

- (void)okTapped {
    if (self.left > 0) return;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kWarnedKey];
    void (^fin)(void) = self.finished;
    [self dismissViewControllerAnimated:YES completion:^{ if (fin) fin(); }];
}

- (void)dealloc { [self.timer invalidate]; }

@end


#pragma mark - Turn-off confirmation

/// Asks before the vault lock is switched off.
@interface VGVaultConfirm : UIViewController
@property (nonatomic, copy) void (^decided)(BOOL turnOff);
@end

@implementation VGVaultConfirm

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    UIColor *red = [UIColor colorWithRed:1.0 green:0.27 blue:0.23 alpha:1];

    UIView *card = [UIView new];
    card.backgroundColor = VGSurface;
    card.layer.cornerRadius = 28;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1;
    card.layer.borderColor = VGStroke.CGColor;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.45;
    card.layer.shadowRadius = 30;
    card.layer.shadowOffset = CGSizeMake(0, 12);
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    UIView *badge = [UIView new];
    badge.backgroundColor = [red colorWithAlphaComponent:0.15];
    badge.layer.cornerRadius = 30;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.open.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:25 weight:UIImageSymbolWeightSemibold]]];
    icon.tintColor = red;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:60], [badge.heightAnchor constraintEqualToConstant:60],
        [icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor], [icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor]]];
    UIView *badgeRow = [UIView new];
    [badgeRow addSubview:badge];
    [badge.centerXAnchor constraintEqualToAnchor:badgeRow.centerXAnchor].active = YES;
    [badge.topAnchor constraintEqualToAnchor:badgeRow.topAnchor].active = YES;
    [badge.bottomAnchor constraintEqualToAnchor:badgeRow.bottomAnchor].active = YES;

    UILabel *title = [UILabel new];
    title.text = @"Turn Off Protection";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    UIView *line = [UIView new];
    line.backgroundColor = VGStroke;
    [line.heightAnchor constraintEqualToConstant:1].active = YES;
    UILabel *body = [UILabel new];
    body.text = @"Turning off Passcode and Face ID protection will disable biometric and passcode security for this private vault. Anyone with access to your device may be able to access its contents.";
    body.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    body.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    body.textAlignment = NSTextAlignmentCenter;
    body.numberOfLines = 0;
    UILabel *ask = [UILabel new];
    ask.text = @"Are you sure you want to continue?";
    ask.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    ask.textColor = UIColor.whiteColor;
    ask.textAlignment = NSTextAlignmentCenter;
    ask.numberOfLines = 0;

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    cancel.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [cancel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    cancel.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    UIButton *off = [UIButton buttonWithType:UIButtonTypeCustom];
    [off setTitle:@"Turn Off" forState:UIControlStateNormal];
    off.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [off setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    off.backgroundColor = red;
    for (UIButton *b in @[cancel, off]) {
        b.layer.cornerRadius = 25;
        b.layer.cornerCurve = kCACornerCurveContinuous;
        [b.heightAnchor constraintEqualToConstant:50].active = YES;
    }
    [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [off addTarget:self action:@selector(offTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[cancel, off]];
    row.spacing = 12;
    row.distribution = UIStackViewDistributionFillEqually;

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[badgeRow, title, line, body, ask, row]];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 10;
    [col setCustomSpacing:16 afterView:badgeRow];
    [col setCustomSpacing:14 afterView:title];
    [col setCustomSpacing:14 afterView:line];
    [col setCustomSpacing:14 afterView:body];
    [col setCustomSpacing:22 afterView:ask];
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:col];
    NSLayoutConstraint *fill = [card.widthAnchor constraintEqualToAnchor:self.view.widthAnchor constant:-48];
    fill.priority = 750;
    [NSLayoutConstraint activateConstraints:@[
        fill,
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.widthAnchor constraintLessThanOrEqualToConstant:360],
        [col.topAnchor constraintEqualToAnchor:card.topAnchor constant:28], [col.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-22],
        [col.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24], [col.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24]]];
}

- (void)cancelTapped { [self finish:NO]; }
- (void)offTapped { [self finish:YES]; }

- (void)finish:(BOOL)yes {
    void (^d)(BOOL) = self.decided;
    [self dismissViewControllerAnimated:YES completion:^{ if (d) d(yes); }];
}

@end

#pragma mark - Passcode screen

typedef NS_ENUM(NSInteger, VGPadMode) { VGPadUnlock, VGPadCreate, VGPadConfirm };

@interface VGPasscodeViewController : UIViewController
@property (nonatomic) VGPadMode mode;
@property (nonatomic) BOOL showBio;
@property (nonatomic) BOOL autoBio;
@property (nonatomic, copy) NSString *createTitle;
@property (nonatomic, copy) BOOL (^check)(NSString *code);           // unlock: is this the right code?
@property (nonatomic, copy) void (^finished)(BOOL ok, NSString *code); // called after the screen closes
@property (nonatomic, copy) void (^onBio)(void);
@property (nonatomic, copy) void (^onForgot)(void);
- (void)closeWith:(BOOL)ok code:(NSString *)code;
- (void)switchToCreate:(NSString *)title;
@end

@interface VGPasscodeViewController ()
@property (nonatomic, strong) UILabel *titleLabel, *subtitleLabel;
@property (nonatomic, strong) NSMutableArray<UIView *> *dots;
@property (nonatomic, strong) UIStackView *dotRow;
@property (nonatomic, strong) NSMutableString *entered;
@property (nonatomic, copy) NSString *firstEntry;
@property (nonatomic, strong) UIButton *forgotButton, *bioButton;
@property (nonatomic, strong) NSMutableArray<UIButton *> *keys;
@property (nonatomic) NSInteger wrong;
@property (nonatomic) BOOL locked, closed, didAutoBio;
@end

@implementation VGPasscodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VGBackground;
    self.entered = [NSMutableString string];
    self.dots = [NSMutableArray array];
    self.keys = [NSMutableArray array];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    cancel.titleLabel.font = VGFont(17, UIFontWeightSemibold);
    cancel.tintColor = VGText;
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cancel];

    UIImageView *lock = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"
                                                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightBold]]];
    lock.tintColor = VGAccent;
    lock.contentMode = UIViewContentModeCenter;

    self.titleLabel = [UILabel new];
    self.titleLabel.font = VGRounded(24, UIFontWeightHeavy);
    self.titleLabel.textColor = VGText;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.font = VGFont(15, UIFontWeightMedium);
    self.subtitleLabel.textColor = VGSecondary;
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 0;

    self.dotRow = [UIStackView new];
    self.dotRow.spacing = 18;
    for (NSUInteger i = 0; i < kDigits; i++) {
        UIView *d = [UIView new];
        d.layer.cornerRadius = 7;
        d.layer.borderWidth = 2;
        d.layer.borderColor = VGSecondary.CGColor;
        [d.widthAnchor constraintEqualToConstant:14].active = YES;
        [d.heightAnchor constraintEqualToConstant:14].active = YES;
        [self.dots addObject:d];
        [self.dotRow addArrangedSubview:d];
    }

    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[lock, self.titleLabel, self.subtitleLabel, self.dotRow]];
    head.axis = UILayoutConstraintAxisVertical;
    head.alignment = UIStackViewAlignmentCenter;
    head.spacing = 12;
    [head setCustomSpacing:28 afterView:self.subtitleLabel];
    head.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:head];

    // Number pad: 1-9, then [Face ID] 0 [delete].
    UIStackView *pad = [UIStackView new];
    pad.axis = UILayoutConstraintAxisVertical;
    pad.spacing = 16;
    pad.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *rows = @[@[@"1", @"2", @"3"], @[@"4", @"5", @"6"], @[@"7", @"8", @"9"], @[@"bio", @"0", @"del"]];
    for (NSArray *r in rows) {
        UIStackView *row = [UIStackView new];
        row.spacing = 26;
        for (NSString *k in r) [row addArrangedSubview:[self keyFor:k]];
        [pad addArrangedSubview:row];
    }
    [self.view addSubview:pad];

    self.forgotButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.forgotButton setTitle:@"Forgot passcode?" forState:UIControlStateNormal];
    self.forgotButton.titleLabel.font = VGFont(15, UIFontWeightSemibold);
    self.forgotButton.tintColor = VGAccentSoft;
    self.forgotButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.forgotButton addTarget:self action:@selector(forgotTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.forgotButton];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [cancel.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [cancel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [cancel.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [head.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [head.leadingAnchor constraintGreaterThanOrEqualToAnchor:g.leadingAnchor constant:24],
        [head.trailingAnchor constraintLessThanOrEqualToAnchor:g.trailingAnchor constant:-24],
        [head.bottomAnchor constraintEqualToAnchor:pad.topAnchor constant:-44],
        [head.topAnchor constraintGreaterThanOrEqualToAnchor:cancel.bottomAnchor constant:8],
        [pad.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [pad.bottomAnchor constraintLessThanOrEqualToAnchor:self.forgotButton.topAnchor constant:-12],
        [self.forgotButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.forgotButton.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],
        [self.forgotButton.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
    // Keep the lock, dots and keypad together in the middle of the screen, like the iPhone's own passcode screen.
    UILayoutGuide *group = [UILayoutGuide new];
    [self.view addLayoutGuide:group];
    NSLayoutConstraint *mid = [group.centerYAnchor constraintEqualToAnchor:g.centerYAnchor constant:-6];
    mid.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [group.topAnchor constraintEqualToAnchor:head.topAnchor],
        [group.bottomAnchor constraintEqualToAnchor:pad.bottomAnchor],
        mid,
    ]];
    [self refreshText];
}

- (UIButton *)keyFor:(NSString *)k {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b.widthAnchor constraintEqualToConstant:76].active = YES;
    [b.heightAnchor constraintEqualToConstant:76].active = YES;
    b.layer.cornerRadius = 38;
    b.tintColor = VGText;
    if ([k isEqualToString:@"del"]) {
        [b setImage:[UIImage systemImageNamed:@"delete.left" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
        b.accessibilityLabel = @"Delete";
        [b addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
    } else if ([k isEqualToString:@"bio"]) {
        NSString *name = [VGVaultLock biometryName];
        [b setImage:[UIImage systemImageNamed:[name isEqualToString:@"Touch ID"] ? @"touchid" : @"faceid"
                            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
        b.tintColor = VGAccent;
        b.accessibilityLabel = name ? [NSString stringWithFormat:@"Use %@", name] : nil;
        [b addTarget:self action:@selector(bioTapped) forControlEvents:UIControlEventTouchUpInside];
        self.bioButton = b;
    } else {
        b.backgroundColor = VGSurface2;
        [b setTitle:k forState:UIControlStateNormal];
        b.titleLabel.font = VGRounded(32, UIFontWeightMedium);
        b.tag = k.integerValue;
        [b addTarget:self action:@selector(digitTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.keys addObject:b];
    }
    return b;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.autoBio && !self.didAutoBio && self.mode == VGPadUnlock && self.onBio) {
        self.didAutoBio = YES;
        self.onBio();
    }
}

- (void)refreshText {
    BOOL unlock = self.mode == VGPadUnlock;
    BOOL bio = unlock && self.showBio;
    self.bioButton.alpha = bio ? 1 : 0;              // hidden would collapse the row and push 0 to the side
    self.bioButton.userInteractionEnabled = bio;
    self.bioButton.isAccessibilityElement = bio;
    self.forgotButton.hidden = !(unlock && self.onForgot);
    if (unlock) {
        self.titleLabel.text = @"Private Vault 2.0";
        if (!self.locked) self.subtitleLabel.text = self.showBio ? [NSString stringWithFormat:@"Enter your passcode or use %@", [VGVaultLock biometryName]]
                                                                 : @"Enter your vault passcode";
    } else if (self.mode == VGPadCreate) {
        self.titleLabel.text = self.createTitle ?: @"Create a passcode";
        if (!self.subtitleLabel.text.length || ![self.subtitleLabel.text hasPrefix:@"Those"])
            self.subtitleLabel.text = @"Pick 6 numbers you'll remember";
    } else {
        self.titleLabel.text = @"Enter it again";
        self.subtitleLabel.text = @"Type the same 6 numbers to confirm";
    }
    for (NSUInteger i = 0; i < kDigits; i++) {
        BOOL on = i < self.entered.length;
        self.dots[i].backgroundColor = on ? VGAccent : UIColor.clearColor;
        self.dots[i].layer.borderColor = (on ? VGAccent : VGSecondary).CGColor;
    }
}

- (void)digitTapped:(UIButton *)b {
    if (self.locked || self.entered.length >= kDigits) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self.entered appendFormat:@"%ld", (long)b.tag];
    [self refreshText];
    if (self.entered.length == kDigits)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self complete]; });
}

- (void)deleteTapped {
    if (self.entered.length) [self.entered deleteCharactersInRange:NSMakeRange(self.entered.length - 1, 1)];
    [self refreshText];
}

- (void)bioTapped { if (self.onBio) self.onBio(); }
- (void)forgotTapped { if (self.onForgot) self.onForgot(); }
- (void)cancelTapped { [self closeWith:NO code:nil]; }

- (void)complete {
    NSString *code = [self.entered copy];
    [self.entered setString:@""];
    if (self.mode == VGPadUnlock) {
        if (self.check && self.check(code)) { [self closeWith:YES code:code]; return; }
        self.wrong++;
        [self shake];
        if (self.wrong >= 5) {
            self.locked = YES;
            self.subtitleLabel.text = @"Too many tries. Wait 30 seconds.";
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.locked = NO; self.wrong = 0; [self refreshText];
            });
        } else {
            self.subtitleLabel.text = @"Wrong passcode. Try again.";
        }
    } else if (self.mode == VGPadCreate) {
        self.firstEntry = code;
        self.mode = VGPadConfirm;
    } else {
        if ([code isEqualToString:self.firstEntry]) { [self closeWith:YES code:code]; return; }
        [self shake];
        self.mode = VGPadCreate;
        self.subtitleLabel.text = @"Those didn't match. Try again.";
    }
    [self refreshText];
}

- (void)shake {
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    a.values = @[@0, @-14, @14, @-10, @10, @-5, @5, @0];
    a.duration = 0.45;
    [self.dotRow.layer addAnimation:a forKey:@"shake"];
}

- (void)switchToCreate:(NSString *)title {
    self.createTitle = title;
    self.mode = VGPadCreate;
    self.subtitleLabel.text = @"";
    [self.entered setString:@""];
    [self refreshText];
}

- (void)closeWith:(BOOL)ok code:(NSString *)code {
    if (self.closed) return;
    self.closed = YES;
    void (^f)(BOOL, NSString *) = self.finished;
    [self dismissViewControllerAnimated:YES completion:^{ if (f) f(ok, code); }];
}

@end

#pragma mark - Lock

@implementation VGVaultLock

#pragma mark Stored passcode

// Saved as a salt plus a slow hash, never the passcode itself. Kept in the keychain,
// or in a protected file when the keychain isn't available to this install.
+ (NSString *)fallbackPath {
    NSURL *dir = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir URLByAppendingPathComponent:@".vaultlock"].path;
}

+ (NSDictionary *)keychainQuery {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: kService,
             (__bridge id)kSecAttrAccount: @"passcode"};
}

+ (NSData *)loadRecord {
    NSMutableDictionary *q = [[self keychainQuery] mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) == errSecSuccess && out) return (__bridge_transfer NSData *)out;
    return [NSData dataWithContentsOfFile:[self fallbackPath]];
}

+ (void)deleteRecord {
    SecItemDelete((__bridge CFDictionaryRef)[self keychainQuery]);
    [NSFileManager.defaultManager removeItemAtPath:[self fallbackPath] error:nil];
}

+ (void)saveRecord:(NSData *)record {
    [self deleteRecord];
    NSMutableDictionary *q = [[self keychainQuery] mutableCopy];
    q[(__bridge id)kSecValueData] = record;
    q[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    if (SecItemAdd((__bridge CFDictionaryRef)q, NULL) == errSecSuccess) return;
    [record writeToFile:[self fallbackPath] options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:nil];
}

+ (NSData *)hash:(NSString *)code salt:(NSData *)salt {
    NSData *pw = [code dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *out = [NSMutableData dataWithLength:32];
    CCKeyDerivationPBKDF(kCCPBKDF2, pw.bytes, pw.length, salt.bytes, salt.length, kCCPRFHmacAlgSHA256, 60000, out.mutableBytes, out.length);
    return out;
}

+ (void)setPasscode:(NSString *)code {
    NSMutableData *salt = [NSMutableData dataWithLength:16];
    if (SecRandomCopyBytes(kSecRandomDefault, 16, salt.mutableBytes) != errSecSuccess) arc4random_buf(salt.mutableBytes, 16);
    NSMutableData *rec = [salt mutableCopy];
    [rec appendData:[self hash:code salt:salt]];
    [self saveRecord:rec];
}

+ (BOOL)checkPasscode:(NSString *)code {
    NSData *rec = [self loadRecord];
    if (rec.length != 48) return NO;
    NSData *salt = [rec subdataWithRange:NSMakeRange(0, 16)];
    return [[rec subdataWithRange:NSMakeRange(16, 32)] isEqualToData:[self hash:code salt:salt]];
}

#pragma mark State

+ (NSString *)method { return [NSUserDefaults.standardUserDefaults stringForKey:kMethodKey]; }
+ (void)setMethod:(NSString *)m { [NSUserDefaults.standardUserDefaults setObject:m forKey:kMethodKey]; }

+ (BOOL)usesPasscode {
    NSString *m = [self method];
    return ([m isEqualToString:@"both"] || [m isEqualToString:@"passcode"]) && [self loadRecord].length == 48;
}

+ (BOOL)usesBio {
    NSString *m = [self method];
    return [m isEqualToString:@"both"] || [m isEqualToString:@"bio"];
}

+ (BOOL)isSetUp {
    return [[self method] isEqualToString:@"bio"] || [[self method] isEqualToString:@"none"] || [self usesPasscode];
}

+ (NSString *)biometryName {
    LAContext *c = [LAContext new];
    if (![c canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:nil]) return nil;
    if (c.biometryType == LABiometryTypeFaceID) return @"Face ID";
    if (c.biometryType == LABiometryTypeTouchID) return @"Touch ID";
    return nil;
}

+ (NSString *)bioLabel { return [self biometryName] ?: @"Face ID"; }

+ (NSString *)methodDescription {
    if (![self isSetUp]) return @"Not set up";
    NSString *m = [self method];
    if ([m isEqualToString:@"none"]) return @"Off";
    if ([m isEqualToString:@"both"]) return [NSString stringWithFormat:@"Passcode and %@", [self bioLabel]];
    if ([m isEqualToString:@"passcode"]) return @"Passcode";
    return [self bioLabel];
}

#pragma mark Helpers

+ (UIViewController *)top:(UIViewController *)vc {
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc;
}

// Face ID / Touch ID. With allowPhonePasscode, iOS offers the iPhone passcode if Face ID fails.
+ (void)bio:(NSString *)reason allowPhonePasscode:(BOOL)phone completion:(void (^)(BOOL ok))done {
    LAContext *c = [LAContext new];
    c.localizedCancelTitle = @"Cancel";
    LAPolicy policy = phone ? LAPolicyDeviceOwnerAuthentication : LAPolicyDeviceOwnerAuthenticationWithBiometrics;
    if (!phone) c.localizedFallbackTitle = @"Use Passcode";
    if (![c canEvaluatePolicy:policy error:nil]) { done(NO); return; }
    [c evaluatePolicy:policy localizedReason:reason reply:^(BOOL ok, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(ok); });
    }];
}

+ (VGPasscodeViewController *)padWithMode:(VGPadMode)mode {
    VGPasscodeViewController *p = [VGPasscodeViewController new];
    p.mode = mode;
    p.modalPresentationStyle = UIModalPresentationFullScreen;
    p.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    return p;
}

+ (void)createPasscodeFrom:(UIViewController *)vc title:(NSString *)title completion:(void (^)(NSString *code))done {
    VGPasscodeViewController *p = [self padWithMode:VGPadCreate];
    p.createTitle = title;
    p.finished = ^(BOOL ok, NSString *code) { done(ok ? code : nil); };
    [[self top:vc] presentViewController:p animated:YES completion:nil];
}

#pragma mark Setup

+ (void)warnFirstTimeFrom:(UIViewController *)vc then:(void (^)(void))next {
    if ([NSUserDefaults.standardUserDefaults boolForKey:kWarnedKey]) { next(); return; }
    VGVaultWarning *w = [VGVaultWarning new];
    w.modalPresentationStyle = UIModalPresentationOverFullScreen;
    w.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    w.finished = next;
    [[self top:vc] presentViewController:w animated:YES completion:nil];
}

+ (void)setupFrom:(UIViewController *)vc completion:(void (^)(BOOL ok))done {
    NSString *bio = [self biometryName];
    void (^passcodeOnly)(void) = ^{
        [self createPasscodeFrom:vc title:@"Create a vault passcode" completion:^(NSString *code) {
            if (!code) { done(NO); return; }
            [self setPasscode:code];
            [self setMethod:@"passcode"];
            done(YES);
        }];
    };
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Lock your vault"
                                                               message:bio ? [NSString stringWithFormat:@"With both, either one opens it. If %@ doesn't work, use your passcode, and the other way around. You can also turn the lock off.", bio]
                                                                           : @"Choose how to protect your Private Vault 2.0. You can also turn the lock off."
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    if (bio) {
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Passcode and %@ (best)", bio] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [self createPasscodeFrom:vc title:@"Create a vault passcode" completion:^(NSString *code) {
                if (!code) { done(NO); return; }
                [self setPasscode:code];
                [self bio:[NSString stringWithFormat:@"Turn on %@ for your Private Vault 2.0", bio] allowPhonePasscode:NO completion:^(BOOL ok) {
                    [self setMethod:ok ? @"both" : @"passcode"];
                    if (!ok) [VGActions alert:[NSString stringWithFormat:@"%@ is off for now", bio]
                                      message:[NSString stringWithFormat:@"Your passcode is set. You can turn on %@ later in Settings > Private Vault 2.0.", bio]
                                         from:[self top:vc]];
                    done(YES);
                }];
            }];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Passcode only" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { passcodeOnly(); }]];
    if (bio) {
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ only", bio] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [self bio:[NSString stringWithFormat:@"Turn on %@ for your Private Vault 2.0", bio] allowPhonePasscode:NO completion:^(BOOL ok) {
                if (!ok) { done(NO); return; }
                [self deleteRecord];
                [self setMethod:@"bio"];
                done(YES);
            }];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"None" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        VGVaultConfirm *c = [VGVaultConfirm new];
        c.modalPresentationStyle = UIModalPresentationOverFullScreen;
        c.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        c.decided = ^(BOOL turnOff) {
            if (!turnOff) { done(NO); return; }
            [self deleteRecord];
            [self setMethod:@"none"];
            done(YES);
        };
        [[self top:vc] presentViewController:c animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { done(NO); }]];
    UIViewController *host = [self top:vc];
    a.popoverPresentationController.sourceView = host.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds), CGRectGetMidY(host.view.bounds), 1, 1);
    [host presentViewController:a animated:YES completion:nil];
}

#pragma mark Unlock

+ (void)unlockFrom:(UIViewController *)vc completion:(void (^)(BOOL ok))done {
    if (![self isSetUp]) { [self setupFrom:vc completion:done]; return; }
    NSString *bio = [self biometryName];
    if ([[self method] isEqualToString:@"none"]) { done(YES); return; }   // the lock is turned off

    if (![self usesPasscode]) {
        // Face ID only. iOS offers the iPhone passcode if Face ID fails.
        [self bio:@"Unlock your Private Vault 2.0" allowPhonePasscode:YES completion:done];
        return;
    }

    VGPasscodeViewController *p = [self padWithMode:VGPadUnlock];
    __weak VGPasscodeViewController *wp = p;
    p.check = ^BOOL(NSString *code) { return [VGVaultLock checkPasscode:code]; };
    if ([self usesBio] && bio) {
        p.showBio = YES;
        p.autoBio = YES;
        p.onBio = ^{
            [VGVaultLock bio:@"Unlock your Private Vault 2.0" allowPhonePasscode:NO completion:^(BOOL ok) {
                if (ok) [wp closeWith:YES code:nil];
            }];
        };
    }
    p.onForgot = ^{
        // Prove it's you another way, then pick a new passcode.
        BOOL viaBio = [VGVaultLock usesBio] && bio;
        NSString *reason = @"Confirm it's you to reset your vault passcode";
        [VGVaultLock bio:reason allowPhonePasscode:!viaBio completion:^(BOOL ok) {
            if (!ok && viaBio) {
                [VGVaultLock bio:reason allowPhonePasscode:YES completion:^(BOOL ok2) { if (ok2) [wp switchToCreate:@"Create a new passcode"]; }];
                return;
            }
            if (ok) [wp switchToCreate:@"Create a new passcode"];
        }];
    };
    // After a reset, the screen collects a new code and closes with it.
    p.finished = ^(BOOL ok, NSString *code) {
        if (ok && code && ![VGVaultLock checkPasscode:code]) [VGVaultLock setPasscode:code];
        done(ok);
    };
    [[self top:vc] presentViewController:p animated:YES completion:nil];
}

#pragma mark Settings

+ (void)changeLockFrom:(UIViewController *)vc completion:(void (^)(void))done {
    void (^pick)(void) = ^{
        NSString *old = [self method];
        NSData *oldRec = [self loadRecord];
        [self setupFrom:vc completion:^(BOOL ok) {
            if (!ok) {   // cancelled: keep the lock you had
                if (old) [self setMethod:old];
                if (oldRec.length == 48 && [self loadRecord].length != 48) [self saveRecord:oldRec];
            }
            done();
        }];
    };
    if (![self isSetUp]) { pick(); return; }
    [self unlockFrom:vc completion:^(BOOL ok) { if (ok) pick(); }];
}

+ (void)changePasscodeFrom:(UIViewController *)vc completion:(void (^)(void))done {
    [self unlockFrom:vc completion:^(BOOL ok) {
        if (!ok) return;
        [self createPasscodeFrom:vc title:@"Create a new passcode" completion:^(NSString *code) {
            if (code) {
                [self setPasscode:code];
                [VGActions toast:@"Passcode changed" icon:@"checkmark.circle.fill" in:vc.view.window ?: vc.view];
            }
            done();
        }];
    }];
}

@end
