#import "VGHomeViewController.h"
#import "VGEngine.h"
#import "VGTheme.h"
#import "VGActions.h"
#import "VGQualityCell.h"
#import "VGCrash.h"
#import "VGBlocker.h"
#import "VGCache.h"
#import "VGSettingsViewController.h"

#pragma mark - Home

typedef NS_ENUM(NSInteger, VGStep) { VGStepWelcome, VGStepLoaded, VGStepDownloading, VGStepDone };

@interface VGHomeViewController () <UITextFieldDelegate, UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;

@property (nonatomic, strong) UIView *welcomeHero;
@property (nonatomic, strong) UIView *videoHero;
@property (nonatomic, strong) UIImageView *heroImage;
@property (nonatomic, strong) UILabel *siteBadge, *heroTitle, *heroMeta;

@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *pasteButton, *findButton, *clearButton, *clearRowButton;
@property (nonatomic) NSUInteger lookupID;
@property (nonatomic, strong) UIView *linkSection, *chipsSection;

@property (nonatomic, strong) UIView *qualitySection;
@property (nonatomic, strong) UICollectionView *qualityList;
@property (nonatomic, strong) UIButton *downloadButton;
@property (nonatomic, strong) UILabel *downloadCaption;

@property (nonatomic, strong) UIView *progressSection;
@property (nonatomic, strong) UILabel *stageLabel, *percentLabel, *detailLabel;
@property (nonatomic, strong) VGProgressBar *bar;

@property (nonatomic, strong) UIView *doneSection;
@property (nonatomic, strong) UILabel *doneSub;
@property (nonatomic, strong) UIButton *photosButton, *shareButton;

@property (nonatomic, strong) VGVideo *video;
@property (nonatomic, strong) VGItem *item;
@property (nonatomic, weak) VGTask *task;   // the download this screen is showing
@property (nonatomic) NSInteger selected;
@property (nonatomic) VGStep step;
@end

@implementation VGHomeViewController

#pragma mark Helpers

- (UILabel *)label:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines {
    UILabel *l = [UILabel new];
    l.font = font;
    l.textColor = color;
    l.numberOfLines = lines;
    return l;
}

- (UIView *)padded:(UIView *)content top:(CGFloat)top bottom:(CGFloat)bottom {
    UIView *wrap = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:top],
        [content.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-bottom],
        [content.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-16],
    ]];
    return wrap;
}

- (UIView *)card:(UIView *)content {
    UIView *card = [UIView new];
    card.backgroundColor = VGSurface;
    card.layer.cornerRadius = 14;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderColor = VGStroke.CGColor;
    card.layer.borderWidth = 1;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
    ]];
    return card;
}

- (UIStackView *)vstack:(NSArray *)views spacing:(CGFloat)spacing {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:views];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = spacing;
    return s;
}

#pragma mark Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [VGCrash breadcrumb:@"home screen"];
    self.view.backgroundColor = VGBackground;

    // Header
    UIView *header = [UIView new];
    header.backgroundColor = VGBackground;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *mark = VGWordmark(26);
    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    [gear setImage:[UIImage systemImageNamed:@"gearshape.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    gear.tintColor = VGText;
    gear.accessibilityLabel = @"Settings";
    [gear addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *v in @[mark, gear]) { v.translatesAutoresizingMaskIntoConstraints = NO; [header addSubview:v]; }

    self.scroll = [UIScrollView new];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.alwaysBounceVertical = YES;
    self.scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scroll];
    [self.view addSubview:header];

    self.stack = [self vstack:@[] spacing:0];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scroll addSubview:self.stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.bottomAnchor constraintEqualToAnchor:safe.topAnchor constant:52],
        [mark.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [mark.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12],
        [gear.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-10],
        [gear.centerYAnchor constraintEqualToAnchor:mark.centerYAnchor],
        [gear.widthAnchor constraintEqualToConstant:44],
        [gear.heightAnchor constraintEqualToConstant:44],

        [self.scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.leadingAnchor],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.trailingAnchor],
    ]];

    [self buildWelcomeHero];
    [self buildVideoHero];
    [self buildLinkSection];
    [self buildChips];
    [self buildQuality];
    [self buildProgress];
    [self buildDone];
    [self setStep:VGStepWelcome animated:NO];
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSString *report = [VGCrash previousReport];
    if (!report) return;
    NSString *last = [VGCrash previousLastStep];
    [VGCrash clearPreviousReport];
    NSString *msg = @"Tap Copy details and send them to the developer so it can be fixed.";
    if ([last hasPrefix:@"adblock"])
        msg = @"It happened while setting up the ad blocker, so the ad blocker was turned off. You can turn it back on with the shield in Browse. Tap Copy details and send them to the developer.";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"VidGrab closed unexpectedly" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy details" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UIPasteboard.generalPasteboard.string = report;
        [VGActions toast:@"Crash details copied" icon:@"doc.on.doc.fill" in:self.view.window ?: self.view];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

