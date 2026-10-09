#import "VGDownloadsViewController.h"
#import "VGEngine.h"
#import "VGDownloadDefaults.h"
#import "VGTheme.h"
#import "VGActions.h"
#import "VGSupportViewController.h"
#import "VGVaultLock.h"
#import "VGFolderEditorViewController.h"
#import "VGStorageView.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [UIView animateWithDuration:animated ? 0.2 : 0 animations:^{ self.more.alpha = editing ? 0 : 1; }];
    self.more.userInteractionEnabled = !editing;
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


#pragma mark - Folder row

@interface VGFolderCell : UITableViewCell
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *nameLabel, *metaLabel;
@property (nonatomic, strong) UIButton *more;
@end

@implementation VGFolderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = VGBackground;
        UIView *sel = [UIView new];
        sel.backgroundColor = VGSurface;
        self.selectedBackgroundView = sel;
        _icon = [UIImageView new];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:38 weight:UIImageSymbolWeightRegular];
        _icon.image = [UIImage systemImageNamed:@"folder.fill"];
        _nameLabel = [UILabel new];
        _nameLabel.font = VGFont(16, UIFontWeightSemibold);
        _nameLabel.textColor = VGText;
        _metaLabel = [UILabel new];
        _metaLabel.font = VGFont(13, UIFontWeightMedium);
        _metaLabel.textColor = VGSecondary;
        _more = [UIButton buttonWithType:UIButtonTypeSystem];
        [_more setImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
        _more.tintColor = VGSecondary;
        _more.showsMenuAsPrimaryAction = YES;
        for (UIView *v in @[_icon, _nameLabel, _metaLabel, _more]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        UIView *c = self.contentView;
        [NSLayoutConstraint activateConstraints:@[
            [_icon.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
            [_icon.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:56],
            [_icon.heightAnchor constraintEqualToConstant:56],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:10],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:_more.leadingAnchor constant:-4],
            [_nameLabel.bottomAnchor constraintEqualToAnchor:c.centerYAnchor constant:-1],
            [_metaLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],
            [_metaLabel.topAnchor constraintEqualToAnchor:c.centerYAnchor constant:2],
            [_more.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-6],
            [_more.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
            [_more.widthAnchor constraintEqualToConstant:40],
            [_more.heightAnchor constraintEqualToConstant:44],
        ]];
    }
    return self;
}

- (void)configure:(VGFolder *)f count:(NSUInteger)n bytes:(long long)bytes {
    self.icon.tintColor = f.color;
    self.nameLabel.text = f.name;
    NSString *what = n == 0 ? @"Empty" : [NSString stringWithFormat:@"%lu %@ \u00B7 %@", (unsigned long)n, n == 1 ? @"video" : @"videos",
                                           [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile]];
    self.metaLabel.text = what;
    self.accessibilityLabel = [NSString stringWithFormat:@"Folder %@, %@", f.name, what];
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
@property (nonatomic, strong) UIButton *pauseButton;
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
        _pauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _pauseButton.tintColor = VGSecondary;
        for (UIView *v in @[_thumb, _titleLabel, _statusLabel, _percentLabel, _bar, _action, _pauseButton]) {
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
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_pauseButton.leadingAnchor constant:-2],
            [_pauseButton.trailingAnchor constraintEqualToAnchor:_action.leadingAnchor constant:2],
            [_pauseButton.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
            [_pauseButton.widthAnchor constraintEqualToConstant:36],
            [_pauseButton.heightAnchor constraintEqualToConstant:44],
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
    } else if (t.state == VGTaskPaused) {
        self.statusLabel.text = [NSString stringWithFormat:@"Paused · %@", t.option.res];
        self.statusLabel.textColor = VGSecondary;
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
    BOOL paused = t.state == VGTaskPaused;
    self.pauseButton.hidden = failed || t.state == VGTaskQueued;
    [self.pauseButton setImage:[UIImage systemImageNamed:paused ? @"play.circle.fill" : @"pause.circle.fill"
                                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]]
                      forState:UIControlStateNormal];
    self.pauseButton.tintColor = paused ? VGAccent : VGTertiary;
    self.pauseButton.accessibilityLabel = paused ? @"Resume download" : @"Pause download";

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

// Table sections: downloads in progress, folders, saved videos.
enum { kSecFolders = 0, kSecTasks = 1, kSecItems = 2 };

@interface VGDownloadsViewController () <UITableViewDataSource, UITableViewDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UISearchResultsUpdating>
@property (nonatomic) BOOL vaultMode;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic) NSInteger secretTaps;
@property (nonatomic) CFAbsoluteTime lastSecretTap;
/// Set when this screen shows the inside of one folder.
@property (nonatomic, strong, nullable) VGFolder *folder;
@property (nonatomic, strong) NSArray<VGFolder *> *folders;
@property (nonatomic, strong) UIBarButtonItem *addFolderItem;
@property (nonatomic, strong) UIButton *folderAction;
// Main list only: the "Downloads" title sits in the list's own header so the phone-storage card can share its row.
@property (nonatomic, strong) UILabel *headerTitle;
@property (nonatomic, strong) VGStorageView *storageCard;
@property (nonatomic, strong) UIView *blankTitle;
@property (nonatomic, strong) UIButton *vaultButton;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *empty;
@property (nonatomic, strong) UILabel *storageLabel;
@property (nonatomic, strong) NSArray<VGItem *> *items;
@property (nonatomic, strong) NSArray<VGTask *> *tasks;
// Select mode: pick several downloads and act on all of them at once.
@property (nonatomic) BOOL selecting;
@property (nonatomic, strong) UIBarButtonItem *selectItem, *importItem;
// Importing videos from Photos or Files
@property (nonatomic) NSInteger importTotal, importFinished, importOK;
@property (nonatomic, strong) NSMutableArray<NSString *> *importErrors;
@property (nonatomic, strong) UIAlertController *importAlert;
@property (nonatomic) NSInteger importAlertState;   // 0 not showing, 1 appearing, 2 showing
@property (nonatomic, strong) UIView *actionBar;
@property (nonatomic, strong) NSArray<UIButton *> *actionButtons;
@property (nonatomic, strong) UIButton *batchPhotosButton;
@property (nonatomic, strong) UIButton *vaultAction;
@property (nonatomic, strong) NSArray<VGItem *> *oldItems;
@end

