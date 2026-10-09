#import "VGLibraryViewController.h"
#import "VGSavedPlaylistsViewController.h"
#import "VGEngine.h"
#import "VGActions.h"
#import "VGTheme.h"
#import "VGAudioEditorViewController.h"
#import "VGFolderEditorViewController.h"

typedef NS_ENUM(NSInteger, VGLibMode) { VGLibAll, VGLibRecent, VGLibFavorites, VGLibFolders };
typedef NS_ENUM(NSInteger, VGLibSort) { VGLibSortDate, VGLibSortName, VGLibSortSize, VGLibSortDuration };

static NSString *const kSortKey = @"vgLibSort", *const kSortUpKey = @"vgLibSortUp", *const kGridKey = @"vgLibGrid";

#pragma mark - Cells

@interface VGLibCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumb, *heart, *check;
@property (nonatomic, strong) UILabel *titleLabel, *subLabel, *badge;
@property (nonatomic) BOOL grid, audio;
- (void)configureWith:(VGItem *)item grid:(BOOL)grid selecting:(BOOL)selecting;
@end

@implementation VGLibCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _thumb = [UIImageView new];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.backgroundColor = VGSurface2;
        _thumb.layer.cornerRadius = 10;
        _thumb.layer.cornerCurve = kCACornerCurveContinuous;
        _titleLabel = [UILabel new];
        _titleLabel.font = VGFont(14, UIFontWeightSemibold);
        _titleLabel.textColor = VGText;
        _subLabel = [UILabel new];
        _subLabel.font = VGFont(12, UIFontWeightMedium);
        _subLabel.textColor = VGSecondary;
        _badge = [UILabel new];
        _badge.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightBold];
        _badge.textColor = VGText;
        _badge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
        _badge.layer.cornerRadius = 4;
        _badge.clipsToBounds = YES;
        _badge.textAlignment = NSTextAlignmentCenter;
        _heart = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]];
        _heart.tintColor = VGAccent;
        _check = [UIImageView new];
        _check.tintColor = VGAccent;
        _check.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        _check.layer.cornerRadius = 11;
        for (UIView *v in @[_thumb, _titleLabel, _subLabel, _badge, _heart, _check]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self updateCheck];
}

- (void)updateCheck {
    if (self.check.hidden) return;
    self.check.contentMode = UIViewContentModeScaleAspectFit;
    self.check.image = [UIImage systemImageNamed:self.selected ? @"checkmark.circle.fill" : @"circle"];
    self.check.tintColor = self.selected ? VGAccent : UIColor.whiteColor;
}