#pragma mark Sections

- (void)buildWelcomeHero {
    UIView *hero = [UIView new];
    hero.clipsToBounds = YES;
    VGGradientView *glow = [VGGradientView new];
    glow.gradient.type = kCAGradientLayerRadial;
    glow.gradient.colors = @[(id)[VGAccent colorWithAlphaComponent:0.45].CGColor,
                             (id)[VGAccent2 colorWithAlphaComponent:0.15].CGColor,
                             (id)UIColor.clearColor.CGColor];
    glow.gradient.locations = @[@0, @0.45, @1];
    glow.gradient.startPoint = CGPointMake(0.85, 0.0);
    glow.gradient.endPoint = CGPointMake(-0.1, 1.2);
    glow.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:glow];

    UILabel *h1 = [self label:VGFont(38, UIFontWeightHeavy) color:VGText lines:0];
    h1.text = @"Grab any\nvideo.";
    UILabel *sub = [self label:VGFont(16, UIFontWeightRegular) color:VGSecondary lines:0];
    sub.text = @"Paste a link, pick the quality, and keep it on your iPhone.";
    UIStackView *s = [self vstack:@[h1, sub] spacing:10];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [glow.topAnchor constraintEqualToAnchor:hero.topAnchor],
        [glow.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor],
        [glow.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor],
        [glow.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor],
        [s.topAnchor constraintEqualToAnchor:hero.topAnchor constant:36],
        [s.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-20],
        [s.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:20],
        [s.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-20],
    ]];
    self.welcomeHero = hero;
    [self.stack addArrangedSubview:hero];
}