@implementation VGDownloadsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.vaultMode ? @"Private Vault 2.0" : (self.folder.name ?: @"Downloads");
    self.view.backgroundColor = VGBackground;
    BOOL isMain = !self.vaultMode && !self.folder;
    // The main list draws its own big title (see headerTitle); the folder and vault screens keep the normal large title.
    self.navigationItem.largeTitleDisplayMode = isMain ? UINavigationItemLargeTitleDisplayModeNever : UINavigationItemLargeTitleDisplayModeAlways;
    if (isMain) {
        self.blankTitle = [UIView new];
        self.navigationItem.titleView = self.blankTitle;   // hides the small title; Select brings it back to show the count
    }

    __weak typeof(self) ws = self;
    self.selectItem = [[UIBarButtonItem alloc] initWithTitle:@"Select" style:UIBarButtonItemStylePlain target:self action:@selector(startSelecting)];
    [self.selectItem setTitleTextAttributes:@{NSFontAttributeName: VGFont(17, UIFontWeightSemibold)} forState:UIControlStateNormal];

    // "Import" at the top right: bring in a video or song from Photos or Files.
    UIButtonConfiguration *ic = [UIButtonConfiguration filledButtonConfiguration];
    ic.baseBackgroundColor = [VGAccent colorWithAlphaComponent:0.16];
    ic.baseForegroundColor = VGAccent;
    ic.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    ic.image = [UIImage systemImageNamed:@"square.and.arrow.down.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold]];
    ic.imagePadding = 6;
    ic.contentInsets = NSDirectionalEdgeInsetsMake(7, 12, 7, 13);
    ic.attributedTitle = [[NSAttributedString alloc] initWithString:@"Import" attributes:@{NSFontAttributeName: VGFont(13, UIFontWeightBold)}];
    UIButton *imp = [UIButton buttonWithConfiguration:ic primaryAction:nil];
    imp.menu = [UIMenu menuWithTitle:self.vaultMode ? @"Import into the vault" : @"Import" children:@[
        [UIAction actionWithTitle:@"From Photos" image:[UIImage systemImageNamed:@"photo.on.rectangle"] identifier:nil handler:^(UIAction *a) { [ws importFromPhotos]; }],
        [UIAction actionWithTitle:@"From Files" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *a) { [ws importFromFiles]; }],
    ]];
    imp.showsMenuAsPrimaryAction = YES;
    imp.accessibilityLabel = @"Import a video from Photos or Files";
    self.importItem = [[UIBarButtonItem alloc] initWithCustomView:imp];
    self.addFolderItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder.badge.plus"] style:UIBarButtonItemStylePlain target:self action:@selector(newFolderTapped)];
    self.addFolderItem.accessibilityLabel = @"New folder";
    [self showNormalBarButtons];
    if (self.vaultMode) {
        UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
        sc.searchResultsUpdater = self;
        sc.obscuresBackgroundDuringPresentation = NO;
        sc.searchBar.placeholder = self.folder ? @"Search this folder" : @"Search the vault";
        sc.searchBar.tintColor = VGAccent;
        self.navigationItem.searchController = sc;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
        self.definesPresentationContext = YES;
    }

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = VGBackground;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 92;
    [self.table registerClass:VGDownloadCell.class forCellReuseIdentifier:@"d"];
    [self.table registerClass:VGTaskCell.class forCellReuseIdentifier:@"t"];
    [self.table registerClass:VGFolderCell.class forCellReuseIdentifier:@"f"];
    self.table.allowsMultipleSelectionDuringEditing = YES;
    self.table.sectionHeaderTopPadding = 0;
    self.table.contentInset = UIEdgeInsetsMake(0, 0, 76, 0);   // room for the progress button
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    self.storageLabel = [UILabel new];
    self.storageLabel.font = VGFont(13, UIFontWeightMedium);
    self.storageLabel.textColor = VGTertiary;
    BOOL plainHeader = self.vaultMode || self.folder != nil;
    CGFloat rowH = plainHeader ? 0 : 66;   // the title row: "Downloads" on the left, the storage card on the right
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, plainHeader ? 30 : 38 + rowH)];
    if (!plainHeader) {
        self.headerTitle = [UILabel new];
        self.headerTitle.text = @"Downloads";
        self.headerTitle.font = VGFont(32, UIFontWeightHeavy);
        self.headerTitle.textColor = VGText;
        self.headerTitle.adjustsFontSizeToFitWidth = YES;
        self.headerTitle.minimumScaleFactor = 0.7;
        self.headerTitle.translatesAutoresizingMaskIntoConstraints = NO;
        [self.headerTitle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.headerTitle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        self.storageCard = [[VGStorageView alloc] initWithFrame:CGRectZero];
        self.storageCard.translatesAutoresizingMaskIntoConstraints = NO;
        __weak typeof(self) wsc = self;
        self.storageCard.onTap = ^{
            VGDownloadsViewController *me = wsc;
            if (!me) return;
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Phone storage" message:me.storageCard.detailsText preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                UIPasteboard.generalPasteboard.string = me.storageCard.detailsText;
                [VGActions toast:@"Storage details copied" icon:@"doc.on.doc.fill" in:me.view.window ?: me.view];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
            [me presentViewController:a animated:YES completion:nil];
        };
        [header addSubview:self.headerTitle];
        [header addSubview:self.storageCard];
        NSLayoutConstraint *cardW = [self.storageCard.widthAnchor constraintEqualToConstant:176];
        cardW.priority = UILayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[
            [self.headerTitle.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
            [self.headerTitle.centerYAnchor constraintEqualToAnchor:header.topAnchor constant:rowH / 2],
            [self.storageCard.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
            [self.storageCard.centerYAnchor constraintEqualToAnchor:header.topAnchor constant:rowH / 2],
            [self.storageCard.heightAnchor constraintEqualToConstant:56],
            cardW,
            // Never slides under the title: on a narrow phone the card gets smaller instead.
            [self.storageCard.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.headerTitle.trailingAnchor constant:10],
        ]];
        // The Private Vault 2.0 entry, above the list.
        UIButtonConfiguration *vc = [UIButtonConfiguration filledButtonConfiguration];
        vc.baseBackgroundColor = VGSurface;
        vc.baseForegroundColor = VGText;
        vc.cornerStyle = UIButtonConfigurationCornerStyleLarge;
        vc.image = [UIImage systemImageNamed:@"lock.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold]];
        vc.imagePadding = 12;
        vc.imagePlacement = NSDirectionalRectEdgeLeading;
        vc.contentInsets = NSDirectionalEdgeInsetsMake(14, 16, 14, 16);
        self.vaultButton = [UIButton buttonWithConfiguration:vc primaryAction:nil];
        self.vaultButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        self.vaultButton.tintColor = VGAccent;
        self.vaultButton.layer.borderColor = VGStroke.CGColor;
        self.vaultButton.layer.borderWidth = 1;
        self.vaultButton.layer.cornerRadius = 14;
        [self.vaultButton addTarget:self action:@selector(openVault) forControlEvents:UIControlEventTouchUpInside];
        self.vaultButton.frame = CGRectMake(16, 6 + rowH, 100, 56);
        self.vaultButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.vaultButton.hidden = YES;   // Private Vault 2.0 has no button: hold "Downloads" for 3 seconds
        [header addSubview:self.vaultButton];
        self.storageLabel.frame = CGRectMake(16, 10 + rowH, 400, 22);
        self.headerTitle.userInteractionEnabled = YES;
        [self.headerTitle addGestureRecognizer:[self secretHold]];
    } else {
        self.storageLabel.frame = CGRectMake(16, 0, 400, 22);
    }
    [header addSubview:self.storageLabel];
    self.table.tableHeaderView = header;

    [self buildEmpty];
    [self buildActionBar];
    if (self.vaultMode) {
        // Lock the vault again whenever VidGrab leaves the screen.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(lockVault) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
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

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopSelecting];
}

- (void)viewWillAppear:(BOOL)animated {
    self.batchPhotosButton.hidden = VGDownloadDefaults.filesOnly;
    [super viewWillAppear:animated];
    self.navigationController.tabBarItem.badgeValue = nil;
    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect f = self.vaultButton.frame;
    f.size.width = self.table.bounds.size.width - 32;
    self.vaultButton.frame = f;
}

#pragma mark Private Vault 2.0

/// The way into the vault: press and hold the word "Downloads" for 1 second.
- (UILongPressGestureRecognizer *)secretHold {
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(secretHeld:)];
    g.minimumPressDuration = 1.0;
    g.allowableMovement = 30;
    return g;
}

- (void)secretHeld:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;   // fires once the second is up
    [[UIImpactFeedbackGenerator new] impactOccurred];
    [self openVault];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    self.searchText = [sc.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self reload];
}

