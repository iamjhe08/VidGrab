#import "VGHomeViewController.h"
#import "VGPlaylistStore.h"
#import "VGSavedPlaylistsViewController.h"
#import "VGEngine.h"
#import "VGTheme.h"
#import "VGActions.h"
#import "VGQualityCell.h"
#import "VGCrash.h"
#import "VGBlocker.h"
#import "VGCache.h"
#import "VGSettingsViewController.h"

#pragma mark - Home

typedef NS_ENUM(NSInteger, VGStep) { VGStepWelcome, VGStepLoaded, VGStepDownloading, VGStepDone, VGStepPlaylist };

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

// Paste-free start
@property (nonatomic, strong) UIView *clipBanner;
@property (nonatomic, strong) UILabel *clipTitle;
@property (nonatomic) BOOL fromClipboard;
@property (nonatomic, strong) UIButton *notThisButton;

// Playlists
@property (nonatomic, strong) UIView *playlistSection;
@property (nonatomic, strong) UILabel *playlistTitle, *playlistMeta;
@property (nonatomic, strong) UIStackView *playlistRows;
@property (nonatomic, strong) UIButton *playlistMore, *playlistAll, *playlistDownload, *playlistStream, *playlistSave;
@property (nonatomic, copy) NSArray<VGVideo *> *streamQueue;
@property (nonatomic) NSUInteger playlistStreamToken;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *queueOrder;
@property (nonatomic) NSInteger queuePos, queueRepeat;
@property (nonatomic) BOOL queueShuffle, queueStarted;
@property (nonatomic) NSUInteger queueLoadID;
@property (nonatomic, weak) VGPlayerViewController *queuePlayer;
@property (nonatomic, strong) UISegmentedControl *modeControl;   // Download or Stream
@property (nonatomic) BOOL opening;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *picked;
@property (nonatomic) BOOL showAllRows;
@property (nonatomic, copy) NSString *playlistQuality;
@property (nonatomic, strong) NSArray<UIButton *> *playlistQualityButtons;

// Home when nothing is going on
@property (nonatomic, strong) UIView *activitySection;
@property (nonatomic, strong) UIView *nowCard;
@property (nonatomic, strong) UILabel *nowTitle, *nowPercent;
@property (nonatomic, strong) VGProgressBar *nowBar;
@property (nonatomic, strong) UIView *recentBlock;
@property (nonatomic, strong) UIStackView *recentRow;
@end

static NSString *const kClipCount = @"vgClipboardCount";
static NSString *const kClipDismissed = @"vgClipboardDismissed";

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
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(openSavedNotification:) name:VGOpenSavedPlaylist object:nil];
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
    [self buildPlaylist];
    [self buildProgress];
    [self buildDone];
    [self buildActivity];
    [self setStep:VGStepWelcome animated:NO];

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(appActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appInactive) name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(refreshActivity) name:VGTasksDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(refreshActivity) name:VGLibraryDidChangeNotification object:nil];
    [self refreshActivity];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSString *report = [VGCrash previousReport];
    if (!report) { [self checkClipboard]; return; }
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
    h1.text = @"Download from anywhere.";
    UILabel *sub = [self label:VGFont(16, UIFontWeightRegular) color:VGSecondary lines:0];
    sub.text = @"Copy a video or playlist link from any app. Return to VidGrab, and your link is automatically detected and ready to download.";
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

- (void)buildClipBanner {
    UILabel *tag = [self label:VGFont(12, UIFontWeightHeavy) color:VGHex(0xFF8FA6) lines:1];
    tag.attributedText = [[NSAttributedString alloc] initWithString:@"FOUND ON YOUR CLIPBOARD" attributes:@{NSKernAttributeName: @1.4}];
    self.clipTitle = [self label:VGFont(30, UIFontWeightHeavy) color:VGText lines:0];
    self.clipTitle.text = @"Ready when you are.";
    UIStackView *s = [self vstack:@[tag, self.clipTitle] spacing:4];
    self.clipBanner = [self padded:s top:18 bottom:12];
    [self.stack addArrangedSubview:self.clipBanner];
}