- (void)buildVideoHero {
    UIView *hero = [UIView new];
    self.heroImage = [UIImageView new];
    self.heroImage.contentMode = UIViewContentModeScaleAspectFill;
    self.heroImage.clipsToBounds = YES;
    self.heroImage.backgroundColor = VGSurface;
    self.heroImage.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:self.heroImage];

    VGGradientView *fade = [VGGradientView new];
    fade.gradient.colors = @[(id)UIColor.clearColor.CGColor, (id)[VGBackground colorWithAlphaComponent:0.55].CGColor, (id)VGBackground.CGColor];
    fade.gradient.locations = @[@0.25, @0.6, @1];
    fade.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:fade];

    self.siteBadge = [self label:VGFont(11, UIFontWeightHeavy) color:VGText lines:1];
    UIView *badgeWrap = [UIView new];
    badgeWrap.backgroundColor = VGAccent;
    badgeWrap.layer.cornerRadius = 4;
    self.siteBadge.translatesAutoresizingMaskIntoConstraints = NO;
    [badgeWrap addSubview:self.siteBadge];
    [NSLayoutConstraint activateConstraints:@[
        [self.siteBadge.topAnchor constraintEqualToAnchor:badgeWrap.topAnchor constant:3],
        [self.siteBadge.bottomAnchor constraintEqualToAnchor:badgeWrap.bottomAnchor constant:-3],
        [self.siteBadge.leadingAnchor constraintEqualToAnchor:badgeWrap.leadingAnchor constant:7],
        [self.siteBadge.trailingAnchor constraintEqualToAnchor:badgeWrap.trailingAnchor constant:-7],
    ]];
    UIStackView *badgeRow = [[UIStackView alloc] initWithArrangedSubviews:@[badgeWrap, [UIView new]]];

    self.heroTitle = [self label:VGFont(26, UIFontWeightHeavy) color:VGText lines:3];
    self.heroMeta = [self label:VGFont(14, UIFontWeightMedium) color:VGSecondary lines:1];
    UIStackView *s = [self vstack:@[badgeRow, self.heroTitle, self.heroMeta] spacing:8];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:s];

    [NSLayoutConstraint activateConstraints:@[
        [self.heroImage.topAnchor constraintEqualToAnchor:hero.topAnchor],
        [self.heroImage.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor],
        [self.heroImage.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor],
        [self.heroImage.heightAnchor constraintEqualToAnchor:self.heroImage.widthAnchor multiplier:9.0 / 16.0],
        [fade.topAnchor constraintEqualToAnchor:self.heroImage.topAnchor],
        [fade.bottomAnchor constraintEqualToAnchor:self.heroImage.bottomAnchor constant:1],
        [fade.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor],
        [fade.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor],
        [s.topAnchor constraintGreaterThanOrEqualToAnchor:self.heroImage.topAnchor constant:60],
        [s.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-4],
        [s.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:16],
        [s.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-16],
        [hero.bottomAnchor constraintGreaterThanOrEqualToAnchor:self.heroImage.bottomAnchor constant:40],
    ]];
    self.videoHero = hero;
    [self.stack addArrangedSubview:hero];
}