- (void)configureWith:(VGItem *)item grid:(BOOL)grid selecting:(BOOL)selecting {
    self.grid = grid;
    self.audio = item.audio;
    [NSLayoutConstraint deactivateConstraints:self.contentView.constraints];
    UIView *c = self.contentView;
    self.titleLabel.text = item.title;
    NSMutableArray *bits = [NSMutableArray array];
    if (item.audio && item.artist.length) [bits addObject:item.artist];
    if (item.audio && item.album.length) [bits addObject:item.album];
    if (!item.audio || !bits.count) {
        [bits addObject:[NSByteCountFormatter stringFromByteCount:item.bytes countStyle:NSByteCountFormatterCountStyleFile]];
        if (!item.audio && item.res.length) [bits addObject:item.res];
    }
    static NSDateFormatter *added;
    if (!added) { added = [NSDateFormatter new]; added.dateStyle = NSDateFormatterMediumStyle; added.timeStyle = NSDateFormatterNoStyle; }
    if (item.date) [bits addObject:[added stringFromDate:item.date]];   // the day it was added
    self.subLabel.text = [bits componentsJoinedByString:@" · "];
    NSString *d = VGDuration(item.duration);
    self.badge.text = d ? [NSString stringWithFormat:@" %@ ", d] : nil;
    self.badge.hidden = !d || !grid;
    self.heart.hidden = !item.favorite;
    self.check.hidden = !selecting;
    [self updateCheck];
    UIImage *img = item.thumbnailImage;
    self.thumb.image = img ?: (item.audio ? [UIImage systemImageNamed:@"music.note" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightLight]] : nil);
    self.thumb.contentMode = img ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
    self.thumb.tintColor = VGTertiary;
    self.titleLabel.numberOfLines = grid ? 2 : 1;
    if (grid) {
        CGFloat ratio = item.audio ? 1.0 : 9.0 / 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [self.thumb.topAnchor constraintEqualToAnchor:c.topAnchor],
            [self.thumb.leadingAnchor constraintEqualToAnchor:c.leadingAnchor],
            [self.thumb.trailingAnchor constraintEqualToAnchor:c.trailingAnchor],
            [self.thumb.heightAnchor constraintEqualToAnchor:self.thumb.widthAnchor multiplier:ratio],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.thumb.bottomAnchor constant:6],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:2],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-2],
            [self.subLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2],
            [self.subLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.subLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
            [self.badge.trailingAnchor constraintEqualToAnchor:self.thumb.trailingAnchor constant:-6],
            [self.badge.bottomAnchor constraintEqualToAnchor:self.thumb.bottomAnchor constant:-6],
            [self.heart.topAnchor constraintEqualToAnchor:self.thumb.topAnchor constant:6],
            [self.heart.leadingAnchor constraintEqualToAnchor:self.thumb.leadingAnchor constant:6],
            [self.heart.widthAnchor constraintEqualToConstant:18], [self.heart.heightAnchor constraintEqualToConstant:18],
            [self.check.topAnchor constraintEqualToAnchor:self.thumb.topAnchor constant:6],
            [self.check.trailingAnchor constraintEqualToAnchor:self.thumb.trailingAnchor constant:-6],
            [self.check.widthAnchor constraintEqualToConstant:22], [self.check.heightAnchor constraintEqualToConstant:22],
        ]];
    } else {
        CGFloat w = item.audio ? 56 : 100, h = item.audio ? 56 : 56;
        [NSLayoutConstraint activateConstraints:@[
            [self.thumb.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
            [self.thumb.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
            [self.thumb.widthAnchor constraintEqualToConstant:w], [self.thumb.heightAnchor constraintEqualToConstant:h],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.thumb.trailingAnchor constant:12],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-44],
            [self.titleLabel.bottomAnchor constraintEqualToAnchor:c.centerYAnchor constant:-1],
            [self.subLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.subLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
            [self.subLabel.topAnchor constraintEqualToAnchor:c.centerYAnchor constant:2],
            [self.badge.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-12],
            [self.badge.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
            [self.heart.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-14],
            [self.heart.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
            [self.heart.widthAnchor constraintEqualToConstant:18], [self.heart.heightAnchor constraintEqualToConstant:18],
            [self.check.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-12],
            [self.check.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
            [self.check.widthAnchor constraintEqualToConstant:22], [self.check.heightAnchor constraintEqualToConstant:22],
        ]];
        // In the list the length sits in the second line.
        NSString *dd = VGDuration(item.duration);
        if (dd) self.subLabel.text = [self.subLabel.text stringByAppendingFormat:@" · %@", dd];
        self.heart.hidden = !item.favorite || selecting;
    }
}

@end

@interface VGLibFolderCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *titleLabel, *subLabel;
@end

@implementation VGLibFolderCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _icon = [UIImageView new];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _titleLabel = [UILabel new];
        _titleLabel.font = VGFont(16, UIFontWeightSemibold);
        _titleLabel.textColor = VGText;
        _subLabel = [UILabel new];
        _subLabel.font = VGFont(12, UIFontWeightMedium);
        _subLabel.textColor = VGSecondary;
        UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        chev.tintColor = VGTertiary;
        for (UIView *v in @[_icon, _titleLabel, _subLabel, chev]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self.contentView addSubview:v]; }
        UIView *c = self.contentView;
        [NSLayoutConstraint activateConstraints:@[
            [_icon.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16], [_icon.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
            [_icon.widthAnchor constraintEqualToConstant:40], [_icon.heightAnchor constraintEqualToConstant:34],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:12],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:chev.leadingAnchor constant:-8],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:c.centerYAnchor constant:-1],
            [_subLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor], [_subLabel.topAnchor constraintEqualToAnchor:c.centerYAnchor constant:2],
            [chev.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16], [chev.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
        ]];
    }
    return self;
}
@end

#pragma mark - Screen

@interface VGLibraryViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UICollectionView *collection;
@property (nonatomic, strong) UISegmentedControl *kind;
@property (nonatomic, strong) NSArray<UIButton *> *chips;
@property (nonatomic, strong) UILabel *summary, *empty;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic) VGLibMode mode;
@property (nonatomic) VGLibSort sort;
@property (nonatomic) BOOL sortUp, grid, selecting;
@property (nonatomic, strong) VGFolder *openFolder;
@property (nonatomic, copy) NSArray<VGItem *> *rows;
@property (nonatomic, copy) NSArray<VGFolder *> *folderRows;
@property (nonatomic, strong) UIBarButtonItem *gridItem, *sortItem, *selectItem, *addFolderItem;
@property (nonatomic, strong) UIStackView *actionBar;
@property (nonatomic, strong) UIView *header;
@end

@implementation VGLibraryViewController