- (void)buildVideoHero {
    [self buildClipBanner];
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

    self.notThisButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.notThisButton setTitle:@"Not this one" forState:UIControlStateNormal];
    self.notThisButton.titleLabel.font = VGFont(15, UIFontWeightSemibold);
    self.notThisButton.tintColor = VGSecondary;
    [self.notThisButton.heightAnchor constraintEqualToConstant:44].active = YES;
    [self.notThisButton addTarget:self action:@selector(notThisOne) forControlEvents:UIControlEventTouchUpInside];
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Download", @"Stream"]];
    self.modeControl.selectedSegmentIndex = [NSUserDefaults.standardUserDefaults boolForKey:@"vgStreamMode"] ? 1 : 0;
    self.modeControl.selectedSegmentTintColor = VGAccent;
    self.modeControl.backgroundColor = VGSurface2;
    [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: VGSecondary, NSFontAttributeName: VGFont(15, UIFontWeightSemibold)} forState:UIControlStateNormal];
    [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: VGFont(15, UIFontWeightBold)} forState:UIControlStateSelected];
    [self.modeControl.heightAnchor constraintEqualToConstant:40].active = YES;
    [self.modeControl addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    UIView *bottom = [self padded:[self vstack:@[self.modeControl, self.downloadButton, self.downloadCaption, self.notThisButton] spacing:10] top:18 bottom:0];
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
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.widthAnchor constraintEqualToConstant:34].active = YES;
    [icon.heightAnchor constraintEqualToConstant:34].active = YES;
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
        self.activitySection.hidden = step != VGStepWelcome;
        self.clipBanner.hidden = !(self.fromClipboard && (step == VGStepLoaded || step == VGStepPlaylist));
        self.videoHero.hidden = step == VGStepWelcome || step == VGStepPlaylist;
        self.qualitySection.hidden = step != VGStepLoaded;
        self.playlistSection.hidden = step != VGStepPlaylist;
        self.notThisButton.hidden = !self.fromClipboard;
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
    self.fromClipboard = NO;
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
    self.fromClipboard = NO;
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
        if (!video) {
            if (self.fromClipboard) { self.fromClipboard = NO; [self clearAll]; return; }   // not a video link: stay quiet
            [self showError:@"Couldn't find a video" message:error];
            return;
        }
        self.video = video;
        if (video.isPlaylist) {
            [self fillPlaylist];
            [self setStep:VGStepPlaylist animated:YES];
            [self.scroll setContentOffset:CGPointZero animated:YES];
            return;
        }
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

- (BOOL)streamMode { return self.modeControl.selectedSegmentIndex == 1; }

- (void)modeChanged {
    [NSUserDefaults.standardUserDefaults setBool:[self streamMode] forKey:@"vgStreamMode"];
    [self updateCaption];
}

- (void)setPrimaryTitle:(NSString *)title icon:(NSString *)icon {
    UIButtonConfiguration *c = self.downloadButton.configuration;
    if (c) {
        c.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: VGFont(16, UIFontWeightBold)}];
        c.image = [UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold]];
        self.downloadButton.configuration = c;
    } else {
        [self.downloadButton setTitle:title forState:UIControlStateNormal];
        [self.downloadButton setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
    }
}

- (void)updateCaption {
    VGOption *o = self.video.options.count > (NSUInteger)self.selected ? self.video.options[self.selected] : nil;
    if (!o) { self.downloadCaption.text = @""; return; }
    if ([self streamMode]) {
        [self setPrimaryTitle:(self.opening ? @"Opening…" : @"Stream") icon:@"play.fill"];
        self.downloadCaption.text = o.audio ? @"Plays now in VidGrab's player. Nothing is saved unless you tap the download button there"
                                            : @"Plays now in VidGrab's player. Tap the download button in the player to keep it";
        return;
    }
    [self setPrimaryTitle:@"Download" icon:@"arrow.down.to.line"];
    if ([o.identifier isEqualToString:@"mp3"]) self.downloadCaption.text = @"MP3 at 256 kbps · plays anywhere. Share it or save to Files";
    else if (o.audio) self.downloadCaption.text = @"M4A audio · Share it or save to Files";
    else if (o.convert) self.downloadCaption.text = @"Converted to MP4 on your iPhone so Photos can play it. Takes a few minutes; keep the app open.";
    else if (o.photos) self.downloadCaption.text = @"MP4 · Ready for your Photos library";
    else self.downloadCaption.text = [NSString stringWithFormat:@"%@ · The Photos app can't open this one, but Files and other apps can", o.format];
}

- (void)stream {
    if (!self.video || self.opening || (NSUInteger)self.selected >= self.video.options.count) return;
    // No quality is asked for here: the player opens fast on its own pick and the viewer changes quality inside it.
    VGOption *picked = self.video.options[self.selected];
    VGOption *opt = picked.audio ? picked : nil;
    VGVideo *video = self.video;
    NSUInteger token = self.lookupID;
    self.opening = YES;
    self.downloadButton.enabled = NO;
    [self updateCaption];
    __weak typeof(self) ws = self;
    void (^done)(void) = ^{ ws.opening = NO; ws.downloadButton.enabled = YES; [ws updateCaption]; };
    [[VGEngine shared] streamLinkFor:video option:opt completion:^(NSDictionary *info, NSString *error) {
        if (!ws) return;
        if (ws.lookupID != token) return;   // cleared while opening
        if (!info) { done(); [ws showError:@"Couldn't stream this video" message:error ?: @"Try Download instead."]; return; }
        [VGPlayerViewController prepareStream:info completion:^(AVPlayerItem *item, NSString *err) {
            if (!ws) return;
            if (ws.lookupID != token) return;   // cleared while opening
            done();
            if (!item) { [ws showError:@"Couldn't stream this video" message:err ?: @"Try Download instead."]; return; }
            VGPlayerViewController *p = [VGPlayerViewController playerForStreamItem:item video:video option:opt audio:[info[@"audio"] boolValue]];
            p.streamMaster = [info[@"master"] boolValue];
            p.streamVariants = [info[@"variants"] isKindOfClass:NSDictionary.class] ? info[@"variants"] : nil;
            UIViewController *top = ws;
            while (top.presentedViewController) top = top.presentedViewController;
            [top presentViewController:p animated:YES completion:^{ [p start]; }];
        }];
    }];
}

