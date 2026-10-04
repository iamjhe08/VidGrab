#import "VGQualitySheet.h"
#import "VGEngine.h"
#import "VGTheme.h"
#import "VGActions.h"
#import "VGQualityCell.h"

typedef NS_ENUM(NSInteger, VGSheetState) { VGSheetLoading, VGSheetError, VGSheetPick, VGSheetDownloading, VGSheetDone };

@interface VGQualitySheet () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy, nullable) NSString *fallback;
@property (nonatomic, strong) VGVideo *video;
@property (nonatomic, strong) VGItem *item;
@property (nonatomic, weak) VGTask *task;
@property (nonatomic) NSInteger selected;

@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UILabel *titleLabel, *metaLabel;

@property (nonatomic, strong) UIView *loadingView, *errorView, *pickView, *progressView, *doneView;
@property (nonatomic, strong) UILabel *errorLabel, *caption, *stageLabel, *percentLabel, *detailLabel, *doneSub;
@property (nonatomic, strong) UICollectionView *list;
@property (nonatomic, strong) VGProgressBar *bar;
@property (nonatomic, strong) UIButton *photosButton, *shareButton;
@end

@implementation VGQualitySheet

- (instancetype)initWithURL:(NSString *)url fallbackURL:(NSString *)fallback {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _url = [url copy];
        _fallback = [fallback copy];
    }
    return self;
}

- (void)presentFrom:(UIViewController *)host {
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = self.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    sheet.prefersGrabberVisible = YES;
    sheet.preferredCornerRadius = 22;
    [host presentViewController:self animated:YES completion:nil];
}

#pragma mark Helpers

- (UILabel *)label:(UIFont *)f color:(UIColor *)c lines:(NSInteger)n {
    UILabel *l = [UILabel new];
    l.font = f;
    l.textColor = c;
    l.numberOfLines = n;
    return l;
}

- (UIStackView *)vstack:(NSArray *)views spacing:(CGFloat)sp {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:views];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = sp;
    return s;
}

- (UIView *)inset:(UIView *)v {
    UIView *w = [UIView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [w addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:w.topAnchor],
        [v.bottomAnchor constraintEqualToAnchor:w.bottomAnchor],
        [v.leadingAnchor constraintEqualToAnchor:w.leadingAnchor constant:20],
        [v.trailingAnchor constraintEqualToAnchor:w.trailingAnchor constant:-20],
    ]];
    return w;
}

#pragma mark Build

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VGSurface;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // Header: thumbnail + title
    self.thumb = [UIImageView new];
    self.thumb.contentMode = UIViewContentModeScaleAspectFill;
    self.thumb.clipsToBounds = YES;
    self.thumb.layer.cornerRadius = 8;
    self.thumb.backgroundColor = VGSurface2;
    [self.thumb.widthAnchor constraintEqualToConstant:112].active = YES;
    [self.thumb.heightAnchor constraintEqualToConstant:63].active = YES;
    self.titleLabel = [self label:VGFont(16, UIFontWeightBold) color:VGText lines:2];
    self.titleLabel.text = @"Finding video…";
    self.metaLabel = [self label:VGFont(13, UIFontWeightMedium) color:VGSecondary lines:1];
    self.metaLabel.text = [NSURL URLWithString:self.url].host;
    UIStackView *texts = [self vstack:@[self.titleLabel, self.metaLabel] spacing:3];
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[self.thumb, texts]];
    header.spacing = 12;
    header.alignment = UIStackViewAlignmentCenter;

    [self buildLoading];
    [self buildError];
    [self buildPick];
    [self buildProgress];
    [self buildDone];

    UIStackView *root = [self vstack:@[[self inset:header], self.loadingView, self.errorView, self.pickView, self.progressView, self.doneView] spacing:18];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];
    [scroll addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:28],
        [root.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [root.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor],
    ]];

    [self setState:VGSheetLoading];
    [self lookUp:self.url];
}

- (void)buildLoading {
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spin.color = VGSecondary;
    [spin startAnimating];
    UILabel *l = [self label:VGFont(15, UIFontWeightMedium) color:VGSecondary lines:1];
    l.text = @"Finding qualities…";
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[spin, l]];
    s.spacing = 10;
    self.loadingView = [self inset:s];
}