- (instancetype)init {
    if ((self = [super init])) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        _sort = (VGLibSort)[d integerForKey:kSortKey];
        _sortUp = [d boolForKey:kSortUpKey];
        _grid = [d objectForKey:kGridKey] ? [d boolForKey:kGridKey] : YES;
        self.title = @"Library";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VGBackground;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Search your library";
    self.search.searchBar.tintColor = VGAccent;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"music.note.list"] style:UIBarButtonItemStylePlain target:self action:@selector(openPlaylists)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = @"Saved playlists";
    self.navigationItem.leftItemsSupplementBackButton = YES;
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.kind = [[UISegmentedControl alloc] initWithItems:@[@"Videos", @"Audio"]];
    self.kind.selectedSegmentIndex = 0;
    [self.kind addTarget:self action:@selector(kindChanged) forControlEvents:UIControlEventValueChanged];

    NSArray *names = @[@"All", @"Recently Added", @"Favorites", @"Folders"];
    NSMutableArray *chips = [NSMutableArray array];
    UIStackView *chipRow = [UIStackView new];
    chipRow.spacing = 8;
    for (NSUInteger i = 0; i < names.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = (NSInteger)i;
        [b setTitle:names[i] forState:UIControlStateNormal];
        b.titleLabel.font = VGFont(13, UIFontWeightBold);
        b.contentEdgeInsets = UIEdgeInsetsMake(7, 14, 7, 14);
        b.layer.cornerRadius = 16;
        b.layer.cornerCurve = kCACornerCurveContinuous;
        [b addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [chips addObject:b];
        [chipRow addArrangedSubview:b];
    }
    self.chips = chips;
    UIScrollView *chipScroll = [UIScrollView new];
    chipScroll.showsHorizontalScrollIndicator = NO;
    chipRow.translatesAutoresizingMaskIntoConstraints = NO;
    [chipScroll addSubview:chipRow];
    [NSLayoutConstraint activateConstraints:@[
        [chipRow.leadingAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.leadingAnchor constant:16],
        [chipRow.trailingAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.trailingAnchor constant:-16],
        [chipRow.topAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.topAnchor],
        [chipRow.bottomAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.bottomAnchor],
        [chipRow.heightAnchor constraintEqualToAnchor:chipScroll.frameLayoutGuide.heightAnchor],
        [chipScroll.heightAnchor constraintEqualToConstant:34],
    ]];

    self.summary = [UILabel new];
    self.summary.font = VGFont(12, UIFontWeightMedium);
    self.summary.textColor = VGTertiary;

    UIView *segHolder = [UIView new];
    self.kind.translatesAutoresizingMaskIntoConstraints = NO;
    [segHolder addSubview:self.kind];
    [NSLayoutConstraint activateConstraints:@[
        [self.kind.leadingAnchor constraintEqualToAnchor:segHolder.leadingAnchor constant:16], [self.kind.trailingAnchor constraintEqualToAnchor:segHolder.trailingAnchor constant:-16],
        [self.kind.topAnchor constraintEqualToAnchor:segHolder.topAnchor], [self.kind.bottomAnchor constraintEqualToAnchor:segHolder.bottomAnchor],
    ]];
    UIView *sumHolder = [UIView new];
    self.summary.translatesAutoresizingMaskIntoConstraints = NO;
    [sumHolder addSubview:self.summary];
    [NSLayoutConstraint activateConstraints:@[
        [self.summary.leadingAnchor constraintEqualToAnchor:sumHolder.leadingAnchor constant:18], [self.summary.trailingAnchor constraintEqualToAnchor:sumHolder.trailingAnchor constant:-16],
        [self.summary.topAnchor constraintEqualToAnchor:sumHolder.topAnchor], [self.summary.bottomAnchor constraintEqualToAnchor:sumHolder.bottomAnchor],
    ]];
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[segHolder, chipScroll, sumHolder]];
    head.axis = UILayoutConstraintAxisVertical;
    head.spacing = 10;
    head.translatesAutoresizingMaskIntoConstraints = NO;
    self.header = head;

    self.collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[self makeLayout]];
    self.collection.backgroundColor = VGBackground;
    self.collection.dataSource = self;
    self.collection.delegate = self;
    self.collection.alwaysBounceVertical = YES;
    self.collection.translatesAutoresizingMaskIntoConstraints = NO;
    [self.collection registerClass:VGLibCell.class forCellWithReuseIdentifier:@"i"];
    [self.collection registerClass:VGLibFolderCell.class forCellWithReuseIdentifier:@"f"];

    [self.view addSubview:self.collection];
    [self.view addSubview:head];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [head.topAnchor constraintEqualToAnchor:g.topAnchor constant:6],
        [head.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [head.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collection.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:4],
        [self.collection.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.collection.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collection.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.empty = [UILabel new];
    self.empty.font = VGFont(15, UIFontWeightMedium);
    self.empty.textColor = VGSecondary;
    self.empty.textAlignment = NSTextAlignmentCenter;
    self.empty.numberOfLines = 0;
    self.empty.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.empty];
    [NSLayoutConstraint activateConstraints:@[[self.empty.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
                                              [self.empty.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:40],
                                              [self.empty.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
                                              [self.empty.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40]]];

    [self buildActionBar];
    [self updateBarButtons];
    [self updateChips];
    [self reload];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(libraryChanged) name:VGLibraryDidChangeNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

#pragma mark Layout

- (UICollectionViewLayout *)makeLayout {
    __weak typeof(self) ws = self;
    return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> env) {
        CGFloat width = env.container.effectiveContentSize.width;
        BOOL foldersOnly = ws.mode == VGLibFolders && !ws.openFolder;
        if (ws.grid && !foldersOnly) {
            BOOL audio = ws.kind.selectedSegmentIndex == 1;
            NSInteger cols = width > 700 ? (audio ? 5 : 4) : (audio ? 3 : 2);
            CGFloat gap = 12, inset = 16;
            CGFloat cell = (width - inset * 2 - gap * (cols - 1)) / cols;
            CGFloat h = cell * (audio ? 1.0 : 9.0 / 16.0) + 6 + 36 + 16;
            NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0 / cols]
                                                                                                                      heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]]];
            NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                                                                                  heightDimension:[NSCollectionLayoutDimension absoluteDimension:h]]
                                                                                            subitem:item count:cols];
            group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:gap];
            NSCollectionLayoutSection *sec = [NSCollectionLayoutSection sectionWithGroup:group];
            sec.interGroupSpacing = 10;
            sec.contentInsets = NSDirectionalEdgeInsetsMake(6, inset, 24, inset);
            return sec;
        }
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                                                                  heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]]];
        NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup verticalGroupWithLayoutSize:[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                                                                              heightDimension:[NSCollectionLayoutDimension absoluteDimension:foldersOnly ? 64 : 74]]
                                                                                       subitems:@[item]];
        NSCollectionLayoutSection *sec = [NSCollectionLayoutSection sectionWithGroup:group];
        sec.contentInsets = NSDirectionalEdgeInsetsMake(2, 0, 24, 0);
        return sec;
    }];
}

