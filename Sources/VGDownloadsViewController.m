#import "VGDownloadsViewController.h"
#import "VGEngine.h"
#import "VGTheme.h"
#import "VGActions.h"
#import "VGSupportViewController.h"

@interface VGDownloadCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UILabel *titleLabel, *metaLabel, *durationLabel;
@property (nonatomic, strong) UIView *durationPill;
@property (nonatomic, strong) UIButton *more;
@end

@implementation VGDownloadCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = VGBackground;
        UIView *sel = [UIView new];
        sel.backgroundColor = VGSurface;
        self.selectedBackgroundView = sel;

        _thumb = [UIImageView new];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.layer.cornerRadius = 6;
        _thumb.backgroundColor = VGSurface2;
        _thumb.tintColor = VGTertiary;

        _durationPill = [UIView new];
        _durationPill.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
        _durationPill.layer.cornerRadius = 4;
        _durationLabel = [UILabel new];
        _durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightBold];
        _durationLabel.textColor = UIColor.whiteColor;

        _titleLabel = [UILabel new];
        _titleLabel.font = VGFont(15, UIFontWeightSemibold);
        _titleLabel.textColor = VGText;
        _titleLabel.numberOfLines = 2;

        _metaLabel = [UILabel new];
        _metaLabel.font = VGFont(13, UIFontWeightMedium);
        _metaLabel.textColor = VGSecondary;

        _more = [UIButton buttonWithType:UIButtonTypeSystem];
        [_more setImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
        _more.tintColor = VGSecondary;
        _more.showsMenuAsPrimaryAction = YES;

        for (UIView *v in @[_thumb, _titleLabel, _metaLabel, _more]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        _durationPill.translatesAutoresizingMaskIntoConstraints = NO;
        _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_thumb addSubview:_durationPill];
        [_durationPill addSubview:_durationLabel];

        UIView *c = self.contentView;
        [NSLayoutConstraint activateConstraints:@[
            [_thumb.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
            [_thumb.topAnchor constraintEqualToAnchor:c.topAnchor constant:10],
            [_thumb.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-10],
            [_thumb.widthAnchor constraintEqualToConstant:128],
            [_thumb.heightAnchor constraintEqualToConstant:72],
            [_durationPill.trailingAnchor constraintEqualToAnchor:_thumb.trailingAnchor constant:-5],
            [_durationPill.bottomAnchor constraintEqualToAnchor:_thumb.bottomAnchor constant:-5],
            [_durationLabel.topAnchor constraintEqualToAnchor:_durationPill.topAnchor constant:2],
            [_durationLabel.bottomAnchor constraintEqualToAnchor:_durationPill.bottomAnchor constant:-2],
            [_durationLabel.leadingAnchor constraintEqualToAnchor:_durationPill.leadingAnchor constant:5],
            [_durationLabel.trailingAnchor constraintEqualToAnchor:_durationPill.trailingAnchor constant:-5],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_thumb.trailingAnchor constant:12],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_more.leadingAnchor constant:-4],
            [_titleLabel.topAnchor constraintEqualToAnchor:_thumb.topAnchor constant:2],
            [_metaLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_metaLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
            [_more.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-6],
            [_more.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
            [_more.widthAnchor constraintEqualToConstant:40],
            [_more.heightAnchor constraintEqualToConstant:44],
        ]];
    }
    return self;
}

- (void)configure:(VGItem *)item {
    UIImage *img = item.thumbnailImage;
    if (img) {
        self.thumb.image = img;
        self.thumb.contentMode = UIViewContentModeScaleAspectFill;
    } else {
        self.thumb.image = [UIImage systemImageNamed:item.audio ? @"waveform" : @"film"];
        self.thumb.contentMode = UIViewContentModeCenter;
    }
    self.titleLabel.text = item.title;
    NSMutableArray *bits = [NSMutableArray arrayWithObject:item.res.length ? item.res : @"Video"];
    [bits addObject:[NSByteCountFormatter stringFromByteCount:item.bytes countStyle:NSByteCountFormatterCountStyleFile]];
    if (item.site.length) [bits addObject:item.site];
    self.metaLabel.text = [bits componentsJoinedByString:@" · "];
    NSString *d = VGDuration(item.duration);
    self.durationLabel.text = d;
    self.durationPill.hidden = d == nil;
}

@end


#pragma mark - In-progress row