- (void)openVault {
    __weak typeof(self) ws = self;
    // First time the vault is opened: the warning comes first, before any lock screen.
    [VGVaultLock warnFirstTimeFrom:self then:^{
        [VGVaultLock unlockFrom:ws completion:^(BOOL ok) {
            if (!ok) return;
            VGDownloadsViewController *v = [VGDownloadsViewController new];
            v.vaultMode = YES;
            [ws.navigationController pushViewController:v animated:YES];
        }];
    }];
}

- (void)lockVault {
    if (!self.vaultMode) return;
    UINavigationController *nav = self.navigationController;
    NSUInteger i = [nav.viewControllers indexOfObject:self];
    if (i != NSNotFound && i > 0) [nav popToViewController:nav.viewControllers[i - 1] animated:NO];
}

- (void)moveItem:(VGItem *)item toVault:(BOOL)vault {
    [[VGEngine shared] setItem:item inVault:vault];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    [VGActions toast:vault ? @"Moved to Private Vault 2.0" : @"Moved back to Downloads"
                icon:vault ? @"lock.fill" : @"lock.open.fill" in:self.view.window ?: self.view];
}

- (void)buildEmpty {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.vaultMode ? @"lock" : (self.folder ? @"folder" : @"arrow.down.circle")
                                                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:54 weight:UIImageSymbolWeightLight]]];
    icon.tintColor = VGTertiary;
    UILabel *t = [UILabel new];
    t.text = self.vaultMode ? @"Your vault is empty" : (self.folder ? @"This folder is empty" : @"No downloads yet");
    t.font = VGFont(20, UIFontWeightHeavy);
    t.textColor = VGText;
    UILabel *s = [UILabel new];
    s.text = self.vaultMode ? @"Touch and hold a download and choose Move to Vault. Videos here are hidden from Downloads and the Files app."
                            : (self.folder ? @"Touch and hold a video in Downloads and choose Move to Folder. Or tap Select, pick some videos and tap Folder."
                                           : @"Videos you download show up here, ready to watch offline. They're also in the Files app under VidGrab.");
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
    if (self.folder && ![[VGEngine shared] folderWithID:self.folder.identifier]) {   // this folder was deleted
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    NSMutableArray *mine = [NSMutableArray array];
    NSUInteger locked = 0, shown = 0;
    long long shownBytes = 0;
    for (VGItem *i in [VGEngine shared].items) {
        if (i.vault) locked++;
        if (i.vault != self.vaultMode) continue;
        shown++;
        shownBytes += i.bytes;
        // The main list holds only videos that are not in a folder; a folder screen holds just its own.
        if (self.folder) { if (![i.folderID isEqualToString:self.folder.identifier]) continue; }
        else if ([[VGEngine shared] folderWithID:i.folderID]) continue;
        if (self.searchText.length && [[@[i.title ?: @"", i.site ?: @"", i.artist ?: @""] componentsJoinedByString:@" "] rangeOfString:self.searchText options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
        [mine addObject:i];
    }
    [self.storageCard refreshWithVidGrabBytes:[VGEngine shared].totalBytes];
    self.items = mine;
    self.tasks = (self.vaultMode || self.folder) ? @[] : [VGEngine shared].tasks;
    NSArray<VGFolder *> *allFolders = self.folder ? @[] : (self.vaultMode ? [VGEngine shared].vaultFolders : [VGEngine shared].folders);
    if (self.searchText.length) {
        NSMutableArray *m = [NSMutableArray array];
        for (VGFolder *f in allFolders) if ([f.name rangeOfString:self.searchText options:NSCaseInsensitiveSearch].location != NSNotFound) [m addObject:f];
        allFolders = m;
    }
    self.folders = allFolders;
    if (self.folder && !self.selecting) self.title = [[VGEngine shared] folderWithID:self.folder.identifier].name;
    if (self.vaultButton) {
        UIButtonConfiguration *c = self.vaultButton.configuration;
        c.attributedTitle = [[NSAttributedString alloc] initWithString:@"Private Vault 2.0" attributes:@{NSFontAttributeName: VGFont(16, UIFontWeightBold)}];
        c.attributedSubtitle = [[NSAttributedString alloc] initWithString:locked ? [NSString stringWithFormat:@"%lu locked · Face ID or passcode", (unsigned long)locked] : @"Hide videos behind Face ID or passcode"
                                                               attributes:@{NSFontAttributeName: VGFont(12, UIFontWeightMedium), NSForegroundColorAttributeName: VGSecondary}];
        self.vaultButton.configuration = c;
    }
    NSSet *picked = nil;
    if (self.selecting) {
        NSMutableSet *m = [NSMutableSet set];
        for (NSIndexPath *ip in self.table.indexPathsForSelectedRows) if (ip.section == kSecItems && ip.row < (NSInteger)self.oldItems.count) [m addObject:self.oldItems[ip.row].fileName];
        picked = m;
    }
    self.oldItems = self.items;
    [self.table reloadData];
    if (picked.count)
        [self.items enumerateObjectsUsingBlock:^(VGItem *i, NSUInteger idx, BOOL *stop) {
            if ([picked containsObject:i.fileName]) [self.table selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)idx inSection:kSecItems] animated:NO scrollPosition:UITableViewScrollPositionNone];
        }];
    if (self.selecting && !self.items.count) [self stopSelecting];
    if (!self.selecting) [self showNormalBarButtons];
    [self updateSelection];
    BOOL any = self.items.count || self.tasks.count || self.folders.count;
    self.empty.hidden = any;
    BOOL plain = self.vaultMode || self.folder != nil;
    // The main list counts everything outside the vault, including what is inside folders.
    NSUInteger counted = plain ? self.items.count : shown;
    long long countedBytes = plain ? [[self.items valueForKeyPath:@"@sum.bytes"] longLongValue] : shownBytes;
    self.storageLabel.hidden = counted == 0;
    self.table.tableHeaderView.hidden = plain ? self.items.count == 0 : NO;
    self.storageLabel.text = [NSString stringWithFormat:@"%lu %@ · %@ used", (unsigned long)counted,
                              counted == 1 ? @"video" : @"videos",
                              [NSByteCountFormatter stringFromByteCount:countedBytes countStyle:NSByteCountFormatterCountStyleFile]];
}