- (void)buildLinkSection {
    UIView *box = [UIView new];
    box.backgroundColor = VGSurface2;
    box.layer.cornerRadius = 12;
    box.layer.borderColor = VGStroke.CGColor;
    box.layer.borderWidth = 1;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"link"]];
    icon.tintColor = VGTertiary;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    self.field = [UITextField new];
    self.field.textColor = VGText;
    self.field.tintColor = VGAccent;
    self.field.font = VGFont(16, UIFontWeightRegular);
    self.field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Paste a video link"
                                                                       attributes:@{NSForegroundColorAttributeName: VGTertiary}];
    self.field.keyboardType = UIKeyboardTypeURL;
    self.field.keyboardAppearance = UIKeyboardAppearanceDark;
    self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.field.returnKeyType = UIReturnKeySearch;
    self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.field.delegate = self;
    self.field.clearButtonMode = UITextFieldViewModeNever;
    [self.field addTarget:self action:@selector(updateClear) forControlEvents:UIControlEventEditingChanged];

    self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold]]
                      forState:UIControlStateNormal];
    self.clearButton.tintColor = VGSecondary;
    self.clearButton.accessibilityLabel = @"Clear";
    [self.clearButton addTarget:self action:@selector(clearAll) forControlEvents:UIControlEventTouchUpInside];
    self.clearButton.hidden = YES;
    for (UIView *v in @[icon, self.field, self.clearButton]) { v.translatesAutoresizingMaskIntoConstraints = NO; [box addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [box.heightAnchor constraintEqualToConstant:54],
        [icon.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:14],
        [icon.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:20],
        [self.field.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [self.field.trailingAnchor constraintEqualToAnchor:self.clearButton.leadingAnchor constant:-2],
        [self.clearButton.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-4],
        [self.clearButton.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [self.clearButton.widthAnchor constraintEqualToConstant:40],
        [self.clearButton.heightAnchor constraintEqualToConstant:44],
        [self.field.topAnchor constraintEqualToAnchor:box.topAnchor],
        [self.field.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
    ]];

    self.pasteButton = VGPrimaryButton(@"Paste", @"doc.on.clipboard.fill");
    [self.pasteButton addTarget:self action:@selector(paste) forControlEvents:UIControlEventTouchUpInside];
    self.findButton = VGSecondaryButton(@"Find video", @"magnifyingglass");
    [self.findButton addTarget:self action:@selector(find) forControlEvents:UIControlEventTouchUpInside];
    // Clear sits between Paste and Find video: empties the link and removes the shown video.
    self.clearRowButton = VGSecondaryButton(@"Clear", @"xmark");
    UIButtonConfiguration *cc = self.clearRowButton.configuration;
    cc.contentInsets = NSDirectionalEdgeInsetsMake(14, 12, 14, 12);
    self.clearRowButton.configuration = cc;
    self.clearRowButton.accessibilityLabel = @"Clear link and video";
    [self.clearRowButton addTarget:self action:@selector(clearAll) forControlEvents:UIControlEventTouchUpInside];
    [self.clearRowButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.clearRowButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.pasteButton, self.clearRowButton, self.findButton]];
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFill;
    [self.pasteButton.widthAnchor constraintEqualToAnchor:self.findButton.widthAnchor].active = YES;

    self.linkSection = [self padded:[self vstack:@[box, row] spacing:12] top:12 bottom:8];
    [self.stack addArrangedSubview:self.linkSection];
}

- (void)buildChips {
    UILabel *h = [self label:VGFont(12, UIFontWeightHeavy) color:VGTertiary lines:1];
    h.attributedText = [[NSAttributedString alloc] initWithString:@"WORKS WITH" attributes:@{NSKernAttributeName: @1.2}];
    UIScrollView *sv = [UIScrollView new];
    sv.showsHorizontalScrollIndicator = NO;
    UIStackView *chips = [UIStackView new];
    chips.spacing = 8;
    chips.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSString *name in @[@"YouTube", @"TikTok", @"Instagram", @"X", @"Facebook", @"Reddit", @"Vimeo", @"Twitch", @"Dailymotion", @"SoundCloud", @"+1,000 more"]) {
        UILabel *l = [self label:VGFont(14, UIFontWeightSemibold) color:VGText lines:1];
        l.text = name;
        UIView *chip = [UIView new];
        chip.backgroundColor = VGSurface2;
        chip.layer.cornerRadius = 17;
        chip.layer.borderColor = VGStroke.CGColor;
        chip.layer.borderWidth = 1;
        l.translatesAutoresizingMaskIntoConstraints = NO;
        [chip addSubview:l];
        [NSLayoutConstraint activateConstraints:@[
            [chip.heightAnchor constraintEqualToConstant:34],
            [l.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:14],
            [l.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-14],
            [l.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
        ]];
        [chips addArrangedSubview:chip];
    }
    [sv addSubview:chips];
    [NSLayoutConstraint activateConstraints:@[
        [chips.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor],
        [chips.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor],
        [chips.leadingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.leadingAnchor constant:16],
        [chips.trailingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.trailingAnchor constant:-16],
        [chips.heightAnchor constraintEqualToAnchor:sv.frameLayoutGuide.heightAnchor],
        [sv.heightAnchor constraintEqualToConstant:34],
    ]];
    UIView *hWrap = [self padded:h top:0 bottom:0];
    self.chipsSection = [self vstack:@[hWrap, sv] spacing:10];
    UIView *wrap = [UIView new];
    self.chipsSection.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:self.chipsSection];
    [NSLayoutConstraint activateConstraints:@[
        [self.chipsSection.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:22],
        [self.chipsSection.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
        [self.chipsSection.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
        [self.chipsSection.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
    ]];
    self.chipsSection = wrap;
    [self.stack addArrangedSubview:wrap];
}

- (void)buildQuality {
    UILabel *h = [self label:VGFont(20, UIFontWeightHeavy) color:VGText lines:1];
    h.text = @"Choose quality";

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.itemSize = CGSizeMake(120, 128);
    layout.minimumLineSpacing = 10;
    layout.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);
    self.qualityList = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.qualityList.backgroundColor = UIColor.clearColor;
    self.qualityList.showsHorizontalScrollIndicator = NO;
    self.qualityList.dataSource = self;
    self.qualityList.delegate = self;
    [self.qualityList registerClass:VGQualityCell.class forCellWithReuseIdentifier:@"q"];
    [self.qualityList.heightAnchor constraintEqualToConstant:128].active = YES;

    self.downloadButton = VGPrimaryButton(@"Download", @"arrow.down.to.line");
    [self.downloadButton addTarget:self action:@selector(download) forControlEvents:UIControlEventTouchUpInside];
    self.downloadCaption = [self label:VGFont(13, UIFontWeightMedium) color:VGTertiary lines:0];
    self.downloadCaption.textAlignment = NSTextAlignmentCenter;

    UIView *bottom = [self padded:[self vstack:@[self.downloadButton, self.downloadCaption] spacing:10] top:18 bottom:0];
    self.qualitySection = [self vstack:@[[self padded:h top:16 bottom:12], self.qualityList, bottom] spacing:0];
    [self.stack addArrangedSubview:self.qualitySection];
}

- (void)buildProgress {
    self.stageLabel = [self label:VGFont(15, UIFontWeightSemibold) color:VGText lines:1];
    self.percentLabel = [self label:[UIFont monospacedDigitSystemFontOfSize:30 weight:UIFontWeightHeavy] color:VGText lines:1];
    self.percentLabel.textAlignment = NSTextAlignmentRight;
    [self.percentLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[self.stageLabel, self.percentLabel]];
    top.alignment = UIStackViewAlignmentLastBaseline;
    top.spacing = 8;

    self.bar = [VGProgressBar new];
    [self.bar.heightAnchor constraintEqualToConstant:6].active = YES;
    self.detailLabel = [self label:[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium] color:VGSecondary lines:1];

    UIButton *cancel = VGSecondaryButton(@"Cancel", @"xmark");
    [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *s = [self vstack:@[top, self.bar, self.detailLabel, cancel] spacing:12];
    [s setCustomSpacing:18 afterView:self.detailLabel];
    self.progressSection = [self padded:[self card:s] top:20 bottom:0];
    [self.stack addArrangedSubview:self.progressSection];
}

- (void)buildDone {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"
                                                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightBold]]];
    icon.tintColor = VGAccent;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *t = [self label:VGFont(20, UIFontWeightHeavy) color:VGText lines:1];
    t.text = @"Downloaded";
    self.doneSub = [self label:VGFont(14, UIFontWeightMedium) color:VGSecondary lines:2];
    UIStackView *texts = [self vstack:@[t, self.doneSub] spacing:2];
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[icon, texts]];
    head.spacing = 12;
    head.alignment = UIStackViewAlignmentCenter;

    self.photosButton = VGPrimaryButton(@"Save to Photos", @"photo.on.rectangle.angled");
    [self.photosButton addTarget:self action:@selector(savePhotos) forControlEvents:UIControlEventTouchUpInside];
    UIButton *play = VGSecondaryButton(@"Play", @"play.fill");
    [play addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
    self.shareButton = VGSecondaryButton(@"Share", @"square.and.arrow.up");
    [self.shareButton addTarget:self action:@selector(share) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[play, self.shareButton]];
    row.spacing = 10;
    row.distribution = UIStackViewDistributionFillEqually;

    UIButton *again = [UIButton buttonWithType:UIButtonTypeSystem];
    [again setTitle:@"Download another video" forState:UIControlStateNormal];
    again.titleLabel.font = VGFont(15, UIFontWeightSemibold);
    again.tintColor = VGAccent;
    [again addTarget:self action:@selector(reset) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *s = [self vstack:@[head, self.photosButton, row, again] spacing:12];
    [s setCustomSpacing:18 afterView:head];
    self.doneSection = [self padded:[self card:s] top:20 bottom:0];
    [self.stack addArrangedSubview:self.doneSection];
}

- (UIMenu *)settingsMenu {
    __weak typeof(self) ws = self;
    UIAction *update = [UIAction actionWithTitle:@"Update download engine" image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]
                                      identifier:nil handler:^(UIAction *a) { [ws updateEngine]; }];
    UIAction *about = [UIAction actionWithTitle:@"About VidGrab" image:[UIImage systemImageNamed:@"info.circle"]
                                     identifier:nil handler:^(UIAction *a) {
        NSString *v = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        [VGActions alert:@"VidGrab"
                 message:[NSString stringWithFormat:@"Version %@ by T4MAG0\nDownload engine: yt-dlp %@\n\nOnly download videos you have the right to keep. Some sites don't allow downloads in their terms.", v, [VGEngine shared].engineVersion]
                    from:ws];
    }];
    // Cache options are rebuilt each time the menu opens, so the size and toggle are current.
    UIDeferredMenuElement *cache = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^done)(NSArray<UIMenuElement *> *)) {
        [VGCache size:^(long long bytes) {
            NSString *size = [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
            UIAction *clear = [UIAction actionWithTitle:@"Clear cache" image:[UIImage systemImageNamed:@"trash"]
                                             identifier:nil handler:^(UIAction *a) { [ws clearCache]; }];
            clear.subtitle = [NSString stringWithFormat:@"%@ · downloads and sign-ins are kept", size];
            UIAction *autoClear = [UIAction actionWithTitle:@"Auto-clear cache on launch" image:[UIImage systemImageNamed:@"clock.arrow.circlepath"]
                                                 identifier:nil handler:^(UIAction *a) {
                VGCache.autoClearOnLaunch = !VGCache.autoClearOnLaunch;
                [VGActions toast:VGCache.autoClearOnLaunch ? @"Cache will clear each time VidGrab opens" : @"Auto-clear turned off"
                            icon:@"clock.arrow.circlepath" in:ws.view.window ?: ws.view];
            }];
            autoClear.state = VGCache.autoClearOnLaunch ? UIMenuElementStateOn : UIMenuElementStateOff;
            done(@[[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[clear, autoClear]]]);
        }];
    }];
    return [UIMenu menuWithTitle:@"Settings" children:@[cache, [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[update, about]]]];
}