#pragma mark Data

- (BOOL)showingFolderList { return self.mode == VGLibFolders && !self.openFolder; }

- (void)reload {
    BOOL audioKind = self.kind.selectedSegmentIndex == 1;
    NSString *q = [self.search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    VGEngine *e = [VGEngine shared];
    NSMutableArray<VGItem *> *all = [NSMutableArray array];
    NSDate *recentCutoff = [NSDate dateWithTimeIntervalSinceNow:-14 * 86400];
    for (VGItem *i in e.items) {
        if (i.vault) continue;
        if (i.audio != audioKind) continue;
        if (q.length) {
            NSString *hay = [@[i.title ?: @"", i.artist ?: @"", i.album ?: @"", i.site ?: @""] componentsJoinedByString:@" "];
            if ([hay rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
        }
        if (self.mode == VGLibRecent && [i.date compare:recentCutoff] == NSOrderedAscending) continue;
        if (self.mode == VGLibFavorites && !i.favorite) continue;
        if (self.mode == VGLibFolders && self.openFolder && ![i.folderID isEqualToString:self.openFolder.identifier]) continue;
        [all addObject:i];
    }
    BOOL up = self.sortUp;
    VGLibSort sort = self.mode == VGLibRecent ? VGLibSortDate : self.sort;
    if (self.mode == VGLibRecent) up = NO;
    [all sortUsingComparator:^NSComparisonResult(VGItem *a, VGItem *b) {
        NSComparisonResult r = NSOrderedSame;
        switch (sort) {
            case VGLibSortName: r = [a.title localizedCaseInsensitiveCompare:b.title]; break;
            case VGLibSortSize: r = a.bytes < b.bytes ? NSOrderedAscending : (a.bytes > b.bytes ? NSOrderedDescending : NSOrderedSame); break;
            case VGLibSortDuration: r = a.duration < b.duration ? NSOrderedAscending : (a.duration > b.duration ? NSOrderedDescending : NSOrderedSame); break;
            default: r = [a.date compare:b.date]; break;
        }
        return up ? r : -r;
    }];
    self.rows = all;

    NSMutableArray *fl = [NSMutableArray array];
    if ([self showingFolderList]) {
        for (VGFolder *f in e.folders) {
            if (q.length && [f.name rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
            [fl addObject:f];
        }
    }
    self.folderRows = fl;

    long long bytes = 0;
    for (VGItem *i in self.rows) bytes += i.bytes;
    NSString *noun = audioKind ? (self.rows.count == 1 ? @"song" : @"songs") : (self.rows.count == 1 ? @"video" : @"videos");
    if ([self showingFolderList]) self.summary.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)fl.count, fl.count == 1 ? @"folder" : @"folders"];
    else self.summary.text = [NSString stringWithFormat:@"%lu %@ · %@%@", (unsigned long)self.rows.count, noun,
                              [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile],
                              self.openFolder ? [NSString stringWithFormat:@" · in %@", self.openFolder.name] : @""];

    NSUInteger count = [self showingFolderList] ? fl.count : self.rows.count;
    self.empty.hidden = count > 0;
    if (!count) {
        if (q.length) self.empty.text = @"Nothing matches your search.";
        else if ([self showingFolderList]) self.empty.text = @"No folders yet. Tap the folder button at the top to make one.";
        else if (self.mode == VGLibFavorites) self.empty.text = @"Nothing here yet. Touch and hold something and choose Favorite.";
        else if (self.mode == VGLibRecent) self.empty.text = @"Nothing was added in the last two weeks.";
        else if (self.openFolder) self.empty.text = [NSString stringWithFormat:@"This folder has no %@ yet.", audioKind ? @"audio" : @"videos"];
        else self.empty.text = audioKind ? @"No audio yet. Download a video as MP3, M4A, WAV or FLAC and it shows up here."
                                         : @"No videos yet. Download something and it shows up here.";
    }
    [self.collection reloadData];
    [self updateBarButtons];
}

- (void)libraryChanged {
    if (!self.isViewLoaded || !self.view.window) return;
    if (self.openFolder && ![[VGEngine shared] folderWithID:self.openFolder.identifier]) { self.openFolder = nil; [self updateChips]; }
    [self reload];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc { [self reload]; }

#pragma mark Top bar

- (void)kindChanged {
    [self.collection setCollectionViewLayout:[self makeLayout] animated:NO];
    [self reload];
}

- (void)chipTapped:(UIButton *)b {
    [[UISelectionFeedbackGenerator new] selectionChanged];
    if (self.mode == (VGLibMode)b.tag && b.tag == VGLibFolders && self.openFolder) self.openFolder = nil;
    else { self.mode = (VGLibMode)b.tag; self.openFolder = nil; }
    [self endSelecting];
    [self updateChips];
    [self.collection setCollectionViewLayout:[self makeLayout] animated:NO];
    [self reload];
    [self.collection setContentOffset:CGPointMake(0, -self.collection.adjustedContentInset.top) animated:NO];
}

- (void)updateChips {
    for (UIButton *b in self.chips) {
        BOOL on = (VGLibMode)b.tag == self.mode;
        b.backgroundColor = on ? VGText : VGSurface2;
        [b setTitleColor:on ? VGBackground : VGText forState:UIControlStateNormal];
        if (b.tag == VGLibFolders) [b setTitle:self.openFolder ? [@"‹ " stringByAppendingString:self.openFolder.name] : @"Folders" forState:UIControlStateNormal];
    }
}

- (void)updateBarButtons {
    BOOL foldersOnly = [self showingFolderList];
    if (!self.gridItem) {
        self.gridItem = [[UIBarButtonItem alloc] initWithImage:nil style:UIBarButtonItemStylePlain target:self action:@selector(toggleGrid)];
        self.sortItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"] style:UIBarButtonItemStylePlain target:nil action:nil];
        self.selectItem = [[UIBarButtonItem alloc] initWithTitle:@"Select" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelecting)];
        self.addFolderItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder.badge.plus"] style:UIBarButtonItemStylePlain target:self action:@selector(newFolder)];
    }
    self.gridItem.image = [UIImage systemImageNamed:self.grid ? @"list.bullet" : @"square.grid.2x2"];
    self.gridItem.accessibilityLabel = self.grid ? @"Show as list" : @"Show as grid";
    self.sortItem.menu = [self sortMenu];
    self.selectItem.title = self.selecting ? @"Done" : @"Select";
    if (self.selecting) { self.navigationItem.rightBarButtonItems = @[self.selectItem]; return; }
    if (foldersOnly) self.navigationItem.rightBarButtonItems = @[self.addFolderItem];
    else self.navigationItem.rightBarButtonItems = @[self.selectItem, self.gridItem, self.sortItem];
}

- (UIMenu *)sortMenu {
    __weak typeof(self) ws = self;
    NSArray *names = @[@"Date added", @"Name", @"Size", @"Duration"];
    NSArray *icons = @[@"calendar", @"textformat", @"internaldrive", @"clock"];
    NSMutableArray *acts = [NSMutableArray array];
    for (NSUInteger i = 0; i < names.count; i++) {
        UIAction *a = [UIAction actionWithTitle:names[i] image:[UIImage systemImageNamed:icons[i]] identifier:nil handler:^(UIAction *x) {
            if (ws.sort == (VGLibSort)i) ws.sortUp = !ws.sortUp;
            else { ws.sort = (VGLibSort)i; ws.sortUp = i == VGLibSortName; }
            NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
            [d setInteger:ws.sort forKey:kSortKey];
            [d setBool:ws.sortUp forKey:kSortUpKey];
            [ws reload];
        }];
        if (self.sort == (VGLibSort)i) {
            a.state = UIMenuElementStateOn;
            a.subtitle = self.sortUp ? @"Ascending" : @"Descending";
        }
        [acts addObject:a];
    }
    return [UIMenu menuWithTitle:@"Sort by" children:acts];
}

- (void)toggleGrid {
    self.grid = !self.grid;
    [NSUserDefaults.standardUserDefaults setBool:self.grid forKey:kGridKey];
    [self.collection setCollectionViewLayout:[self makeLayout] animated:NO];
    [self.collection reloadData];
    [self updateBarButtons];
}

#pragma mark Collection

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return [self showingFolderList] ? (NSInteger)self.folderRows.count : (NSInteger)self.rows.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    if ([self showingFolderList]) {
        VGLibFolderCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"f" forIndexPath:ip];
        VGFolder *f = self.folderRows[(NSUInteger)ip.item];
        c.icon.image = [[UIImage systemImageNamed:@"folder.fill"] imageWithTintColor:f.color renderingMode:UIImageRenderingModeAlwaysOriginal];
        c.titleLabel.text = f.name;
        NSUInteger n = [[VGEngine shared] itemsInFolder:f].count;
        c.subLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)n, n == 1 ? @"item" : @"items"];
        return c;
    }
    VGLibCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"i" forIndexPath:ip];
    [c configureWith:self.rows[(NSUInteger)ip.item] grid:self.grid selecting:self.selecting];
    return c;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if ([self showingFolderList]) {
        self.openFolder = self.folderRows[(NSUInteger)ip.item];
        [cv deselectItemAtIndexPath:ip animated:NO];
        [self updateChips];
        [self.collection setCollectionViewLayout:[self makeLayout] animated:NO];
        [self reload];
        return;
    }
    if (self.selecting) { [self updateActionBar]; return; }
    [cv deselectItemAtIndexPath:ip animated:YES];
    [VGActions play:self.rows[(NSUInteger)ip.item] from:self];
}