- (void)tasksChanged:(NSNotification *)n {
    NSArray *now = [VGEngine shared].tasks;
    VGTask *t = n.object;
    // Just a progress tick: update that row in place (no flicker). Otherwise rebuild.
    if (t && [now isEqualToArray:self.tasks]) {
        NSUInteger row = [self.tasks indexOfObject:t];
        if (row != NSNotFound) {
            VGTaskCell *c = (VGTaskCell *)[self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:kSecTasks]];
            if (c) [c configure:t];
            return;
        }
    }
    [self reload];
}

- (void)pauseAction:(UIButton *)sender {
    UIView *v = sender;
    while (v && ![v isKindOfClass:VGTaskCell.class]) v = v.superview;
    VGTask *t = ((VGTaskCell *)v).task;
    if (!t) return;
    if (t.state == VGTaskPaused) [[VGEngine shared] resumeTask:t];
    else [[VGEngine shared] pauseTask:t];
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
    if (item.photos && !VGDownloadDefaults.filesOnly) {
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
        fix.subtitle = @"Rebuild the video";
        [tools addObject:fix];
    }
    BOOL inVault = item.vault;
    if (YES) {
        UIMenu *fm = [UIMenu menuWithTitle:@"Move to Folder" image:[UIImage systemImageNamed:@"folder"] identifier:nil options:0
                                  children:[self folderChoicesFor:@[item] afterMove:nil]];
        [tools insertObject:fm atIndex:0];
    }
    [tools insertObject:[UIAction actionWithTitle:inVault ? @"Move out of Vault" : @"Move to Vault"
                                            image:[UIImage systemImageNamed:inVault ? @"lock.open" : @"lock"] identifier:nil
                                          handler:^(UIAction *a) { [ws moveItem:item toVault:!inVault]; }] atIndex:0];
    UIAction *del = [UIAction actionWithTitle:@"Delete" image:[UIImage systemImageNamed:@"trash"] identifier:nil
                                      handler:^(UIAction *a) { [ws confirmDelete:item]; }];
    del.attributes = UIMenuElementAttributesDestructive;
    if (inVault) {
        // Private Vault 2.0: everything that leaves the vault is grouped under Export.
        NSMutableArray *ex = [NSMutableArray array];
        if (item.photos && !VGDownloadDefaults.filesOnly) [ex addObject:[UIAction actionWithTitle:@"Photos" image:[UIImage systemImageNamed:@"photo.on.rectangle.angled"] identifier:nil handler:^(UIAction *a) { [VGActions saveToPhotos:item from:ws]; }]];
        [ex addObject:[UIAction actionWithTitle:@"Files" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *a) { [VGActions saveToFiles:item from:ws]; }]];
        [ex addObject:[UIAction actionWithTitle:@"Downloads (keep a copy here too)" image:[UIImage systemImageNamed:@"arrow.down.circle"] identifier:nil handler:^(UIAction *a) {
            [[VGEngine shared] copyItemToDownloads:item completion:^(NSString *err) {
                if (err) [VGActions alert:@"Couldn't export it" message:err from:ws];
                else [VGActions toast:@"Copied to Downloads" icon:@"arrow.down.circle.fill" in:ws.view.window ?: ws.view];
            }];
        }]];
        [ex addObject:[UIAction actionWithTitle:@"Share…" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *a) { [VGActions share:item from:ws source:source]; }]];
        actions = [NSMutableArray arrayWithObjects:actions[0], [UIMenu menuWithTitle:@"Export" image:[UIImage systemImageNamed:@"square.and.arrow.up.on.square"] identifier:nil options:0 children:ex], nil];
    }
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

#pragma mark Folders