- (void)openSettings {
    [[UIImpactFeedbackGenerator new] impactOccurred];
    [VGSettingsViewController presentFrom:self];
}

- (void)clearCache {
    [VGCache clear:^(long long freed) {
        NSString *msg = freed > 0 ? [NSString stringWithFormat:@"Cleared %@", [NSByteCountFormatter stringFromByteCount:freed countStyle:NSByteCountFormatterCountStyleFile]]
                                  : @"Cache is already empty";
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [VGActions toast:msg icon:@"checkmark.circle.fill" in:self.view.window ?: self.view];
    }];
}

#pragma mark State

- (void)setStep:(VGStep)step animated:(BOOL)animated {
    self.step = step;
    void (^apply)(void) = ^{
        self.welcomeHero.hidden = step != VGStepWelcome;
        self.chipsSection.hidden = step != VGStepWelcome;
        self.videoHero.hidden = step == VGStepWelcome;
        self.qualitySection.hidden = step != VGStepLoaded;
        self.progressSection.hidden = step != VGStepDownloading;
        self.doneSection.hidden = step != VGStepDone;
        for (UIView *v in self.stack.arrangedSubviews) v.alpha = v.hidden ? 0 : 1;
    };
    if (animated) [UIView animateWithDuration:0.3 animations:^{ apply(); [self.stack layoutIfNeeded]; }];
    else apply();
    [self updateClear];
}