- (void)collectionView:(UICollectionView *)cv didDeselectItemAtIndexPath:(NSIndexPath *)ip {
    if (self.selecting) [self updateActionBar];
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    if (self.selecting) return nil;
    __weak typeof(self) ws = self;
    if ([self showingFolderList]) {
        VGFolder *f = self.folderRows[(NSUInteger)ip.item];
        return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *s) { return [ws menuForFolder:f]; }];
    }
    VGItem *item = self.rows[(NSUInteger)ip.item];
    UICollectionViewCell *cell = [cv cellForItemAtIndexPath:ip];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *s) { return [ws menuFor:item source:cell]; }];
}

#pragma mark Menus

- (UIMenu *)menuForFolder:(VGFolder *)f {
    __weak typeof(self) ws = self;
    UIAction *edit = [UIAction actionWithTitle:@"Rename or Change Color" image:[UIImage systemImageNamed:@"paintpalette"] identifier:nil handler:^(UIAction *a) {
        [ws presentViewController:[VGFolderEditorViewController sheetWithFolder:f onSave:^(NSString *name, NSString *hex) { [[VGEngine shared] updateFolder:f name:name colorHex:hex]; }] animated:YES completion:nil];
    }];
    UIAction *del = [UIAction actionWithTitle:@"Delete Folder" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *a) {
        UIAlertController *al = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Delete “%@”?", f.name]
                                                                    message:@"Everything inside goes back to the main Library. Nothing is deleted."
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [al addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [al addAction:[UIAlertAction actionWithTitle:@"Delete Folder" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [[VGEngine shared] deleteFolder:f]; }]];
        [ws presentViewController:al animated:YES completion:nil];
    }];
    del.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithChildren:@[edit, del]];
}