static NSCache<NSString *, UIImage *> *thumbCache(void) {
    static NSCache *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [NSCache new]; });
    return c;
}

@interface VGTaskCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UILabel *titleLabel, *statusLabel, *percentLabel;
@property (nonatomic, strong) VGProgressBar *bar;
@property (nonatomic, strong) UIButton *action;
@property (nonatomic, weak) VGTask *task;
@property (nonatomic, copy) NSString *thumbURL;
@end

@implementation VGTaskCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = VGBackground;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _thumb = [UIImageView new];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.layer.cornerRadius = 6;
        _thumb.backgroundColor = VGSurface2;
        _titleLabel = [UILabel new];
        _titleLabel.font = VGFont(15, UIFontWeightSemibold);
        _titleLabel.textColor = VGText;
        _titleLabel.numberOfLines = 1;
        _statusLabel = [UILabel new];
        _statusLabel.font = VGFont(12, UIFontWeightMedium);
        _statusLabel.textColor = VGSecondary;
        _statusLabel.numberOfLines = 2;
        _percentLabel = [UILabel new];
        _percentLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightHeavy];
        _percentLabel.textColor = VGText;
        _percentLabel.textAlignment = NSTextAlignmentRight;
        [_percentLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_percentLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        _bar = [VGProgressBar new];
        _action = [UIButton buttonWithType:UIButtonTypeSystem];
        _action.tintColor = VGSecondary;
        for (UIView *v in @[_thumb, _titleLabel, _statusLabel, _percentLabel, _bar, _action]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        UIView *c = self.contentView;
        [NSLayoutConstraint activateConstraints:@[
            [_thumb.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
            [_thumb.topAnchor constraintEqualToAnchor:c.topAnchor constant:10],
            [_thumb.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-10],
            [_thumb.widthAnchor constraintEqualToConstant:128],
            [_thumb.heightAnchor constraintEqualToConstant:72],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_thumb.trailingAnchor constant:12],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_action.leadingAnchor constant:-4],
            [_titleLabel.topAnchor constraintEqualToAnchor:_thumb.topAnchor constant:1],
            [_statusLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_statusLabel.trailingAnchor constraintEqualToAnchor:_percentLabel.leadingAnchor constant:-6],
            [_statusLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3],
            [_percentLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_percentLabel.firstBaselineAnchor constraintEqualToAnchor:_statusLabel.firstBaselineAnchor],
            [_bar.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_bar.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_bar.bottomAnchor constraintEqualToAnchor:_thumb.bottomAnchor constant:-3],
            [_bar.heightAnchor constraintEqualToConstant:4],
            [_action.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-6],
            [_action.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
            [_action.widthAnchor constraintEqualToConstant:40],
            [_action.heightAnchor constraintEqualToConstant:44],
        ]];
    }
    return self;
}

- (void)configure:(VGTask *)t {
    self.task = t;
    self.titleLabel.text = t.video.title;
    BOOL failed = t.state == VGTaskFailed;
    if (failed) {
        self.statusLabel.text = t.error.length ? [@"Failed · " stringByAppendingString:t.error] : @"Failed";
        self.statusLabel.textColor = VGAccent;
    } else if (t.state == VGTaskQueued) {
        self.statusLabel.text = [NSString stringWithFormat:@"Waiting · %@", t.option.res];
        self.statusLabel.textColor = VGSecondary;
    } else {
        NSString *extra = t.detail.length ? [@" · " stringByAppendingString:t.detail] : @"";
        self.statusLabel.text = [t.stage stringByAppendingString:extra];
        self.statusLabel.textColor = VGSecondary;
    }
    self.percentLabel.text = failed ? @"" : [NSString stringWithFormat:@"%d%%", (int)round(t.fraction * 100)];
    self.bar.hidden = failed;
    [self.bar setProgress:t.fraction animated:YES];
    NSString *icon = failed ? @"arrow.clockwise.circle.fill" : @"xmark.circle.fill";
    [self.action setImage:[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]]
                 forState:UIControlStateNormal];
    self.action.tintColor = failed ? VGAccent : VGTertiary;
    self.action.accessibilityLabel = failed ? @"Try again" : @"Cancel download";

    NSString *url = t.video.thumbnail;
    if (![url isEqualToString:self.thumbURL]) {
        self.thumbURL = url;
        self.thumb.image = url ? [thumbCache() objectForKey:url] : nil;
        if (url && !self.thumb.image) {
            [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                UIImage *img = d ? [UIImage imageWithData:d] : nil;
                if (!img) return;
                [thumbCache() setObject:img forKey:url];
                dispatch_async(dispatch_get_main_queue(), ^{ if ([self.thumbURL isEqualToString:url]) self.thumb.image = img; });
            }] resume];
        }
    }
}