- (void)setFinding:(BOOL)on {
    UIButtonConfiguration *c = self.findButton.configuration;
    c.showsActivityIndicator = on;
    c.attributedTitle = [[NSAttributedString alloc] initWithString:on ? @"Looking…" : @"Find video"
                                                        attributes:@{NSFontAttributeName: VGFont(16, UIFontWeightBold)}];
    self.findButton.configuration = c;
    self.findButton.userInteractionEnabled = !on;
    self.pasteButton.userInteractionEnabled = !on;
}

#pragma mark Actions

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self find];
    return YES;
}

- (NSString *)extractLink:(NSString *)text {
    NSDataDetector *det = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
    for (NSTextCheckingResult *m in [det matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        if ([m.URL.scheme hasPrefix:@"http"]) return m.URL.absoluteString;
    }
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)paste {
    UIPasteboard *pb = UIPasteboard.generalPasteboard;
    NSString *s = pb.URL.absoluteString ?: pb.string;
    if (!s.length) { [VGActions alert:@"Nothing to paste" message:@"Copy a video link first, then tap Paste." from:self]; return; }
    [self loadLink:s];
}

- (void)loadLink:(NSString *)link {
    self.field.text = [self extractLink:link];
    [self find];
}

- (void)find {
    [self.field resignFirstResponder];
    NSString *url = [self extractLink:self.field.text ?: @""];
    if (![url hasPrefix:@"http"]) {
        [VGActions alert:@"That's not a link" message:@"Paste a full link that starts with http or https." from:self];
        return;
    }
    self.field.text = url;
    [self updateClear];
    [self setFinding:YES];
    NSUInteger lookup = ++self.lookupID;
    [[VGEngine shared] fetch:url completion:^(VGVideo *video, NSString *error) {
        if (lookup != self.lookupID) return;  // cleared while looking up
        [self setFinding:NO];
        if (video) self.task = nil;
        if (!video) { [self showError:@"Couldn't find a video" message:error]; return; }
        self.video = video;
        [self fillVideo];
        [self setStep:VGStepLoaded animated:YES];
        [self.scroll setContentOffset:CGPointZero animated:YES];
    }];
}

- (void)fillVideo {
    VGVideo *v = self.video;
    self.siteBadge.text = (v.site ?: @"Video").uppercaseString;
    self.heroTitle.text = v.title;
    NSMutableArray *meta = [NSMutableArray array];
    if (v.uploader.length && ![v.uploader isEqualToString:v.site]) [meta addObject:v.uploader];
    if (VGDuration(v.duration)) [meta addObject:VGDuration(v.duration)];
    self.heroMeta.text = [meta componentsJoinedByString:@"  ·  "];
    self.heroMeta.hidden = meta.count == 0;

    self.heroImage.image = nil;
    if (v.thumbnail) {
        NSString *forURL = v.url;
        [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:v.thumbnail] completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            UIImage *img = d ? [UIImage imageWithData:d] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!img || ![self.video.url isEqualToString:forURL]) return;
                [UIView transitionWithView:self.heroImage duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve
                                animations:^{ self.heroImage.image = img; } completion:nil];
            });
        }] resume];
    }

    // Preselect the best option that works with Photos.
    self.selected = 0;
    [self.video.options enumerateObjectsUsingBlock:^(VGOption *o, NSUInteger i, BOOL *stop) {
        if (o.photos) { self.selected = (NSInteger)i; *stop = YES; }
    }];
    [self.qualityList reloadData];
    [self.qualityList scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:self.selected inSection:0]
                             atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:NO];
    [self updateCaption];
}