- (UIMenu *)folderMenuFor:(NSArray<VGItem *> *)items {
    __weak typeof(self) ws = self;
    NSMutableArray *list = [NSMutableArray array];
    [list addObject:[UIAction actionWithTitle:@"New Folder…" image:[UIImage systemImageNamed:@"folder.badge.plus"] identifier:nil handler:^(UIAction *a) {
        UINavigationController *sheet = [VGFolderEditorViewController sheetWithFolder:nil onSave:^(NSString *name, NSString *hex) {
            VGFolder *f = [[VGEngine shared] createFolderNamed:name colorHex:hex];
            [[VGEngine shared] setItems:items folder:f];
            [VGActions toast:[NSString stringWithFormat:@"Moved to “%@”", f.name] icon:@"folder.fill" in:ws.view.window ?: ws.view];
        }];
        [ws presentViewController:sheet animated:YES completion:nil];
    }]];
    NSMutableArray *existing = [NSMutableArray array];
    for (VGFolder *f in [VGEngine shared].folders) {
        [existing addObject:[UIAction actionWithTitle:f.name image:[[UIImage systemImageNamed:@"folder.fill"] imageWithTintColor:f.color renderingMode:UIImageRenderingModeAlwaysOriginal]
                                           identifier:nil handler:^(UIAction *a) {
            [[VGEngine shared] setItems:items folder:f];
            [VGActions toast:[NSString stringWithFormat:@"Moved to “%@”", f.name] icon:@"folder.fill" in:ws.view.window ?: ws.view];
        }]];
    }
    NSMutableArray *kids = [NSMutableArray arrayWithObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:list]];
    if (existing.count) [kids addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:existing]];
    BOOL anyIn = NO;
    for (VGItem *i in items) if (i.folderID.length) anyIn = YES;
    if (anyIn) [kids addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
        [UIAction actionWithTitle:@"Remove from Folder" image:[UIImage systemImageNamed:@"tray.and.arrow.up"] identifier:nil handler:^(UIAction *a) { [[VGEngine shared] setItems:items folder:nil]; }]]]];
    return [UIMenu menuWithTitle:@"Move to Folder" image:[UIImage systemImageNamed:@"folder"] identifier:nil options:0 children:kids];
}