- (void)buildError {
    self.errorLabel = [self label:VGFont(15, UIFontWeightMedium) color:VGSecondary lines:0];
    UIButton *retry = VGPrimaryButton(@"Try again", @"arrow.clockwise");
    [retry addTarget:self action:@selector(retry) forControlEvents:UIControlEventTouchUpInside];
    UIButton *copy = VGSecondaryButton(@"Copy details", @"doc.on.doc");
    [copy addTarget:self action:@selector(copyDetails) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[retry, copy]];
    row.spacing = 10;
    row.distribution = UIStackViewDistributionFillEqually;
    self.errorView = [self inset:[self vstack:@[self.errorLabel, row] spacing:14]];
}

- (void)buildPick {
    UILabel *h = [self label:VGFont(18, UIFontWeightHeavy) color:VGText lines:1];
    h.text = @"Choose quality";
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.itemSize = CGSizeMake(120, 128);
    layout.minimumLineSpacing = 10;
    layout.sectionInset = UIEdgeInsetsMake(0, 20, 0, 20);
    self.list = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.list.backgroundColor = UIColor.clearColor;
    self.list.showsHorizontalScrollIndicator = NO;
    self.list.dataSource = self;
    self.list.delegate = self;
    [self.list registerClass:VGQualityCell.class forCellWithReuseIdentifier:@"q"];
    [self.list.heightAnchor constraintEqualToConstant:128].active = YES;

    UIButton *dl = VGPrimaryButton(@"Download", @"arrow.down.to.line");
    [dl addTarget:self action:@selector(download) forControlEvents:UIControlEventTouchUpInside];
    self.caption = [self label:VGFont(13, UIFontWeightMedium) color:VGTertiary lines:0];
    self.caption.textAlignment = NSTextAlignmentCenter;
    self.pickView = [self vstack:@[[self inset:h], self.list, [self inset:[self vstack:@[dl, self.caption] spacing:10]]] spacing:12];
}

- (void)buildProgress {
    self.stageLabel = [self label:VGFont(15, UIFontWeightSemibold) color:VGText lines:1];
    self.percentLabel = [self label:[UIFont monospacedDigitSystemFontOfSize:28 weight:UIFontWeightHeavy] color:VGText lines:1];
    [self.percentLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[self.stageLabel, self.percentLabel]];
    top.alignment = UIStackViewAlignmentLastBaseline;
    self.bar = [VGProgressBar new];
    [self.bar.heightAnchor constraintEqualToConstant:6].active = YES;
    self.detailLabel = [self label:[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium] color:VGSecondary lines:1];
    UILabel *hint = [self label:VGFont(12, UIFontWeightMedium) color:VGTertiary lines:0];
    hint.text = @"You can close this and keep browsing. Progress shows on the Download button and in the Downloads tab.";
    UIButton *cancel = VGSecondaryButton(@"Cancel", @"xmark");
    [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    self.progressView = [self inset:[self vstack:@[top, self.bar, self.detailLabel, cancel, hint] spacing:12]];
}

- (void)buildDone {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"
                                                                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightBold]]];
    icon.tintColor = VGAccent;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *t = [self label:VGFont(18, UIFontWeightHeavy) color:VGText lines:1];
    t.text = @"Downloaded";
    self.doneSub = [self label:VGFont(13, UIFontWeightMedium) color:VGSecondary lines:2];
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[icon, [self vstack:@[t, self.doneSub] spacing:2]]];
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
    self.doneView = [self inset:[self vstack:@[head, self.photosButton, row] spacing:12]];
}

- (void)setState:(VGSheetState)state {
    self.loadingView.hidden = state != VGSheetLoading;
    self.errorView.hidden = state != VGSheetError;
    self.pickView.hidden = state != VGSheetPick;
    self.progressView.hidden = state != VGSheetDownloading;
    self.doneView.hidden = state != VGSheetDone;
    self.modalInPresentation = NO;
}

#pragma mark Flow