- (void)download {
    if ([self streamMode]) { [self stream]; return; }
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
    self.opening = NO;
    self.downloadButton.enabled = YES;
    self.task = nil;   // any download keeps running; it's still shown in Downloads
    [self setFinding:NO];
    self.video = nil;
    self.item = nil;
    self.field.text = @"";
    self.heroImage.image = nil;
    self.fromClipboard = NO;
    [self setStep:VGStepWelcome animated:YES];
    [self.scroll setContentOffset:CGPointZero animated:YES];
    [self updateClear];
    [self refreshActivity];
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


#pragma mark Paste-free start

- (void)appInactive {
    // Remember the clipboard as it is now, so a link copied inside VidGrab isn't offered back.
    [NSUserDefaults.standardUserDefaults setInteger:UIPasteboard.generalPasteboard.changeCount forKey:kClipCount];
}

- (void)appActive {
    [self refreshActivity];
    [self checkClipboard];
}

+ (BOOL)clipboardEnabled {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    return [d objectForKey:@"vgClipboardCheck"] ? [d boolForKey:@"vgClipboardCheck"] : YES;
}

/// When VidGrab opens (or comes back) with a new link on the clipboard, look it up right away,
/// whatever Home was showing before. The tab switches to Home if needed.
- (void)checkClipboard {
    if (![VGHomeViewController clipboardEnabled] || !self.isViewLoaded) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (self.tabBarController.presentedViewController || self.presentedViewController) return;   // Settings or a sheet is open
    if (self.field.isFirstResponder || !self.findButton.userInteractionEnabled) return;            // typing, or already looking up
    UIPasteboard *pb = UIPasteboard.generalPasteboard;
    NSInteger count = pb.changeCount;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ([d objectForKey:kClipCount] && [d integerForKey:kClipCount] == count) return;
    [d setInteger:count forKey:kClipCount];
    if (!pb.hasURLs && !pb.hasStrings) return;
    // Checks for a web link without reading the clipboard, so no paste prompt for other text.
    [pb detectPatternsForPatterns:[NSSet setWithObject:UIPasteboardDetectionPatternProbableWebURL]
                completionHandler:^(NSSet<UIPasteboardDetectionPattern> *found, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![found containsObject:UIPasteboardDetectionPatternProbableWebURL]) return;
            NSString *text = pb.URL.absoluteString ?: pb.string;
            NSString *link = text ? [self extractLink:text] : nil;
            if (![link hasPrefix:@"http"] || [link isEqualToString:[d stringForKey:kClipDismissed]]) return;
            if ([link isEqualToString:self.video.url] || [link isEqualToString:self.field.text]) return;   // already showing it
            if (self.tabBarController && self.tabBarController.selectedViewController != self.navigationController)
                self.tabBarController.selectedViewController = self.navigationController;
            [self.navigationController popToRootViewControllerAnimated:NO];
            if (self.step != VGStepWelcome) [self clearAll];
            self.fromClipboard = YES;
            self.field.text = link;
            [self find];
        });
    }];
}

- (void)notThisOne {
    if (self.video.url) [NSUserDefaults.standardUserDefaults setObject:self.video.url forKey:kClipDismissed];
    [self clearAll];
}

#pragma mark Playlists

- (UIButton *)pill:(NSString *)title {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = VGFont(14, UIFontWeightBold);
    b.layer.cornerRadius = 12;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    [b.heightAnchor constraintEqualToConstant:44].active = YES;
    return b;
}