@end

@interface VGDownloadsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *empty;
@property (nonatomic, strong) UILabel *storageLabel;
@property (nonatomic, strong) NSArray<VGItem *> *items;
@property (nonatomic, strong) NSArray<VGTask *> *tasks;
@end

@implementation VGDownloadsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Downloads";
    self.view.backgroundColor = VGBackground;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    // "Buy me a coffee" at the top right.
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration];
    c.baseBackgroundColor = [VGAccent colorWithAlphaComponent:0.16];
    c.baseForegroundColor = VGAccent;
    c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    c.image = [UIImage systemImageNamed:@"cup.and.saucer.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold]];
    c.imagePadding = 6;
    c.contentInsets = NSDirectionalEdgeInsetsMake(7, 12, 7, 13);
    c.attributedTitle = [[NSAttributedString alloc] initWithString:@"Buy me a coffee" attributes:@{NSFontAttributeName: VGFont(13, UIFontWeightBold)}];
    __weak typeof(self) ws = self;
    UIButton *coffee = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) {
        [[UIImpactFeedbackGenerator new] impactOccurred];
        [[VGSupportViewController new] presentFrom:ws];
    }]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:coffee];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = VGBackground;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 92;
    [self.table registerClass:VGDownloadCell.class forCellReuseIdentifier:@"d"];
    [self.table registerClass:VGTaskCell.class forCellReuseIdentifier:@"t"];
    self.table.sectionHeaderTopPadding = 0;
    self.table.contentInset = UIEdgeInsetsMake(0, 0, 76, 0);   // room for the progress button
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    self.storageLabel = [UILabel new];
    self.storageLabel.font = VGFont(13, UIFontWeightMedium);
    self.storageLabel.textColor = VGTertiary;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 30)];
    self.storageLabel.frame = CGRectMake(16, 0, 400, 22);
    [header addSubview:self.storageLabel];
    self.table.tableHeaderView = header;

    [self buildEmpty];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload)
                                               name:VGLibraryDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(tasksChanged:)
                                               name:VGTasksDidChangeNotification object:nil];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.tabBarItem.badgeValue = nil;
    [self reload];
}

- (void)buildEmpty {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle"
                                                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:54 weight:UIImageSymbolWeightLight]]];
    icon.tintColor = VGTertiary;
    UILabel *t = [UILabel new];
    t.text = @"No downloads yet";
    t.font = VGFont(20, UIFontWeightHeavy);
    t.textColor = VGText;
    UILabel *s = [UILabel new];
    s.text = @"Videos you download show up here, ready to watch offline. They're also in the Files app under VidGrab.";
    s.font = VGFont(15, UIFontWeightRegular);
    s.textColor = VGSecondary;
    s.numberOfLines = 0;
    s.textAlignment = NSTextAlignmentCenter;
    UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:@[icon, t, s]];
    st.axis = UILayoutConstraintAxisVertical;
    st.alignment = UIStackViewAlignmentCenter;
    st.spacing = 10;
    [st setCustomSpacing:18 afterView:icon];
    st.translatesAutoresizingMaskIntoConstraints = NO;
    self.empty = [UIView new];
    self.empty.translatesAutoresizingMaskIntoConstraints = NO;
    [self.empty addSubview:st];
    [self.view addSubview:self.empty];
    [NSLayoutConstraint activateConstraints:@[
        [self.empty.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.empty.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [self.empty.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30],
        [st.topAnchor constraintEqualToAnchor:self.empty.topAnchor],
        [st.bottomAnchor constraintEqualToAnchor:self.empty.bottomAnchor],
        [st.leadingAnchor constraintEqualToAnchor:self.empty.leadingAnchor],
        [st.trailingAnchor constraintEqualToAnchor:self.empty.trailingAnchor],
    ]];
}