- (UIMenu *)menuFor:(VGItem *)item source:(UIView *)source {
    __weak typeof(self) ws = self;
    NSMutableArray *top = [NSMutableArray array];
    [top addObject:[UIAction actionWithTitle:@"Play" image:[UIImage systemImageNamed:@"play.fill"] identifier:nil handler:^(UIAction *a) { [VGActions play:item from:ws]; }]];
    [top addObject:[UIAction actionWithTitle:item.favorite ? @"Remove from Favorites" : @"Favorite" image:[UIImage systemImageNamed:item.favorite ? @"heart.slash" : @"heart"] identifier:nil
                                     handler:^(UIAction *a) { [[VGEngine shared] setFavorite:!item.favorite forItem:item]; }]];
    NSMutableArray *share = [NSMutableArray array];
    if (item.photos) [share addObject:[UIAction actionWithTitle:@"Save to Photos" image:[UIImage systemImageNamed:@"photo.on.rectangle.angled"] identifier:nil handler:^(UIAction *a) { [VGActions saveToPhotos:item from:ws]; }]];
    [share addObject:[UIAction actionWithTitle:@"Save to Files" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *a) { [VGActions saveToFiles:item from:ws]; }]];
    [share addObject:[UIAction actionWithTitle:@"Share" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *a) { [VGActions share:item from:ws source:source]; }]];
    NSMutableArray *tools = [NSMutableArray array];
    [tools addObject:[UIAction actionWithTitle:@"File information" image:[UIImage systemImageNamed:@"info.circle"] identifier:nil handler:^(UIAction *a) { [ws showInfo:item]; }]];
    if (item.audio) {
        [tools addObject:[UIAction actionWithTitle:@"Edit title, artist, album and cover" image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(UIAction *a) {
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[VGAudioEditorViewController alloc] initWithItem:item]];
            nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            [ws presentViewController:nav animated:YES completion:nil];
        }]];
        NSMutableArray *conv = [NSMutableArray array];
        NSString *cur = item.fileName.pathExtension.lowercaseString;
        NSArray *fmts = @[@[@"mp3", @"MP3"], @[@"m4a", @"M4A (AAC)"], @[@"wav", @"WAV"], @[@"flac", @"FLAC"]];
        BOOL lossless = [VGEngine itemIsLossless:item];
        for (NSArray *f in fmts) {
            if ([f[0] isEqualToString:cur]) continue;
            if ([f[0] isEqualToString:@"flac"] && !lossless) continue;   // FLAC from a lossy file would only be bigger, not better
            [conv addObject:[UIAction actionWithTitle:f[1] image:nil identifier:nil handler:^(UIAction *a) { [ws convert:item to:f[0]]; }]];
        }
        if (conv.count) [tools addObject:[UIMenu menuWithTitle:@"Convert to…" image:[UIImage systemImageNamed:@"waveform"] identifier:nil options:0 children:conv]];
    }
    [tools addObject:[self folderMenuFor:@[item]]];
    [tools addObject:[UIAction actionWithTitle:@"Move to Vault" image:[UIImage systemImageNamed:@"lock"] identifier:nil handler:^(UIAction *a) {
        [[VGEngine shared] setItem:item inVault:YES];
        [VGActions toast:@"Moved to Private Vault 2.0" icon:@"lock.fill" in:ws.view.window ?: ws.view];
    }]];
    UIAction *del = [UIAction actionWithTitle:@"Delete" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *a) { [ws confirmDelete:@[item]]; }];
    del.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithChildren:@[[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:top],
                                       [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:share],
                                       [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:tools], del]];
}

#pragma mark Actions

- (void)showInfo:(VGItem *)item {
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateStyle = NSDateFormatterMediumStyle;
    df.timeStyle = NSDateFormatterShortStyle;
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"Name: %@", item.title]];
    [lines addObject:[NSString stringWithFormat:@"Type: %@ · %@", item.audio ? @"Audio" : @"Video", item.fileName.pathExtension.uppercaseString]];
    if (!item.audio && item.res.length) [lines addObject:[NSString stringWithFormat:@"Quality: %@", item.res]];
    if (item.audio && item.artist.length) [lines addObject:[NSString stringWithFormat:@"Artist: %@", item.artist]];
    if (item.audio && item.album.length) [lines addObject:[NSString stringWithFormat:@"Album: %@", item.album]];
    if (VGDuration(item.duration)) [lines addObject:[NSString stringWithFormat:@"Length: %@", VGDuration(item.duration)]];
    [lines addObject:[NSString stringWithFormat:@"Size: %@", [NSByteCountFormatter stringFromByteCount:item.bytes countStyle:NSByteCountFormatterCountStyleFile]]];
    [lines addObject:[NSString stringWithFormat:@"Added: %@", [df stringFromDate:item.date]]];
    if (item.site.length) [lines addObject:[NSString stringWithFormat:@"From: %@", item.site]];
    VGFolder *f = [[VGEngine shared] folderWithID:item.folderID];
    if (f) [lines addObject:[NSString stringWithFormat:@"Folder: %@", f.name]];
    [lines addObject:[NSString stringWithFormat:@"Favorite: %@", item.favorite ? @"Yes" : @"No"]];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"File information" message:[lines componentsJoinedByString:@"\n"] preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) ws = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Technical details" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[VGEngine shared] diagnose:item completion:^(NSString *report) {
            UIAlertController *r = [UIAlertController alertControllerWithTitle:@"Technical details" message:report preferredStyle:UIAlertControllerStyleAlert];
            [r addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *y) { UIPasteboard.generalPasteboard.string = report; }]];
            [r addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
            [ws presentViewController:r animated:YES completion:nil];
        }];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)convert:(VGItem *)item to:(NSString *)format {
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Making %@…", format.uppercaseString]
                                                                  message:@"Keep VidGrab open.\n\n0%" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:wait animated:YES completion:nil];
    __weak typeof(self) ws = self;
    [[VGEngine shared] convertAudioItem:item toFormat:format progress:^(double f) {
        wait.message = [NSString stringWithFormat:@"Keep VidGrab open.\n\n%d%%", (int)(f * 100)];
    } completion:^(VGItem *n, NSString *err) {
        [wait dismissViewControllerAnimated:YES completion:^{
            if (err) [VGActions alert:@"Couldn't convert it" message:err from:ws];
            else [VGActions toast:[NSString stringWithFormat:@"Saved as %@", format.uppercaseString] icon:@"checkmark.circle.fill" in:ws.view.window ?: ws.view];
        }];
    }];
}

- (void)confirmDelete:(NSArray<VGItem *> *)items {
    NSString *t = items.count == 1 ? [NSString stringWithFormat:@"Delete “%@”?", items[0].title] : [NSString stringWithFormat:@"Delete %lu items?", (unsigned long)items.count];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:@"The files are removed from your iPhone." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        for (VGItem *i in items) [[VGEngine shared] deleteItem:i];
        [ws endSelecting];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)openPlaylists { [self.navigationController pushViewController:[VGSavedPlaylistsViewController new] animated:YES]; }