- (void)stylePill:(UIButton *)b on:(BOOL)on {
    b.backgroundColor = on ? [VGAccent colorWithAlphaComponent:0.14] : VGSurface2;
    b.layer.borderColor = (on ? VGAccent : VGStroke).CGColor;
    b.layer.borderWidth = on ? 2 : 1;
    [b setTitleColor:VGText forState:UIControlStateNormal];
    b.accessibilityTraits = on ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

- (void)buildPlaylist {
    UILabel *tag = [self label:VGFont(11, UIFontWeightHeavy) color:VGText lines:1];
    tag.attributedText = [[NSAttributedString alloc] initWithString:@"PLAYLIST" attributes:@{NSKernAttributeName: @1.0}];
    self.playlistTitle = [self label:VGFont(19, UIFontWeightHeavy) color:VGText lines:2];
    self.playlistMeta = [self label:VGFont(14, UIFontWeightMedium) color:VGSecondary lines:1];

    self.playlistAll = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playlistAll.titleLabel.font = VGFont(14, UIFontWeightBold);
    self.playlistAll.tintColor = VGHex(0xFF8FA6);
    [self.playlistAll addTarget:self action:@selector(toggleAllPicked) forControlEvents:UIControlEventTouchUpInside];
    UIView *spacer = [UIView new];
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[self.playlistMeta, spacer, self.playlistAll]];
    head.alignment = UIStackViewAlignmentCenter;

    self.playlistRows = [self vstack:@[] spacing:2];
    self.playlistMore = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playlistMore.titleLabel.font = VGFont(14, UIFontWeightBold);
    self.playlistMore.tintColor = VGHex(0xFF8FA6);
    [self.playlistMore.heightAnchor constraintEqualToConstant:44].active = YES;
    [self.playlistMore addTarget:self action:@selector(showAllPlaylistRows) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *listInner = [self vstack:@[self.playlistRows, self.playlistMore] spacing:0];
    UIView *list = [UIView new];
    list.backgroundColor = VGHex(0x0F0F14);
    list.layer.cornerRadius = 14;
    listInner.translatesAutoresizingMaskIntoConstraints = NO;
    [list addSubview:listInner];
    [NSLayoutConstraint activateConstraints:@[
        [listInner.topAnchor constraintEqualToAnchor:list.topAnchor constant:6],
        [listInner.bottomAnchor constraintEqualToAnchor:list.bottomAnchor constant:-2],
        [listInner.leadingAnchor constraintEqualToAnchor:list.leadingAnchor constant:6],
        [listInner.trailingAnchor constraintEqualToAnchor:list.trailingAnchor constant:-6],
    ]];

    NSMutableArray *qs = [NSMutableArray array];
    NSArray *names = @[@"Best", @"1080p", @"720p", @"480p", @"MP3"];
    for (NSUInteger i = 0; i < names.count; i++) {
        UIButton *b = [self pill:names[i]];
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(pickPlaylistQuality:) forControlEvents:UIControlEventTouchUpInside];
        [qs addObject:b];
    }
    self.playlistQualityButtons = qs;
    UIStackView *qrow = [[UIStackView alloc] initWithArrangedSubviews:qs];
    qrow.spacing = 6;
    qrow.distribution = UIStackViewDistributionFillEqually;

    self.playlistDownload = VGPrimaryButton(@"Download", @"arrow.down.circle.fill");
    [self.playlistDownload addTarget:self action:@selector(downloadPlaylist) forControlEvents:UIControlEventTouchUpInside];
    self.playlistStream = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.playlistStream setTitle:@"  Stream selected" forState:UIControlStateNormal];
    [self.playlistStream setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    self.playlistStream.titleLabel.font = VGFont(16, UIFontWeightBold);
    self.playlistStream.tintColor = VGText;
    [self.playlistStream setTitleColor:VGText forState:UIControlStateNormal];
    self.playlistStream.backgroundColor = VGSurface2;
    self.playlistStream.layer.cornerRadius = 14;
    self.playlistStream.layer.cornerCurve = kCACornerCurveContinuous;
    self.playlistStream.layer.borderWidth = 1;
    self.playlistStream.layer.borderColor = VGStroke.CGColor;
    [self.playlistStream.heightAnchor constraintEqualToConstant:50].active = YES;
    [self.playlistStream addTarget:self action:@selector(streamPlaylist) forControlEvents:UIControlEventTouchUpInside];
    self.playlistSave = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playlistSave.titleLabel.font = VGFont(16, UIFontWeightBold);
    self.playlistSave.tintColor = VGText;
    [self.playlistSave setTitleColor:VGText forState:UIControlStateNormal];
    self.playlistSave.backgroundColor = VGSurface2;
    self.playlistSave.layer.cornerRadius = 14;
    self.playlistSave.layer.cornerCurve = kCACornerCurveContinuous;
    self.playlistSave.layer.borderWidth = 1;
    self.playlistSave.layer.borderColor = VGStroke.CGColor;
    [self.playlistSave.heightAnchor constraintEqualToConstant:50].active = YES;
    [self.playlistSave addTarget:self action:@selector(savePlaylistTapped) forControlEvents:UIControlEventTouchUpInside];
    UILabel *note = [self label:VGFont(12, UIFontWeightMedium) color:VGTertiary lines:0];
    note.text = @"Tick the videos you want. Download saves each one in the chosen quality (they show up in Downloads). Stream plays them one after another in VidGrab's player. Save playlist keeps the list (nothing is downloaded) so you can open it again from the playlist button at the top left of Library.";

    UIStackView *s = [self vstack:@[tag, self.playlistTitle, head, list, qrow, self.playlistDownload, self.playlistStream, self.playlistSave, note] spacing:12];
    [s setCustomSpacing:4 afterView:tag];
    [s setCustomSpacing:6 afterView:self.playlistTitle];
    UIView *card = [self card:s];
    card.layer.cornerRadius = 22;
    self.playlistSection = [self padded:card top:6 bottom:10];
    [self.stack addArrangedSubview:self.playlistSection];
    self.playlistQuality = @"1080";
}

- (void)fillPlaylist {
    VGVideo *p = self.video;
    self.playlistTitle.text = p.title;
    self.picked = [NSMutableArray array];
    for (NSUInteger i = 0; i < p.entries.count; i++) [self.picked addObject:@YES];
    self.showAllRows = NO;
    [self rebuildPlaylistRows];
    [self pickPlaylistQuality:self.playlistQualityButtons[1]];
    [self refreshSaveButton];
}