- (void)updateCaption {
    VGOption *o = self.video.options.count > (NSUInteger)self.selected ? self.video.options[self.selected] : nil;
    if (!o) { self.downloadCaption.text = @""; return; }
    if ([o.identifier isEqualToString:@"mp3"]) self.downloadCaption.text = @"MP3 at 256 kbps · plays anywhere. Share it or save to Files";
    else if (o.audio) self.downloadCaption.text = @"M4A audio · Share it or save to Files";
    else if (o.convert) self.downloadCaption.text = @"Converted to MP4 on your iPhone so Photos can play it. Takes a few minutes; keep the app open.";
    else if (o.photos) self.downloadCaption.text = @"MP4 · Ready for your Photos library";
    else self.downloadCaption.text = [NSString stringWithFormat:@"%@ · The Photos app can't open this one, but Files and other apps can", o.format];
}

- (void)download {
    if (!self.video || (NSUInteger)self.selected >= self.video.options.count) return;
    VGOption *opt = self.video.options[self.selected];
    self.bar.progress = 0;
    self.stageLabel.text = [VGEngine shared].activeCount >= 2 ? @"Waiting for other downloads…" : @"Starting…";
    self.percentLabel.text = @"0%";
    self.detailLabel.text = [NSString stringWithFormat:@"%@ · %@", opt.res, opt.sizeText.length ? opt.sizeText : opt.format];
    [self setStep:VGStepDownloading animated:YES];

    __weak typeof(self) ws = self;
    __block __weak VGTask *weakTask = nil;
    VGTask *task = [[VGEngine shared] download:self.video option:opt progress:^(double fraction, NSString *stage, NSString *detail) {
        if (!ws || ws.task != weakTask) return;   // the screen moved on; the download keeps going
        [ws.bar setProgress:fraction animated:YES];
        ws.percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)round(fraction * 100)];
        ws.stageLabel.text = stage;
        if (detail.length) ws.detailLabel.text = detail;
    } completion:^(VGItem *item, NSString *error) {
        UITabBarItem *tab = ws.tabBarController.tabBar.items.lastObject;
        if (item) { tab.badgeValue = @""; tab.badgeColor = VGAccent; }
        if (!ws || ws.task != weakTask) return;
        if (!item) {
            [ws setStep:VGStepLoaded animated:YES];
            if (![error isEqualToString:@"Cancelled."]) [ws showError:@"Download failed" message:error];
            return;
        }
        ws.item = item;
        ws.doneSub.text = [NSString stringWithFormat:@"%@ · %@ · in your Downloads", item.res,
                           [NSByteCountFormatter stringFromByteCount:item.bytes countStyle:NSByteCountFormatterCountStyleFile]];
        ws.photosButton.hidden = !item.photos;
        [ws setStep:VGStepDone animated:YES];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    }];
    weakTask = task;
    self.task = task;
}