- (void)newFolder {
    __weak typeof(self) ws = self;
    UINavigationController *sheet = [VGFolderEditorViewController sheetWithFolder:nil onSave:^(NSString *name, NSString *hex) {
        VGFolder *f = [[VGEngine shared] createFolderNamed:name colorHex:hex];
        [VGActions toast:[NSString stringWithFormat:@"Folder “%@” made", f.name] icon:@"folder.fill" in:ws.view.window ?: ws.view];
    }];
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark Selecting

- (void)buildActionBar {
    NSArray *defs = @[@[@"Favorite", @"heart", @"selFavorite"], @[@"Folder", @"folder", @"selFolder"], @[@"Share", @"square.and.arrow.up", @"selShare"], @[@"Delete", @"trash", @"selDelete"]];
    NSMutableArray *btns = [NSMutableArray array];
    for (NSArray *d in defs) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
        c.title = d[0];
        c.image = [UIImage systemImageNamed:d[1]];
        c.imagePlacement = NSDirectionalRectEdgeTop;
        c.imagePadding = 4;
        c.baseForegroundColor = [d[0] isEqualToString:@"Delete"] ? VGAccent : VGText;
        c.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *in) { NSMutableDictionary *m = [in mutableCopy]; m[NSFontAttributeName] = VGFont(11, UIFontWeightSemibold); return m; };
        b.configuration = c;
        [b addTarget:self action:NSSelectorFromString(d[2]) forControlEvents:UIControlEventTouchUpInside];
        [btns addObject:b];
    }
    self.actionBar = [[UIStackView alloc] initWithArrangedSubviews:btns];
    self.actionBar.distribution = UIStackViewDistributionFillEqually;
    self.actionBar.backgroundColor = VGSurface;
    self.actionBar.layoutMarginsRelativeArrangement = YES;
    self.actionBar.layoutMargins = UIEdgeInsetsMake(8, 8, 8, 8);
    self.actionBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionBar.hidden = YES;
    [self.view addSubview:self.actionBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.actionBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.actionBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.actionBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor], [self.actionBar.heightAnchor constraintEqualToConstant:64],
    ]];
}

- (NSArray<VGItem *> *)selectedItems {
    NSMutableArray *out = [NSMutableArray array];
    for (NSIndexPath *ip in self.collection.indexPathsForSelectedItems) if ((NSUInteger)ip.item < self.rows.count) [out addObject:self.rows[(NSUInteger)ip.item]];
    return out;
}

- (void)updateActionBar {
    BOOL any = self.collection.indexPathsForSelectedItems.count > 0;
    for (UIButton *b in self.actionBar.arrangedSubviews) { b.enabled = any; b.alpha = any ? 1 : 0.4; }
}

- (void)toggleSelecting {
    if (self.selecting) { [self endSelecting]; return; }
    self.selecting = YES;
    self.collection.allowsMultipleSelection = YES;
    self.actionBar.hidden = NO;
    self.collection.contentInset = UIEdgeInsetsMake(0, 0, 70, 0);
    [self updateActionBar];
    [self updateBarButtons];
    [self.collection reloadData];
}

- (void)endSelecting {
    if (!self.selecting) return;
    self.selecting = NO;
    self.collection.allowsMultipleSelection = NO;
    self.actionBar.hidden = YES;
    self.collection.contentInset = UIEdgeInsetsZero;
    [self updateBarButtons];
    [self.collection reloadData];
}

- (void)selFavorite {
    NSArray *items = [self selectedItems];
    BOOL allFav = items.count > 0;
    for (VGItem *i in items) if (!i.favorite) allFav = NO;
    for (VGItem *i in items) [[VGEngine shared] setFavorite:!allFav forItem:i];
    [VGActions toast:allFav ? @"Removed from Favorites" : @"Added to Favorites" icon:allFav ? @"heart.slash" : @"heart.fill" in:self.view.window ?: self.view];
    [self endSelecting];
}

- (void)selFolder {
    NSArray<VGItem *> *items = [self selectedItems];
    if (!items.count) return;
    __weak typeof(self) ws = self;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Move to folder" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"New Folder…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UINavigationController *sheet = [VGFolderEditorViewController sheetWithFolder:nil onSave:^(NSString *name, NSString *hex) {
            VGFolder *f = [[VGEngine shared] createFolderNamed:name colorHex:hex];
            [[VGEngine shared] setItems:items folder:f];
            [ws endSelecting];
        }];
        [ws presentViewController:sheet animated:YES completion:nil];
    }]];
    for (VGFolder *f in [VGEngine shared].folders) {
        [a addAction:[UIAlertAction actionWithTitle:f.name style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [[VGEngine shared] setItems:items folder:f];
            [ws endSelecting];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Remove from Folder" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[VGEngine shared] setItems:items folder:nil];
        [ws endSelecting];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.actionBar;
    a.popoverPresentationController.sourceRect = self.actionBar.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)selShare {
    NSArray *items = [self selectedItems];
    if (items.count) [VGActions shareItems:items from:self source:self.actionBar];
}

- (void)selDelete {
    NSArray *items = [self selectedItems];
    if (items.count) [self confirmDelete:items];
}

@end