- (void)refreshSaveButton {
    BOOL saved = self.video.url.length && [VGPlaylistStore forURL:self.video.url] != nil;
    [self.playlistSave setTitle:saved ? @"  Saved · tap to remove" : @"  Save playlist" forState:UIControlStateNormal];
    [self.playlistSave setImage:[UIImage systemImageNamed:saved ? @"bookmark.fill" : @"bookmark"] forState:UIControlStateNormal];
    self.playlistSave.tintColor = saved ? VGAccent : VGText;
}

- (void)savePlaylistTapped {
    VGSavedPlaylist *have = [VGPlaylistStore forURL:self.video.url];
    UIView *host = self.view.window ?: self.view;
    if (have) {
        [VGPlaylistStore remove:have];
        [VGActions toast:@"Removed from saved playlists" icon:@"bookmark.slash" in:host];
    } else {
        [VGPlaylistStore save:self.video];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [VGActions toast:@"Playlist saved. Open it from the top left of Library" icon:@"bookmark.fill" in:host];
    }
    [self refreshSaveButton];
}

/// Opens a playlist saved earlier (no internet needed to see the list).
- (void)showSavedPlaylist:(VGSavedPlaylist *)p {
    [self clearAll];
    self.video = [p asVideo];
    self.field.text = p.url;
    [self updateClear];
    [self fillPlaylist];
    [self setStep:VGStepPlaylist animated:YES];
    [self.scroll setContentOffset:CGPointZero animated:YES];
}

- (void)openSavedNotification:(NSNotification *)n {
    VGSavedPlaylist *p = [VGPlaylistStore withID:n.userInfo[@"id"] ?: @""];
    if (!p) return;
    self.tabBarController.selectedIndex = 0;
    [self showSavedPlaylist:p];
}

- (void)rebuildPlaylistRows {
    for (UIView *v in self.playlistRows.arrangedSubviews) [v removeFromSuperview];
    NSArray<VGVideo *> *entries = self.video.entries;
    NSUInteger shown = self.showAllRows ? entries.count : MIN(entries.count, 5);
    for (NSUInteger i = 0; i < shown; i++) {
        VGVideo *e = entries[i];
        BOOL on = [self.picked[i] boolValue];
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.tag = (NSInteger)i;
        [row addTarget:self action:@selector(togglePicked:) forControlEvents:UIControlEventTouchUpInside];
        UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:on ? @"checkmark.circle.fill" : @"circle"]];
        check.tintColor = on ? VGAccent : VGTertiary;
        check.contentMode = UIViewContentModeScaleAspectFit;
        check.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
        [check.widthAnchor constraintEqualToConstant:26].active = YES;
        [check.heightAnchor constraintEqualToConstant:26].active = YES;
        [check setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [check setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UILabel *t = [self label:VGFont(14, UIFontWeightMedium) color:on ? VGText : VGSecondary lines:2];
        t.text = [NSString stringWithFormat:@"%lu. %@", (unsigned long)i + 1, e.title];
        UILabel *d = [self label:VGFont(12, UIFontWeightMedium) color:VGTertiary lines:1];
        d.text = VGDuration(e.duration) ?: @"";
        [d setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *h = [[UIStackView alloc] initWithArrangedSubviews:@[check, t, d]];
        h.spacing = 10;
        h.alignment = UIStackViewAlignmentCenter;
        h.userInteractionEnabled = NO;
        h.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:h];
        [NSLayoutConstraint activateConstraints:@[
            [h.topAnchor constraintEqualToAnchor:row.topAnchor constant:8],
            [h.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-8],
            [h.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:8],
            [h.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8],
            [row.heightAnchor constraintGreaterThanOrEqualToConstant:46],
        ]];
        row.accessibilityLabel = e.title;
        row.accessibilityTraits = on ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
        [self.playlistRows addArrangedSubview:row];
    }
    self.playlistMore.hidden = shown >= entries.count;
    [self.playlistMore setTitle:[NSString stringWithFormat:@"Show all %lu", (unsigned long)entries.count] forState:UIControlStateNormal];
    [self updatePlaylistSummary];
}

- (NSUInteger)pickedCount {
    NSUInteger n = 0;
    for (NSNumber *x in self.picked) if (x.boolValue) n++;
    return n;
}

- (void)updatePlaylistSummary {
    NSUInteger total = self.video.entries.count, n = [self pickedCount];
    NSMutableArray *bits = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%lu videos", (unsigned long)total]];
    if (VGDuration(self.video.duration)) [bits addObject:VGDuration(self.video.duration)];
    self.playlistMeta.text = [bits componentsJoinedByString:@" · "];
    [self.playlistAll setTitle:n == total ? @"Select none" : @"Select all" forState:UIControlStateNormal];
    UIButtonConfiguration *c = self.playlistDownload.configuration;
    NSString *title = n == 1 ? @"Download 1 video" : [NSString stringWithFormat:@"Download %lu videos", (unsigned long)n];
    if (c) {
        c.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: VGFont(17, UIFontWeightBold)}];
        self.playlistDownload.configuration = c;
    } else {
        [self.playlistDownload setTitle:title forState:UIControlStateNormal];
    }
    self.playlistDownload.enabled = n > 0;
    self.playlistDownload.alpha = n > 0 ? 1 : 0.4;
    self.playlistStream.enabled = n > 0;
    self.playlistStream.alpha = n > 0 ? 1 : 0.4;
}