- (void)reload {
    self.items = [VGEngine shared].items;
    self.tasks = [VGEngine shared].tasks;
    [self.table reloadData];
    BOOL any = self.items.count || self.tasks.count;
    self.empty.hidden = any;
    self.table.tableHeaderView.hidden = self.items.count == 0;
    self.storageLabel.text = [NSString stringWithFormat:@"%lu %@ · %@ used", (unsigned long)self.items.count,
                              self.items.count == 1 ? @"video" : @"videos",
                              [NSByteCountFormatter stringFromByteCount:[VGEngine shared].totalBytes countStyle:NSByteCountFormatterCountStyleFile]];
}

- (void)tasksChanged:(NSNotification *)n {
    NSArray *now = [VGEngine shared].tasks;
    VGTask *t = n.object;
    // Just a progress tick: update that row in place (no flicker). Otherwise rebuild.
    if (t && [now isEqualToArray:self.tasks]) {
        NSUInteger row = [self.tasks indexOfObject:t];
        if (row != NSNotFound) {
            VGTaskCell *c = (VGTaskCell *)[self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
            if (c) [c configure:t];
            return;
        }
    }
    [self reload];
}

- (void)taskAction:(UIButton *)sender {
    UIView *v = sender;
    while (v && ![v isKindOfClass:VGTaskCell.class]) v = v.superview;
    VGTask *t = ((VGTaskCell *)v).task;
    if (!t) return;
    if (t.state == VGTaskFailed) [[VGEngine shared] retryTask:t];
    else [[VGEngine shared] cancelTask:t];
}

- (UIMenu *)menuFor:(VGItem *)item source:(UIView *)source {
    __weak typeof(self) ws = self;
    NSMutableArray *actions = [NSMutableArray array];
    [actions addObject:[UIAction actionWithTitle:@"Play" image:[UIImage systemImageNamed:@"play.fill"] identifier:nil
                                         handler:^(UIAction *a) { [VGActions play:item from:ws]; }]];
    if (item.photos) {
        [actions addObject:[UIAction actionWithTitle:@"Save to Photos" image:[UIImage systemImageNamed:@"photo.on.rectangle.angled"] identifier:nil
                                             handler:^(UIAction *a) { [VGActions saveToPhotos:item from:ws]; }]];
    }
    [actions addObject:[UIAction actionWithTitle:@"Save to Files" image:[UIImage systemImageNamed:@"folder"] identifier:nil
                                         handler:^(UIAction *a) { [VGActions saveToFiles:item from:ws]; }]];
    [actions addObject:[UIAction actionWithTitle:@"Share" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil
                                         handler:^(UIAction *a) { [VGActions share:item from:ws source:source]; }]];
    NSMutableArray *tools = [NSMutableArray array];
    [tools addObject:[UIAction actionWithTitle:@"Video info" image:[UIImage systemImageNamed:@"info.circle"] identifier:nil
                                       handler:^(UIAction *a) { [ws showInfo:item]; }]];
    if (!item.audio) {
        UIAction *fix = [UIAction actionWithTitle:@"Fix playback" image:[UIImage systemImageNamed:@"wand.and.stars"] identifier:nil
                                          handler:^(UIAction *a) { [ws repair:item]; }];
        fix.subtitle = @"Rebuilds the video with Apple's encoder";
        [tools addObject:fix];
    }
    UIAction *del = [UIAction actionWithTitle:@"Delete" image:[UIImage systemImageNamed:@"trash"] identifier:nil
                                      handler:^(UIAction *a) { [ws confirmDelete:item]; }];
    del.attributes = UIMenuElementAttributesDestructive;
    UIMenu *main = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:actions];
    UIMenu *toolMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:tools];
    return [UIMenu menuWithChildren:@[main, toolMenu, del]];
}

- (void)showInfo:(VGItem *)item {
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"Checking the video…" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:wait animated:YES completion:nil];
    [[VGEngine shared] diagnose:item completion:^(NSString *report) {
        [wait dismissViewControllerAnimated:YES completion:^{
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Video info" message:report preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                UIPasteboard.generalPasteboard.string = report;
                [VGActions toast:@"Video info copied" icon:@"doc.on.doc.fill" in:self.view.window ?: self.view];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }];
    }];
}