- (UIImage *)folderIcon:(VGFolder *)f {
    return [[UIImage systemImageNamed:@"folder.fill"] imageWithTintColor:f.color renderingMode:UIImageRenderingModeAlwaysOriginal];
}

/// The menu entries for sorting `items`: each folder, New Folder, and Remove from Folder. `after` runs once a choice is made.
- (NSArray<UIMenuElement *> *)folderChoicesFor:(NSArray<VGItem *> *)items afterMove:(void (^)(void))after {
    NSMutableArray<UIMenuElement *> *out = [NSMutableArray array];
    if (!items.count) return out;
    __weak typeof(self) ws = self;
    [out addObject:[UIAction actionWithTitle:@"New Folder\u2026" image:[UIImage systemImageNamed:@"folder.badge.plus"] identifier:nil
                                     handler:^(UIAction *a) { [ws newFolderFor:items afterMove:after]; }]];
    NSMutableArray<UIMenuElement *> *list = [NSMutableArray array];
    for (VGFolder *f in (self.vaultMode ? [VGEngine shared].vaultFolders : [VGEngine shared].folders)) {
        UIAction *a = [UIAction actionWithTitle:f.name image:[self folderIcon:f] identifier:nil handler:^(UIAction *x) {
            [ws moveItems:items toFolder:f];
            if (after) after();
        }];
        BOOL allIn = YES;
        for (VGItem *i in items) if (![i.folderID isEqualToString:f.identifier]) { allIn = NO; break; }
        if (allIn) a.state = UIMenuElementStateOn;
        [list addObject:a];
    }
    if (list.count) [out addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:list]];
    BOOL anyIn = NO;
    for (VGItem *i in items) if (i.folderID.length) { anyIn = YES; break; }
    if (anyIn) {
        [out addObject:[UIAction actionWithTitle:@"Remove from Folder" image:[UIImage systemImageNamed:@"folder.badge.minus"] identifier:nil handler:^(UIAction *x) {
            [ws moveItems:items toFolder:nil];
            if (after) after();
        }]];
    }
    return out;
}

- (void)moveItems:(NSArray<VGItem *> *)items toFolder:(nullable VGFolder *)f {
    [[VGEngine shared] setItems:items folder:f];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    NSString *what = items.count == 1 ? @"1 video" : [NSString stringWithFormat:@"%lu videos", (unsigned long)items.count];
    [VGActions toast:f ? [NSString stringWithFormat:@"Moved %@ to \u201C%@\u201D", what, f.name] : [NSString stringWithFormat:@"Moved %@ out of the folder", what]
                icon:@"folder.fill" in:self.view.window ?: self.view];
}

- (void)newFolderTapped { [self newFolderFor:nil afterMove:nil]; }

/// Opens the folder sheet. Once saved the new folder is made, and `items` (if any) are put in it.
- (void)newFolderFor:(nullable NSArray<VGItem *> *)items afterMove:(nullable void (^)(void))after {
    __weak typeof(self) ws = self;
    UINavigationController *sheet = [VGFolderEditorViewController sheetWithFolder:nil onSave:^(NSString *name, NSString *hex) {
        VGFolder *f = [[VGEngine shared] createFolderNamed:name colorHex:hex vault:ws.vaultMode];
        if (items.count) [ws moveItems:items toFolder:f];
        else [VGActions toast:[NSString stringWithFormat:@"Folder \u201C%@\u201D made", f.name] icon:@"folder.fill" in:ws.view.window ?: ws.view];
        if (after) after();
    }];
    [[self topPresenter] presentViewController:sheet animated:YES completion:nil];
}

- (void)editFolder:(VGFolder *)f {
    UINavigationController *sheet = [VGFolderEditorViewController sheetWithFolder:f onSave:^(NSString *name, NSString *hex) {
        [[VGEngine shared] updateFolder:f name:name colorHex:hex];
    }];
    [[self topPresenter] presentViewController:sheet animated:YES completion:nil];
}

- (void)confirmDeleteFolder:(VGFolder *)f {
    NSUInteger n = [[VGEngine shared] itemsInFolder:f].count;
    NSString *msg = n ? [NSString stringWithFormat:@"The %lu %@ inside will go back to Downloads. No videos are deleted.", (unsigned long)n, n == 1 ? @"video" : @"videos"]
                      : @"The folder is empty, so nothing else changes.";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Delete \u201C%@\u201D?", f.name] message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete Folder" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[VGEngine shared] deleteFolder:f];
    }]];
    [[self topPresenter] presentViewController:a animated:YES completion:nil];
}

- (UIMenu *)menuForFolder:(VGFolder *)f {
    __weak typeof(self) ws = self;
    UIAction *edit = [UIAction actionWithTitle:@"Rename or Change Color" image:[UIImage systemImageNamed:@"paintpalette"] identifier:nil
                                       handler:^(UIAction *a) { [ws editFolder:f]; }];
    UIAction *del = [UIAction actionWithTitle:@"Delete Folder" image:[UIImage systemImageNamed:@"trash"] identifier:nil
                                      handler:^(UIAction *a) { [ws confirmDeleteFolder:f]; }];
    del.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithChildren:@[edit, del]];
}

#pragma mark Import

- (void)importFromPhotos {
    PHPickerConfiguration *cfg = [PHPickerConfiguration new];
    cfg.filter = [PHPickerFilter videosFilter];
    cfg.selectionLimit = 0;   // as many as you like
    cfg.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;   // the original, not a re-encoded copy
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)importFromFiles {
    UIDocumentPickerViewController *d = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeMovie, UTTypeAudio] asCopy:YES];
    d.allowsMultipleSelection = YES;
    d.delegate = self;
    [self presentViewController:d animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    if (!results.count) { [picker dismissViewControllerAnimated:YES completion:nil]; return; }
    [self beginImport:results.count];
    __weak typeof(self) ws = self;
    for (PHPickerResult *r in results) {
        NSItemProvider *prov = r.itemProvider;
        NSString *name = prov.suggestedName;
        [prov loadFileRepresentationForTypeIdentifier:UTTypeMovie.identifier completionHandler:^(NSURL *url, NSError *error) {
            // The file is only there until this block ends, so it's moved into the library right here.
            if (!url) {
                dispatch_async(dispatch_get_main_queue(), ^{ [ws importOne:nil error:error.localizedDescription ?: @"Couldn't read one of the videos."]; });
                return;
            }
            [[VGEngine shared] importFileAtURL:url title:name source:@"Photos" move:YES completion:^(VGItem *item, NSString *err) { [ws importOne:item error:err]; }];
        }];
    }
    [picker dismissViewControllerAnimated:YES completion:^{ [ws showImportAlert]; }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!urls.count) return;
    [self beginImport:urls.count];
    __weak typeof(self) ws = self;
    for (NSURL *u in urls) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [[VGEngine shared] importFileAtURL:u title:nil source:@"Files" move:YES completion:^(VGItem *item, NSString *err) { [ws importOne:item error:err]; }];
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws showImportAlert]; });
}