- (void)togglePicked:(UIButton *)row {
    NSUInteger i = (NSUInteger)row.tag;
    if (i >= self.picked.count) return;
    self.picked[i] = @(![self.picked[i] boolValue]);
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self rebuildPlaylistRows];
}

- (void)toggleAllPicked {
    BOOL all = [self pickedCount] == self.picked.count;
    for (NSUInteger i = 0; i < self.picked.count; i++) self.picked[i] = @(!all);
    [self rebuildPlaylistRows];
}

- (void)showAllPlaylistRows {
    self.showAllRows = YES;
    [self rebuildPlaylistRows];
}

- (void)pickPlaylistQuality:(UIButton *)b {
    self.playlistQuality = @[@"best", @"1080", @"720", @"480", @"mp3"][(NSUInteger)b.tag];
    for (UIButton *x in self.playlistQualityButtons) [self stylePill:x on:x == b];
}

/// Plays the ticked videos one after another in VidGrab's player (one player; the tracks swap inside it).
- (void)streamPlaylist {
    NSMutableArray *q = [NSMutableArray array];
    NSArray<VGVideo *> *entries = self.video.entries;
    for (NSUInteger i = 0; i < entries.count && i < self.picked.count; i++) if ([self.picked[i] boolValue]) [q addObject:entries[i]];
    if (!q.count) return;
    self.streamQueue = q;
    self.queueShuffle = NO;
    self.queueRepeat = 0;
    self.queuePlayer = nil;
    self.queueStarted = NO;
    self.queueOrder = [NSMutableArray array];
    for (NSUInteger i = 0; i < q.count; i++) [self.queueOrder addObject:@(i)];
    ++self.playlistStreamToken;
    self.playlistStream.enabled = NO;
    [self loadQueuePos:0 direction:1];
}

/// The play order: in order, or shuffled with `first` (a queue index) leading.
- (void)rebuildQueueOrderKeeping:(NSInteger)first {
    NSMutableArray *o = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.streamQueue.count; i++) [o addObject:@(i)];
    if (self.queueShuffle) {
        NSMutableArray *rest = [NSMutableArray array];
        for (NSNumber *n in o) if (n.integerValue != first) [rest addObject:n];
        for (NSInteger i = (NSInteger)rest.count - 1; i > 0; i--) [rest exchangeObjectAtIndex:i withObjectAtIndex:arc4random_uniform((uint32_t)i + 1)];
        o = [NSMutableArray array];
        if (first >= 0) [o addObject:@(first)];
        [o addObjectsFromArray:rest];
        self.queuePos = first >= 0 ? 0 : -1;
    } else {
        self.queuePos = first >= 0 ? first : -1;
    }
    self.queueOrder = o;
}

- (void)queueModeChangedShuffle:(BOOL)shuffle repeat:(NSInteger)repeat {
    NSInteger cur = (self.queuePos >= 0 && self.queuePos < (NSInteger)self.queueOrder.count) ? [self.queueOrder[self.queuePos] integerValue] : -1;
    BOOL reorder = shuffle != self.queueShuffle;
    self.queueShuffle = shuffle;
    self.queueRepeat = repeat;
    if (reorder) [self rebuildQueueOrderKeeping:cur];
}

/// Next or back. `ended` is YES when the track just ended by itself.
- (void)queueStep:(NSInteger)dir ended:(BOOL)ended {
    VGPlayerViewController *p = self.queuePlayer;
    if (!p) return;
    NSInteger n = (NSInteger)self.queueOrder.count, next;
    if (ended && self.queueRepeat == 2) { [p restartTrack]; return; }
    if (dir < 0) {
        if ([p currentSeconds] > 3) { [p restartTrack]; return; }
        next = self.queuePos - 1;
        if (next < 0) {
            if (self.queueRepeat == 1) next = n - 1; else { [p restartTrack]; return; }
        }
    } else {
        next = self.queuePos + 1;
        if (next >= n) {
            if (self.queueRepeat == 1) {
                if (self.queueShuffle) { [self rebuildQueueOrderKeeping:-1]; }
                next = 0;
            } else if (ended) { [p showFinished]; return; }
            else { [p showMessage:@"That was the last one"]; return; }
        }
    }
    [self loadQueuePos:next direction:dir];
}