- (void)cancel { if (self.task) [[VGEngine shared] cancelTask:self.task]; }

- (void)showError:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy details" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[VGEngine shared] copyErrorDetails:^{
            [VGActions toast:@"Error details copied" icon:@"doc.on.doc.fill" in:self.view.window ?: self.view];
        }];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)updateClear {
    BOOL hasSomething = self.field.text.length > 0 || self.video != nil;
    self.clearButton.hidden = YES;               // replaced by the Clear button in the row
    self.clearRowButton.enabled = hasSomething;  // dimmed when there's nothing to clear
}

/// Clears the link and the shown video, back to the start.
- (void)clearAll {
    self.lookupID++;
    self.task = nil;   // any download keeps running; it's still shown in Downloads
    [self setFinding:NO];
    self.video = nil;
    self.item = nil;
    self.field.text = @"";
    self.heroImage.image = nil;
    [self setStep:VGStepWelcome animated:YES];
    [self.scroll setContentOffset:CGPointZero animated:YES];
    [self updateClear];
}

- (void)reset {
    self.video = nil;
    self.item = nil;
    self.field.text = @"";
    [self setStep:VGStepWelcome animated:YES];
}

- (void)savePhotos { if (self.item) [VGActions saveToPhotos:self.item from:self]; }
- (void)play { if (self.item) [VGActions play:self.item from:self]; }
- (void)share { if (self.item) [VGActions share:self.item from:self source:self.shareButton]; }

- (void)updateEngine {

    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"Checking for updates…" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:wait animated:YES completion:nil];
    [[VGEngine shared] updateEngine:^(NSString *title, NSString *message) {
        [wait dismissViewControllerAnimated:YES completion:^{ [VGActions alert:title message:message from:self]; }];
    }];
}

#pragma mark Collection

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.video.options.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    VGQualityCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"q" forIndexPath:ip];
    [c configure:self.video.options[ip.item] selected:ip.item == self.selected];
    return c;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    self.selected = ip.item;
    [[UISelectionFeedbackGenerator new] selectionChanged];
    for (NSIndexPath *p in cv.indexPathsForVisibleItems) {
        [(VGQualityCell *)[cv cellForItemAtIndexPath:p] configure:self.video.options[p.item] selected:p.item == self.selected];
    }
    [cv scrollToItemAtIndexPath:ip atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:YES];
    [self updateCaption];
}

@end