- (void)beginImport:(NSInteger)count {
    self.importTotal = count;
    self.importFinished = 0;
    self.importOK = 0;
    self.importErrors = [NSMutableArray array];
    self.importAlertState = 0;
    NSString *t = count == 1 ? @"Importing…" : [NSString stringWithFormat:@"Importing %ld videos…", (long)count];
    self.importAlert = [UIAlertController alertControllerWithTitle:t message:@"Long videos can take a moment." preferredStyle:UIAlertControllerStyleAlert];
}

- (UIViewController *)topPresenter {
    UIViewController *top = self;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

- (void)showImportAlert {
    if (!self.importAlert || self.importAlertState != 0) return;
    if (self.importFinished >= self.importTotal) { [self finishImport]; return; }   // already done: no need to show it
    self.importAlertState = 1;
    [[self topPresenter] presentViewController:self.importAlert animated:YES completion:^{ self.importAlertState = 2; [self finishImport]; }];
}

// Always on the main queue.
- (void)importOne:(VGItem *)item error:(NSString *)err {
    self.importFinished++;
    if (item) {
        self.importOK++;
        if (self.vaultMode) [[VGEngine shared] setItem:item inVault:YES];   // imported while inside the vault: keep it there
        if (self.folder) [[VGEngine shared] setItems:@[item] folder:self.folder];   // imported inside a folder: it goes in that folder
    } else if (err.length) {
        [self.importErrors addObject:err];
    }
    [self finishImport];
}

- (void)finishImport {
    if (!self.importAlert || self.importFinished < self.importTotal) return;
    if (self.importAlertState == 1) return;   // still appearing: it calls this again once it is up
    UIAlertController *wait = self.importAlert;
    BOOL showing = self.importAlertState == 2;
    self.importAlert = nil;
    self.importAlertState = 0;
    __weak typeof(self) ws = self;
    void (^report)(void) = ^{
        VGDownloadsViewController *me = ws;
        if (!me) return;
        if (me.importErrors.count) {
            NSArray *lines = [me.importErrors subarrayWithRange:NSMakeRange(0, MIN(3, me.importErrors.count))];
            NSString *msg = [lines componentsJoinedByString:@"\n\n"];
            if (me.importErrors.count > 3) msg = [msg stringByAppendingFormat:@"\n\n…and %lu more.", (unsigned long)(me.importErrors.count - 3)];
            if (me.importOK) msg = [NSString stringWithFormat:@"Imported %ld, but:\n\n%@", (long)me.importOK, msg];
            [VGActions alert:@"Couldn't import everything" message:msg from:[me topPresenter]];
        } else {
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            [VGActions toast:me.importOK == 1 ? @"Imported 1 video" : [NSString stringWithFormat:@"Imported %ld videos", (long)me.importOK]
                        icon:@"checkmark.circle.fill" in:me.view.window ?: me.view];
        }
    };
    if (showing) [wait dismissViewControllerAnimated:YES completion:report];
    else if (self.presentedViewController.isBeingDismissed) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), report);   // the picker is still closing
    else report();
}

#pragma mark Select

NSString *const VGSelectModeDidChangeNotification = @"VGSelectModeDidChange";

- (void)showNormalBarButtons {
    BOOL can = self.items.count > 0;
    if (self.vaultMode && !self.folder) {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItems = can ? @[self.selectItem, self.importItem, self.addFolderItem] : @[self.importItem, self.addFolderItem];
    } else if (self.vaultMode || self.folder) {
        self.navigationItem.leftBarButtonItem = nil;   // keeps the back button
        self.navigationItem.rightBarButtonItems = can ? @[self.selectItem, self.importItem] : @[self.importItem];
    } else {
        self.navigationItem.leftBarButtonItem = can ? self.selectItem : nil;
        self.navigationItem.rightBarButtonItems = @[self.importItem, self.addFolderItem];
    }
}

- (void)startSelecting {
    if (self.selecting || !self.items.count) return;
    self.selecting = YES;
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self.table setEditing:YES animated:YES];
    self.navigationItem.hidesBackButton = YES;
    if (self.blankTitle) self.navigationItem.titleView = nil;   // show the small "N selected" title at the top
    UIBarButtonItem *all = [[UIBarButtonItem alloc] initWithTitle:@"Select All" style:UIBarButtonItemStylePlain target:self action:@selector(toggleAll)];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(stopSelecting)];
    [all setTitleTextAttributes:@{NSFontAttributeName: VGFont(17, UIFontWeightSemibold)} forState:UIControlStateNormal];
    [done setTitleTextAttributes:@{NSFontAttributeName: VGFont(17, UIFontWeightBold)} forState:UIControlStateNormal];
    self.navigationItem.leftBarButtonItem = all;
    self.navigationItem.rightBarButtonItem = done;
    self.vaultButton.enabled = NO;
    self.actionBar.hidden = NO;
    self.actionBar.transform = CGAffineTransformMakeTranslation(0, 40);
    self.actionBar.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{ self.actionBar.transform = CGAffineTransformIdentity; self.actionBar.alpha = 1; }];
    UIEdgeInsets in = self.table.contentInset;
    in.bottom = 96;
    self.table.contentInset = in;
    [self dimFolders:YES];
    [NSNotificationCenter.defaultCenter postNotificationName:VGSelectModeDidChangeNotification object:@YES];
    [self updateSelection];
}