- (void)loadQueuePos:(NSInteger)pos direction:(NSInteger)dir {
    __weak typeof(self) ws = self;
    NSArray<VGVideo *> *q = self.streamQueue;
    NSInteger n = (NSInteger)self.queueOrder.count;
    void (^reset)(void) = ^{ ws.playlistStream.enabled = YES; };
    if (pos < 0 || pos >= n) { reset(); [self.queuePlayer showFinished]; return; }
    if (self.queueStarted && !(self.queuePlayer && self.queuePlayer.presentingViewController)) { reset(); return; }   // the viewer closed the player
    self.queuePos = pos;
    NSUInteger token = self.playlistStreamToken;
    NSUInteger load = ++self.queueLoadID;
    VGVideo *video = q[[self.queueOrder[pos] unsignedIntegerValue]];
    NSString *position = [NSString stringWithFormat:@"%ld of %lu", (long)pos + 1, (unsigned long)q.count];
    UIView *host = self.queuePlayer.view ?: self.view.window ?: self.view;
    [VGActions toast:[NSString stringWithFormat:@"Opening %@…", position] icon:@"play.circle.fill" in:host];
    void (^skip)(void) = ^{
        [VGActions toast:@"Couldn't stream one video, skipping it" icon:@"exclamationmark.triangle.fill" in:ws.queuePlayer.view ?: ws.view.window ?: ws.view];
        [ws loadQueuePos:pos + (dir < 0 ? -1 : 1) direction:dir];
    };
    [[VGEngine shared] streamLinkFor:video option:nil completion:^(NSDictionary *info, NSString *error) {
        if (!ws || ws.playlistStreamToken != token || ws.queueLoadID != load) return;
        if (!info) { skip(); return; }
        [VGPlayerViewController prepareStream:info completion:^(AVPlayerItem *item, NSString *err) {
            if (!ws || ws.playlistStreamToken != token || ws.queueLoadID != load) return;
            if (!item) { skip(); return; }
            BOOL audio = [info[@"audio"] boolValue], master = [info[@"master"] boolValue];
            NSDictionary *variants = [info[@"variants"] isKindOfClass:NSDictionary.class] ? info[@"variants"] : nil;
            VGPlayerViewController *cur = ws.queuePlayer;
            if (cur && cur.presentingViewController) {
                [cur swapToStreamItem:item video:video audio:audio master:master variants:variants position:position];   // same player, no flicker
            } else {
                VGPlayerViewController *p = [VGPlayerViewController playerForStreamItem:item video:video option:nil audio:audio];
                p.streamMaster = master;
                p.streamVariants = variants;
                p.positionText = position;
                p.playlistMode = YES;
                p.shuffleOn = ws.queueShuffle;
                p.repeatMode = ws.queueRepeat;
                p.onEnded = ^(VGPlayerViewController *x) { [ws queueStep:1 ended:YES]; };
                p.onSkip = ^(VGPlayerViewController *x, NSInteger d) { [ws queueStep:d ended:NO]; };
                p.onModeChange = ^(BOOL shuffle, NSInteger repeat) { [ws queueModeChangedShuffle:shuffle repeat:repeat]; };
                ws.queuePlayer = p;
                ws.queueStarted = YES;
                UIViewController *top = ws;
                while (top.presentedViewController) top = top.presentedViewController;
                [top presentViewController:p animated:YES completion:^{ [p start]; }];
            }
            ws.playlistStream.enabled = YES;
        }];
    }];
}

- (void)downloadPlaylist {
    NSArray<VGVideo *> *entries = self.video.entries;
    VGOption *opt = [VGEngine presetOption:self.playlistQuality ?: @"best"];
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < entries.count && i < self.picked.count; i++) {
        if (![self.picked[i] boolValue]) continue;
        [[VGEngine shared] download:entries[i] option:opt progress:nil completion:nil];
        n++;
    }
    if (!n) return;
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    [VGActions toast:[NSString stringWithFormat:@"%lu videos added to Downloads", (unsigned long)n] icon:@"arrow.down.circle.fill" in:self.view.window ?: self.view];
    [self clearAll];
}

#pragma mark Home activity