- (void)lookUp:(NSString *)url {
    [[VGEngine shared] fetch:url completion:^(VGVideo *video, NSString *error) {
        if (!video) {
            // The page link failed; try the video's own address if the page gave us one.
            if (self.fallback.length && ![url isEqualToString:self.fallback]) { [self lookUp:self.fallback]; return; }
            self.titleLabel.text = @"Couldn't find a video";
            self.errorLabel.text = error;
            [self setState:VGSheetError];
            return;
        }
        self.video = video;
        self.titleLabel.text = video.title;
        NSMutableArray *meta = [NSMutableArray array];
        if (video.site) [meta addObject:video.site];
        if (VGDuration(video.duration)) [meta addObject:VGDuration(video.duration)];
        self.metaLabel.text = [meta componentsJoinedByString:@" · "];
        if (video.thumbnail) {
            [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:video.thumbnail] completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                UIImage *img = d ? [UIImage imageWithData:d] : nil;
                dispatch_async(dispatch_get_main_queue(), ^{ if (img) self.thumb.image = img; });
            }] resume];
        }
        self.selected = 0;
        [video.options enumerateObjectsUsingBlock:^(VGOption *o, NSUInteger i, BOOL *stop) {
            if (o.photos && !o.convert) { self.selected = (NSInteger)i; *stop = YES; }
        }];
        [self.list reloadData];
        [self updateCaption];
        [self setState:VGSheetPick];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ((NSUInteger)self.selected < video.options.count)
                [self.list scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:self.selected inSection:0]
                                  atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:NO];
        });
    }];
}

- (void)retry {
    [self setState:VGSheetLoading];
    [self lookUp:self.url];
}

- (void)copyDetails {
    [[VGEngine shared] copyErrorDetails:^{ [VGActions toast:@"Error details copied" icon:@"doc.on.doc.fill" in:self.view]; }];
}

- (void)updateCaption {
    VGOption *o = (NSUInteger)self.selected < self.video.options.count ? self.video.options[self.selected] : nil;
    if (!o) return;
    if ([o.identifier isEqualToString:@"mp3"]) self.caption.text = @"MP3 at 256 kbps · plays anywhere. Share it or save to Files";
    else if (o.audio) self.caption.text = @"M4A audio · Share it or save to Files";
    else if (o.convert) self.caption.text = @"Converted to MP4 on your iPhone so Photos can play it. Takes a few minutes; keep the app open.";
    else if (o.photos) self.caption.text = @"MP4 · Ready for your Photos library";
    else self.caption.text = [NSString stringWithFormat:@"%@ · Photos can't open this one, but Files and other apps can", o.format];
}

- (void)download {
    VGOption *opt = self.video.options[self.selected];
    self.bar.progress = 0;
    self.percentLabel.text = @"0%";
    self.stageLabel.text = [VGEngine shared].activeCount >= 2 ? @"Waiting for other downloads…" : @"Starting…";
    self.detailLabel.text = [NSString stringWithFormat:@"%@ · %@", opt.res, opt.sizeText.length ? opt.sizeText : opt.format];
    [self setState:VGSheetDownloading];

    __weak typeof(self) ws = self;
    self.task = [[VGEngine shared] download:self.video option:opt progress:^(double fraction, NSString *stage, NSString *detail) {
        [ws.bar setProgress:fraction animated:YES];
        ws.percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)round(fraction * 100)];
        ws.stageLabel.text = stage;
        if (detail.length) ws.detailLabel.text = detail;
    } completion:^(VGItem *item, NSString *error) {
        if (!ws) return;
        if (!item) {
            if ([error isEqualToString:@"Cancelled."]) { [ws setState:VGSheetPick]; return; }
            ws.errorLabel.text = error;
            [ws setState:VGSheetError];
            return;
        }
        ws.item = item;
        ws.doneSub.text = [NSString stringWithFormat:@"%@ · %@ · in your Downloads", item.res,
                           [NSByteCountFormatter stringFromByteCount:item.bytes countStyle:NSByteCountFormatterCountStyleFile]];
        ws.photosButton.hidden = !item.photos;
        [ws setState:VGSheetDone];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    }];
}

- (void)cancel { if (self.task) [[VGEngine shared] cancelTask:self.task]; }
- (void)savePhotos { if (self.item) [VGActions saveToPhotos:self.item from:self]; }
- (void)play { if (self.item) [VGActions play:self.item from:self]; }
- (void)share { if (self.item) [VGActions share:self.item from:self source:self.shareButton]; }

#pragma mark Collection

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return (NSInteger)self.video.options.count; }

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
    [self updateCaption];
}

@end