- (void)stopSelecting {
    if (!self.selecting) return;
    self.selecting = NO;
    [self.table setEditing:NO animated:YES];
    self.navigationItem.hidesBackButton = NO;
    if (self.blankTitle) self.navigationItem.titleView = self.blankTitle;
    self.vaultButton.enabled = YES;
    [UIView animateWithDuration:0.2 animations:^{ self.actionBar.transform = CGAffineTransformMakeTranslation(0, 40); self.actionBar.alpha = 0; }
                     completion:^(BOOL f) { if (!self.selecting) self.actionBar.hidden = YES; }];
    UIEdgeInsets in = self.table.contentInset;
    in.bottom = 76;
    self.table.contentInset = in;
    self.title = self.vaultMode ? @"Private Vault 2.0" : (self.folder ? [[VGEngine shared] folderWithID:self.folder.identifier].name : @"Downloads");
    [self showNormalBarButtons];
    [self dimFolders:NO];
    [NSNotificationCenter.defaultCenter postNotificationName:VGSelectModeDidChangeNotification object:@NO];
}

// Folders can't be picked in Select mode, so they fade while it is on.
- (void)dimFolders:(BOOL)dim {
    for (UITableViewCell *c in self.table.visibleCells)
        if ([c isKindOfClass:VGFolderCell.class]) [UIView animateWithDuration:0.2 animations:^{ c.contentView.alpha = dim ? 0.35 : 1; }];
}

- (NSArray<VGItem *> *)selectedItems {
    NSMutableArray *out = [NSMutableArray array];
    NSArray *rows = [self.table.indexPathsForSelectedRows sortedArrayUsingSelector:@selector(compare:)];
    for (NSIndexPath *ip in rows) if (ip.section == kSecItems && ip.row < (NSInteger)self.items.count) [out addObject:self.items[ip.row]];
    return out;
}

- (void)toggleAll {
    BOOL all = self.selectedItems.count == self.items.count;
    for (NSInteger r = 0; r < (NSInteger)self.items.count; r++) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:r inSection:kSecItems];
        if (all) [self.table deselectRowAtIndexPath:ip animated:NO];
        else [self.table selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self updateSelection];
}

- (void)updateSelection {
    if (!self.selecting) return;
    NSArray *sel = self.selectedItems;
    NSUInteger n = sel.count;
    self.title = n ? [NSString stringWithFormat:@"%lu selected", (unsigned long)n] : @"Select videos";
    self.navigationItem.leftBarButtonItem.title = (n && n == self.items.count) ? @"Deselect All" : @"Select All";
    for (UIButton *b in self.actionButtons) b.enabled = n > 0;
    long long bytes = [[sel valueForKeyPath:@"@sum.bytes"] longLongValue];
    if (n) self.storageLabel.text = [NSString stringWithFormat:@"%lu of %lu selected · %@", (unsigned long)n, (unsigned long)self.items.count,
                                     [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile]];
}

- (UIButton *)actionButton:(NSString *)title icon:(NSString *)icon tint:(UIColor *)tint action:(SEL)sel {
    UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
    c.image = [UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold]];
    c.imagePlacement = NSDirectionalRectEdgeTop;
    c.imagePadding = 5;
    c.baseForegroundColor = tint;
    c.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: VGFont(11, UIFontWeightBold)}];
    c.contentInsets = NSDirectionalEdgeInsetsMake(8, 2, 8, 2);
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    b.configurationUpdateHandler = ^(UIButton *btn) { btn.alpha = btn.enabled ? 1 : 0.35; };
    return b;
}

- (void)buildActionBar {
    UIView *bar = [UIView new];
    bar.backgroundColor = [VGSurface2 colorWithAlphaComponent:0.98];
    bar.layer.cornerRadius = 22;
    bar.layer.cornerCurve = kCACornerCurveContinuous;
    bar.layer.borderColor = VGStroke.CGColor;
    bar.layer.borderWidth = 1;
    bar.layer.shadowColor = UIColor.blackColor.CGColor;
    bar.layer.shadowOpacity = 0.5;
    bar.layer.shadowRadius = 16;
    bar.layer.shadowOffset = CGSizeMake(0, 6);
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.hidden = YES;

    UIButton *photos = [self actionButton:@"Photos" icon:@"photo.on.rectangle.angled" tint:VGText action:@selector(batchPhotos)];
    self.batchPhotosButton = photos;
    photos.hidden = VGDownloadDefaults.filesOnly;
    UIButton *files = [self actionButton:@"Files" icon:@"folder" tint:VGText action:@selector(batchFiles)];
    UIButton *share = [self actionButton:@"Share" icon:@"square.and.arrow.up" tint:VGText action:@selector(batchShare:)];
    self.vaultAction = [self actionButton:self.vaultMode ? @"Unlock" : @"Vault" icon:self.vaultMode ? @"lock.open" : @"lock" tint:VGText action:@selector(batchVault)];
    UIButton *del = [self actionButton:@"Delete" icon:@"trash" tint:VGHex(0xFF5A5F) action:@selector(batchDelete)];
    NSMutableArray<UIButton *> *buttons = [@[photos, files, share, self.vaultAction, del] mutableCopy];
    if (YES) {
        // A menu that is built each time it opens, so it always lists the folders as they are now.
        self.folderAction = [self actionButton:@"Folder" icon:@"folder.badge.plus" tint:VGText action:@selector(stopSelecting)];
        [self.folderAction removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        __weak typeof(self) wsf = self;
        UIDeferredMenuElement *dyn = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
            VGDownloadsViewController *me = wsf;
            completion(me ? [me folderChoicesFor:me.selectedItems afterMove:^{ [me stopSelecting]; }] : @[]);
        }];
        self.folderAction.menu = [UIMenu menuWithChildren:@[dyn]];
        self.folderAction.showsMenuAsPrimaryAction = YES;
        [buttons insertObject:self.folderAction atIndex:3];
    }
    self.actionButtons = buttons;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:self.actionButtons];
    row.distribution = UIStackViewDistributionFillEqually;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:row];
    [self.view addSubview:bar];
    self.actionBar = bar;
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [bar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [bar.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-10],
        [row.topAnchor constraintEqualToAnchor:bar.topAnchor constant:4],
        [row.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-4],
        [row.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:6],
        [row.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-6],
    ]];
}

- (void)batchPhotos {
    NSArray *sel = self.selectedItems;
    [VGActions saveItemsToPhotos:sel from:self];
    [self stopSelecting];
}