- (void)buildActivity {
    // Downloading now
    self.nowTitle = [self label:VGFont(14, UIFontWeightBold) color:VGText lines:1];
    self.nowPercent = [self label:VGFont(15, UIFontWeightHeavy) color:VGText lines:1];
    [self.nowPercent setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    self.nowBar = [VGProgressBar new];
    [self.nowBar.heightAnchor constraintEqualToConstant:6].active = YES;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle.fill"]];
    icon.tintColor = VGAccent;
    [icon.widthAnchor constraintEqualToConstant:28].active = YES;
    [icon.heightAnchor constraintEqualToConstant:28].active = YES;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    UIStackView *texts = [self vstack:@[self.nowTitle, self.nowBar] spacing:8];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, texts, self.nowPercent]];
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    self.nowCard = [self card:row];
    self.nowCard.layer.cornerRadius = 18;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openDownloads)];
    [self.nowCard addGestureRecognizer:tap];
    self.nowCard.isAccessibilityElement = YES;
    self.nowCard.accessibilityTraits = UIAccessibilityTraitButton;

    // Recently saved
    UILabel *h = [self label:VGFont(18, UIFontWeightBold) color:VGText lines:1];
    h.text = @"Recently saved";
    UIButton *all = [UIButton buttonWithType:UIButtonTypeSystem];
    [all setTitle:@"See all" forState:UIControlStateNormal];
    all.titleLabel.font = VGFont(14, UIFontWeightBold);
    all.tintColor = VGHex(0xFF8FA6);
    [all addTarget:self action:@selector(openDownloads) forControlEvents:UIControlEventTouchUpInside];
    UIView *sp = [UIView new];
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[h, sp, all]];
    head.alignment = UIStackViewAlignmentCenter;
    self.recentRow = [UIStackView new];
    self.recentRow.spacing = 12;
    self.recentRow.distribution = UIStackViewDistributionFillEqually;
    self.recentBlock = [self vstack:@[head, self.recentRow] spacing:10];

    UIStackView *s = [self vstack:@[self.nowCard, self.recentBlock] spacing:22];
    self.activitySection = [self padded:s top:14 bottom:6];
    // Put it right after the link box, before the "works with" chips.
    NSUInteger at = [self.stack.arrangedSubviews indexOfObject:self.chipsSection];
    if (at == NSNotFound) [self.stack addArrangedSubview:self.activitySection];
    else [self.stack insertArrangedSubview:self.activitySection atIndex:at];
}

- (void)openDownloads {
    UITabBarController *tabs = self.tabBarController;
    if (tabs.viewControllers.count) tabs.selectedIndex = tabs.viewControllers.count - 1;
}

- (void)refreshActivity {
    if (!self.activitySection) return;
    VGTask *t = [VGEngine shared].leadTask;
    self.nowCard.hidden = t == nil;
    if (t) {
        NSUInteger n = [VGEngine shared].activeCount;
        self.nowTitle.text = n > 1 ? [NSString stringWithFormat:@"%@ (+%lu more)", t.video.title ?: @"Downloading", (unsigned long)n - 1] : (t.video.title ?: @"Downloading");
        self.nowPercent.text = [NSString stringWithFormat:@"%d%%", (int)round(t.fraction * 100)];
        self.nowBar.progress = t.fraction;
        self.nowCard.accessibilityLabel = [NSString stringWithFormat:@"Downloading %@, %@", self.nowTitle.text, self.nowPercent.text];
    }
    NSMutableArray<VGItem *> *recent = [NSMutableArray array];
    for (VGItem *i in [VGEngine shared].items) {
        if (i.vault) continue;
        [recent addObject:i];
        if (recent.count == 2) break;
    }
    // Only rebuild the thumbnails when the list changed.
    NSString *key = [[recent valueForKey:@"fileName"] componentsJoinedByString:@"|"];
    if (![key isEqualToString:self.recentRow.accessibilityIdentifier]) {
        self.recentRow.accessibilityIdentifier = key;
        for (UIView *v in self.recentRow.arrangedSubviews) [v removeFromSuperview];
        for (VGItem *i in recent) [self.recentRow addArrangedSubview:[self recentCard:i]];
        if (recent.count == 1) [self.recentRow addArrangedSubview:[UIView new]];
    }
    self.recentBlock.hidden = recent.count == 0;
}

- (UIView *)recentCard:(VGItem *)item {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageView *img = [[UIImageView alloc] initWithImage:item.thumbnailImage];
    img.contentMode = UIViewContentModeScaleAspectFill;
    img.clipsToBounds = YES;
    img.backgroundColor = VGSurface2;
    img.layer.cornerRadius = 14;
    img.layer.cornerCurve = kCACornerCurveContinuous;
    [img.heightAnchor constraintEqualToConstant:100].active = YES;
    UILabel *badge = [self label:VGFont(11, UIFontWeightHeavy) color:VGText lines:1];
    badge.text = [NSString stringWithFormat:@" %@ ", item.res.length ? item.res : (item.audio ? @"Audio" : @"Video")];
    badge.backgroundColor = [VGBackground colorWithAlphaComponent:0.75];
    badge.layer.cornerRadius = 6;
    badge.clipsToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [img addSubview:badge];
    UILabel *t = [self label:VGFont(13, UIFontWeightBold) color:VGText lines:2];
    t.text = item.title;
    UIStackView *s = [self vstack:@[img, t] spacing:6];
    s.userInteractionEnabled = NO;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [b addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:b.topAnchor], [s.bottomAnchor constraintEqualToAnchor:b.bottomAnchor],
        [s.leadingAnchor constraintEqualToAnchor:b.leadingAnchor], [s.trailingAnchor constraintEqualToAnchor:b.trailingAnchor],
        [badge.trailingAnchor constraintEqualToAnchor:img.trailingAnchor constant:-8],
        [badge.bottomAnchor constraintEqualToAnchor:img.bottomAnchor constant:-8],
    ]];
    b.accessibilityLabel = [@"Play " stringByAppendingString:item.title ?: @"video"];
    __weak typeof(self) ws = self;
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [VGActions play:item from:ws]; }] forControlEvents:UIControlEventTouchUpInside];
    return b;
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