- (void)repair:(VGItem *)item {
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"Fixing playback…"
                                                                  message:@"Rebuilding the video with Apple's encoder. Keep VidGrab open.\n\n0%"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:wait animated:YES completion:nil];
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    [[VGEngine shared] repairItem:item progress:^(double f) {
        wait.message = [NSString stringWithFormat:@"Rebuilding the video with Apple's encoder. Keep VidGrab open.\n\n%d%%", (int)(f * 100)];
    } completion:^(NSString *error) {
        UIApplication.sharedApplication.idleTimerDisabled = [VGEngine shared].activeCount > 0;
        [wait dismissViewControllerAnimated:YES completion:^{
            if (error) {
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Couldn't fix it" message:error preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"Copy details" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                    [[VGEngine shared] diagnose:item completion:^(NSString *report) {
                        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"Fix playback failed:\n%@\n\n%@", error, report];
                        [VGActions toast:@"Details copied" icon:@"doc.on.doc.fill" in:self.view.window ?: self.view];
                    }];
                }]];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            }
            else [VGActions toast:@"Video rebuilt. Try playing it now." icon:@"checkmark.circle.fill" in:self.view.window ?: self.view];
            [self reload];
        }];
    }];
}

- (void)confirmDelete:(VGItem *)item {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Delete this download?"
                                                               message:@"It will be removed from VidGrab. Copies saved to Photos or Files are kept."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[VGEngine shared] deleteItem:item];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)(section == 0 ? self.tasks.count : self.items.count);
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    NSUInteger n = section == 0 ? self.tasks.count : self.items.count;
    if (!n || (section == 1 && !self.tasks.count)) return nil;
    UILabel *l = [UILabel new];
    NSString *title = section == 0 ? [NSString stringWithFormat:@"IN PROGRESS · %lu", (unsigned long)[VGEngine shared].activeCount] : @"SAVED";
    if (section == 0 && [VGEngine shared].activeCount == 0) title = @"NEEDS ATTENTION";
    l.attributedText = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: VGFont(12, UIFontWeightHeavy), NSForegroundColorAttributeName: VGTertiary, NSKernAttributeName: @1.0}];
    UIView *h = [UIView new];
    h.backgroundColor = VGBackground;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [h addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:h.leadingAnchor constant:16],
        [l.bottomAnchor constraintEqualToAnchor:h.bottomAnchor constant:-4],
    ]];
    return h;
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section {
    if (section == 0) return self.tasks.count ? 30 : 0.01;
    return (self.items.count && self.tasks.count) ? 36 : 0.01;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        VGTaskCell *c = [tv dequeueReusableCellWithIdentifier:@"t" forIndexPath:ip];
        [c configure:self.tasks[ip.row]];
        [c.action removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [c.action addTarget:self action:@selector(taskAction:) forControlEvents:UIControlEventTouchUpInside];
        return c;
    }
    VGDownloadCell *c = [tv dequeueReusableCellWithIdentifier:@"d" forIndexPath:ip];
    VGItem *item = self.items[ip.row];
    [c configure:item];
    c.more.menu = [self menuFor:item source:c.more];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        VGTask *t = self.tasks[ip.row];
        if (t.state != VGTaskFailed) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Download failed" message:t.error preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Try again" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [[VGEngine shared] retryTask:t]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Copy details" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [[VGEngine shared] copyErrorDetails:^{ [VGActions toast:@"Error details copied" icon:@"doc.on.doc.fill" in:self.view.window ?: self.view]; }];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [[VGEngine shared] dismissTask:t]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    [VGActions play:self.items[ip.row] from:self];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        VGTask *t = self.tasks[ip.row];
        BOOL failed = t.state == VGTaskFailed;
        UIContextualAction *a = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:failed ? @"Remove" : @"Cancel"
                                                                      handler:^(UIContextualAction *x, UIView *v, void (^done)(BOOL)) {
            if (failed) [[VGEngine shared] dismissTask:t]; else [[VGEngine shared] cancelTask:t];
            done(YES);
        }];
        a.image = [UIImage systemImageNamed:failed ? @"trash.fill" : @"xmark"];
        return [UISwipeActionsConfiguration configurationWithActions:@[a]];
    }
    VGItem *item = self.items[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [[VGEngine shared] deleteItem:item];
        done(YES);
    }];
    del.image = [UIImage systemImageNamed:@"trash.fill"];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    if (ip.section == 0) return nil;
    VGItem *item = self.items[ip.row];
    UIView *cell = [tv cellForRowAtIndexPath:ip];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray *s) { return [self menuFor:item source:cell]; }];
}

@end