- (void)batchFiles {
    [VGActions saveItemsToFiles:self.selectedItems from:self];
    [self stopSelecting];
}

- (void)batchShare:(UIButton *)sender {
    [VGActions shareItems:self.selectedItems from:self source:sender];
    [self stopSelecting];
}

- (void)batchVault {
    NSArray *sel = self.selectedItems;
    BOOL toVault = !self.vaultMode;
    [self stopSelecting];
    for (VGItem *i in sel) [[VGEngine shared] setItem:i inVault:toVault];
    NSString *what = sel.count == 1 ? @"1 video" : [NSString stringWithFormat:@"%lu videos", (unsigned long)sel.count];
    [VGActions toast:toVault ? [NSString stringWithFormat:@"Moved %@ to Private Vault 2.0", what] : [NSString stringWithFormat:@"Moved %@ out of the vault", what]
                icon:toVault ? @"lock.fill" : @"lock.open.fill" in:self.view.window ?: self.view];
}

- (void)batchDelete {
    NSArray *sel = self.selectedItems;
    if (!sel.count) return;
    NSString *what = sel.count == 1 ? @"this download" : [NSString stringWithFormat:@"%lu downloads", (unsigned long)sel.count];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Delete %@?", what]
                                                               message:@"They will be removed from VidGrab. Copies saved to Photos or Files are kept."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [self stopSelecting];
        for (VGItem *i in sel) [[VGEngine shared] deleteItem:i];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == kSecTasks) return (NSInteger)self.tasks.count;
    if (section == kSecFolders) return (NSInteger)self.folders.count;
    return (NSInteger)self.items.count;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    NSString *title = nil;
    if (section == kSecTasks) {
        if (!self.tasks.count) return nil;
        title = [VGEngine shared].activeCount == 0 ? @"NEEDS ATTENTION" : [NSString stringWithFormat:@"IN PROGRESS · %lu", (unsigned long)[VGEngine shared].activeCount];
    } else if (section == kSecFolders) {
        if (!self.folders.count) return nil;
        title = [NSString stringWithFormat:@"FOLDERS · %lu", (unsigned long)self.folders.count];
    } else {
        if (!self.items.count || !(self.tasks.count || self.folders.count)) return nil;
        title = @"SAVED";
    }
    UILabel *l = [UILabel new];
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
    if (section == kSecFolders) return self.folders.count ? 30 : 0.01;
    if (section == kSecTasks) return self.tasks.count ? (self.folders.count ? 36 : 30) : 0.01;
    return (self.items.count && (self.tasks.count || self.folders.count)) ? 36 : 0.01;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == kSecFolders ? 76 : 92;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == kSecTasks) {
        VGTaskCell *c = [tv dequeueReusableCellWithIdentifier:@"t" forIndexPath:ip];
        [c configure:self.tasks[ip.row]];
        [c.action removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [c.action addTarget:self action:@selector(taskAction:) forControlEvents:UIControlEventTouchUpInside];
        [c.pauseButton addTarget:self action:@selector(pauseAction:) forControlEvents:UIControlEventTouchUpInside];
        return c;
    }
    if (ip.section == kSecFolders) {
        VGFolderCell *c = [tv dequeueReusableCellWithIdentifier:@"f" forIndexPath:ip];
        VGFolder *f = self.folders[ip.row];
        NSArray *inside = [[VGEngine shared] itemsInFolder:f];
        [c configure:f count:inside.count bytes:[[inside valueForKeyPath:@"@sum.bytes"] longLongValue]];
        c.more.menu = [self menuForFolder:f];
        c.contentView.alpha = self.selecting ? 0.35 : 1;
        return c;
    }
    VGDownloadCell *c = [tv dequeueReusableCellWithIdentifier:@"d" forIndexPath:ip];
    VGItem *item = self.items[ip.row];
    [c configure:item];
    c.more.menu = [self menuFor:item source:c.more];
    return c;
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == kSecFolders) return NO;
    return !self.selecting || ip.section == kSecItems;
}

- (NSIndexPath *)tableView:(UITableView *)tv willSelectRowAtIndexPath:(NSIndexPath *)ip {
    return (self.selecting && ip.section != kSecItems) ? nil : ip;
}

// Two-finger swipe down the list starts Select and picks rows as you go, like Photos.
- (BOOL)tableView:(UITableView *)tv shouldBeginMultipleSelectionInteractionAtIndexPath:(NSIndexPath *)ip {
    return ip.section == kSecItems;
}

- (void)tableView:(UITableView *)tv didBeginMultipleSelectionInteractionAtIndexPath:(NSIndexPath *)ip {
    if (!self.selecting) [self startSelecting];
}

- (void)tableView:(UITableView *)tv didDeselectRowAtIndexPath:(NSIndexPath *)ip {
    if (self.selecting) [self updateSelection];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (self.selecting) { [self updateSelection]; return; }
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == kSecFolders) {
        VGDownloadsViewController *v = [VGDownloadsViewController new];
        v.vaultMode = self.vaultMode;
        v.folder = self.folders[ip.row];
        [self.navigationController pushViewController:v animated:YES];
        return;
    }
    if (ip.section == kSecTasks) {
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
    if (ip.section == kSecFolders) {
        VGFolder *f = self.folders[ip.row];
        UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
                                                                        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [self confirmDeleteFolder:f];
            done(NO);   // the alert decides; the row stays until then
        }];
        del.image = [UIImage systemImageNamed:@"trash.fill"];
        UIContextualAction *edit = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Edit"
                                                                         handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [self editFolder:f];
            done(YES);
        }];
        edit.image = [UIImage systemImageNamed:@"paintpalette.fill"];
        edit.backgroundColor = VGHex(0x3A3A46);
        return [UISwipeActionsConfiguration configurationWithActions:@[del, edit]];
    }
    if (ip.section == kSecTasks) {
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
    if (self.selecting || ip.section == kSecTasks) return nil;
    if (ip.section == kSecFolders) {
        VGFolder *f = self.folders[ip.row];
        return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
                                                        actionProvider:^UIMenu *(NSArray *s) { return [self menuForFolder:f]; }];
    }
    VGItem *item = self.items[ip.row];
    UIView *cell = [tv cellForRowAtIndexPath:ip];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray *s) { return [self menuFor:item source:cell]; }];
}

@end
