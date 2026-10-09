#import "VGAudioEditorViewController.h"
#import "VGAudioTags.h"
#import "VGTheme.h"
#import "VGActions.h"
#import "VGCoverSearch.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface VGAudioEditorViewController () <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UITextFieldDelegate>
@property (nonatomic, strong) VGItem *item;
@property (nonatomic, strong) UIImageView *art;
@property (nonatomic, strong) UITextField *titleField, *artistField, *albumField;
@property (nonatomic, strong) NSData *chosenArt;
@property (nonatomic) BOOL clearArt;
@property (nonatomic, strong) UIScrollView *scroll;
@end

@implementation VGAudioEditorViewController

- (instancetype)initWithItem:(VGItem *)item {
    if ((self = [super init])) _item = item;
    return self;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)p text:(NSString *)t {
    UITextField *f = [UITextField new];
    f.backgroundColor = VGSurface2;
    f.textColor = VGText;
    f.font = VGFont(16, UIFontWeightMedium);
    f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:p attributes:@{NSForegroundColorAttributeName: VGTertiary}];
    f.text = t;
    f.layer.cornerRadius = 12;
    f.layer.cornerCurve = kCACornerCurveContinuous;
    f.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 10)];
    f.leftViewMode = UITextFieldViewModeAlways;
    f.returnKeyType = UIReturnKeyDone;
    f.delegate = self;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    [f.heightAnchor constraintEqualToConstant:50].active = YES;
    return f;
}

- (UILabel *)caption:(NSString *)s {
    UILabel *l = [UILabel new];
    l.text = s.uppercaseString;
    l.font = VGFont(11, UIFontWeightHeavy);
    l.textColor = VGSecondary;
    return l;
}

- (UIButton *)pillButton:(NSString *)title icon:(NSString *)icon action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:[@"  " stringByAppendingString:title] forState:UIControlStateNormal];
    [b setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
    b.titleLabel.font = VGFont(14, UIFontWeightBold);
    b.tintColor = VGText;
    [b setTitleColor:VGText forState:UIControlStateNormal];
    b.backgroundColor = VGSurface2;
    b.layer.cornerRadius = 12;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    [b.heightAnchor constraintEqualToConstant:44].active = YES;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VGBackground;
    self.title = @"Edit Audio";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];

    self.art = [UIImageView new];
    self.art.contentMode = UIViewContentModeScaleAspectFill;
    self.art.clipsToBounds = YES;
    self.art.backgroundColor = VGSurface2;
    self.art.layer.cornerRadius = 18;
    self.art.layer.cornerCurve = kCACornerCurveContinuous;
    [self.art.widthAnchor constraintEqualToConstant:200].active = YES;
    [self.art.heightAnchor constraintEqualToConstant:200].active = YES;
    [self refreshArt];

    UIButton *online = [self pillButton:@"Find cover art online" icon:@"magnifyingglass" action:@selector(findOnline)];
    online.backgroundColor = VGAccent;
    online.tintColor = UIColor.whiteColor;
    [online setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    UIButton *photo = [self pillButton:@"Choose from Photos" icon:@"photo" action:@selector(pickPhoto)];
    UIButton *file = [self pillButton:@"Choose from Files" icon:@"folder" action:@selector(pickFile)];
    UIButton *clear = [self pillButton:@"Remove cover" icon:@"trash" action:@selector(removeArt)];
    UIStackView *artButtons = [[UIStackView alloc] initWithArrangedSubviews:@[online, photo, file, clear]];
    artButtons.axis = UILayoutConstraintAxisVertical;
    artButtons.spacing = 8;

    self.titleField = [self fieldWithPlaceholder:@"Title" text:self.item.title];
    self.artistField = [self fieldWithPlaceholder:@"Artist" text:self.item.artist];
    self.albumField = [self fieldWithPlaceholder:@"Album" text:self.item.album];

    UILabel *note = [UILabel new];
    NSString *ext = self.item.fileName.pathExtension.lowercaseString;
    BOOL tagged = [ext isEqualToString:@"mp3"] || [ext isEqualToString:@"m4a"];
    note.text = tagged ? @"These details are saved inside the file, so other music apps show them too."
                       : @"These details are shown in VidGrab. WAV and FLAC files can't hold a cover picture inside the file.";
    note.font = VGFont(12, UIFontWeightMedium);
    note.textColor = VGTertiary;
    note.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.art, artButtons, [self caption:@"Title"], self.titleField,
                                                                           [self caption:@"Artist"], self.artistField, [self caption:@"Album"], self.albumField, note]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.alignment = UIStackViewAlignmentFill;
    [stack setCustomSpacing:16 afterView:self.art];
    [stack setCustomSpacing:20 afterView:artButtons];
    [stack setCustomSpacing:14 afterView:self.titleField];
    [stack setCustomSpacing:14 afterView:self.artistField];
    [stack setCustomSpacing:14 afterView:self.albumField];
    // The picture sits in the middle of the page.
    UIView *artHolder = [UIView new];
    self.art.translatesAutoresizingMaskIntoConstraints = NO;
    [artHolder addSubview:self.art];
    [NSLayoutConstraint activateConstraints:@[[self.art.topAnchor constraintEqualToAnchor:artHolder.topAnchor], [self.art.bottomAnchor constraintEqualToAnchor:artHolder.bottomAnchor],
                                              [self.art.centerXAnchor constraintEqualToAnchor:artHolder.centerXAnchor]]];
    [stack removeArrangedSubview:self.art];
    [stack insertArrangedSubview:artHolder atIndex:0];

    self.scroll = [UIScrollView new];
    self.scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scroll];
    [self.scroll addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.topAnchor constraintEqualToAnchor:g.topAnchor], [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-30],
        [stack.leadingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.trailingAnchor constant:-20],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

/// Lifts the page above the keyboard so the field being typed in stays visible.
- (void)keyboardChanged:(NSNotification *)n {
    CGRect kb = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect inView = [self.view convertRect:kb fromView:nil];
    CGFloat cover = n.name == UIKeyboardWillHideNotification ? 0 : MAX(0, CGRectGetMaxY(self.view.bounds) - inView.origin.y);
    double dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:dur animations:^{
        self.scroll.contentInset = UIEdgeInsetsMake(0, 0, cover, 0);
        self.scroll.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, cover, 0);
        for (UITextField *f in @[self.titleField, self.artistField, self.albumField]) {
            if (f.isFirstResponder) { [self.scroll scrollRectToVisible:CGRectInset([self.scroll convertRect:f.bounds fromView:f], 0, -24) animated:NO]; break; }
        }
    }];
}

- (void)refreshArt {
    UIImage *img = nil;
    if (self.chosenArt) img = [UIImage imageWithData:self.chosenArt];
    else if (!self.clearArt) img = self.item.thumbnailImage;
    self.art.image = img ?: [UIImage systemImageNamed:@"music.note" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:64 weight:UIImageSymbolWeightLight]];
    self.art.contentMode = img ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
    self.art.tintColor = VGTertiary;
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)removeArt {
    self.chosenArt = nil;
    self.clearArt = YES;
    [self refreshArt];
}

- (void)useImage:(UIImage *)image {
    NSData *d = [VGAudioTags squareJPEGFrom:image side:1000];
    if (!d) { [VGActions alert:@"Couldn't use that picture" message:@"Try a different one." from:self]; return; }
    self.chosenArt = d;
    self.clearArt = NO;
    [self refreshArt];
}

- (void)findOnline {
    [self.view endEditing:YES];
    NSString *terms = [[self.artistField.text stringByAppendingFormat:@" %@", self.titleField.text] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    UIAlertController *ask = [UIAlertController alertControllerWithTitle:@"Find cover art" message:@"Type a song, an artist, or both." preferredStyle:UIAlertControllerStyleAlert];
    [ask addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [VGCoverSearch cleanedTerms:terms]; tf.clearButtonMode = UITextFieldViewModeWhileEditing; tf.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [ask addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ask addAction:[UIAlertAction actionWithTitle:@"Search" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [ws runCoverSearch:ask.textFields.firstObject.text]; }]];
    [self presentViewController:ask animated:YES completion:nil];
}

- (void)runCoverSearch:(NSString *)terms {
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"Searching…" message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) ws = self;
    [self presentViewController:wait animated:YES completion:^{
        [VGCoverSearch search:terms completion:^(NSArray<VGCoverResult *> *results, NSString *error) {
            [wait dismissViewControllerAnimated:YES completion:^{
                if (!ws) return;
                if (error) { [VGActions alert:@"Cover art" message:error from:ws]; return; }
                VGCoverPickerViewController *pick = [[VGCoverPickerViewController alloc] initWithResults:results];
                pick.onPick = ^(UIImage *img, VGCoverResult *r) {
                    [ws useImage:img];
                    if (!ws.albumField.text.length && r.album.length) ws.albumField.text = r.album;
                    if (!ws.artistField.text.length && r.artist.length) ws.artistField.text = r.artist;
                };
                UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:pick];
                [ws presentViewController:nav animated:YES completion:nil];
            }];
        }];
    }];
}

- (void)pickPhoto {
    PHPickerConfiguration *cfg = [PHPickerConfiguration new];
    cfg.filter = [PHPickerFilter imagesFilter];
    cfg.selectionLimit = 1;
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *prov = results.firstObject.itemProvider;
    if (![prov canLoadObjectOfClass:UIImage.class]) return;
    [prov loadObjectOfClass:UIImage.class completionHandler:^(id img, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{ if ([img isKindOfClass:UIImage.class]) [self useImage:img]; });
    }];
}

- (void)pickFile {
    UIDocumentPickerViewController *d = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    d.delegate = self;
    [self presentViewController:d animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    UIImage *img = urls.firstObject ? [UIImage imageWithContentsOfFile:urls.firstObject.path] : nil;
    if (img) [self useImage:img]; else [VGActions alert:@"Couldn't read that picture" message:nil from:self];
}

- (void)save {
    [self.view endEditing:YES];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [sp startAnimating];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:sp];
    __weak typeof(self) ws = self;
    [[VGEngine shared] updateItem:self.item title:self.titleField.text artist:self.artistField.text album:self.albumField.text
                          artwork:self.chosenArt clearArtwork:self.clearArt completion:^(NSString *err) {
        UIViewController *presenter = ws.presentingViewController;
        [ws dismissViewControllerAnimated:YES completion:^{
            if (err && presenter) [VGActions alert:@"Saved in VidGrab, but not inside the file" message:err from:presenter];
        }];
    }];
}

@end


#pragma mark Picker for online covers

@interface VGCoverCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iv;
@property (nonatomic, strong) UILabel *label;
@end
@implementation VGCoverCell
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.iv = [UIImageView new];
        self.iv.contentMode = UIViewContentModeScaleAspectFill;
        self.iv.clipsToBounds = YES;
        self.iv.backgroundColor = VGSurface2;
        self.iv.layer.cornerRadius = 12;
        self.iv.layer.cornerCurve = kCACornerCurveContinuous;
        self.label = [UILabel new];
        self.label.font = VGFont(11, UIFontWeightSemibold);
        self.label.textColor = VGSecondary;
        self.label.numberOfLines = 2;
        UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[self.iv, self.label]];
        s.axis = UILayoutConstraintAxisVertical;
        s.spacing = 5;
        s.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:s];
        [NSLayoutConstraint activateConstraints:@[[s.topAnchor constraintEqualToAnchor:self.contentView.topAnchor], [s.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
                                                  [s.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor], [self.iv.heightAnchor constraintEqualToAnchor:self.iv.widthAnchor]]];
    }
    return self;
}
@end

@interface VGCoverPickerViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, copy) NSArray<VGCoverResult *> *results;
@property (nonatomic, strong) UICollectionView *grid;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIImage *> *thumbs;
@end

@implementation VGCoverPickerViewController

- (instancetype)initWithResults:(NSArray<VGCoverResult *> *)r {
    if ((self = [super init])) { _results = r; _thumbs = [NSMutableDictionary dictionary]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Choose cover art";
    self.view.backgroundColor = VGBackground;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    UICollectionViewFlowLayout *l = [UICollectionViewFlowLayout new];
    l.minimumInteritemSpacing = 14;
    l.minimumLineSpacing = 18;
    l.sectionInset = UIEdgeInsetsMake(16, 20, 24, 20);
    self.grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:l];
    self.grid.backgroundColor = VGBackground;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.grid registerClass:VGCoverCell.class forCellWithReuseIdentifier:@"c"];
    self.grid.frame = self.view.bounds;
    self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.grid];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UICollectionViewFlowLayout *l = (UICollectionViewFlowLayout *)self.grid.collectionViewLayout;
    CGFloat w = floor((self.view.bounds.size.width - 40 - 14) / 2);
    CGSize want = CGSizeMake(w, w + 40);
    if (!CGSizeEqualToSize(l.itemSize, want)) { l.itemSize = want; [l invalidateLayout]; }
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.results.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    VGCoverCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:ip];
    VGCoverResult *r = self.results[ip.item];
    c.label.text = [NSString stringWithFormat:@"%@\n%@", r.album.length ? r.album : r.title, r.artist];
    c.iv.image = self.thumbs[@(ip.item)];
    if (!c.iv.image) {
        NSInteger i = ip.item;
        __weak typeof(self) ws = self;
        [VGCoverSearch loadImage:r.smallURL completion:^(UIImage *img) {
            if (!img || !ws) return;
            ws.thumbs[@(i)] = img;
            VGCoverCell *now = (VGCoverCell *)[ws.grid cellForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
            now.iv.image = img;
        }];
    }
    return c;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    VGCoverResult *r = self.results[ip.item];
    UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [sp startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:sp];
    cv.userInteractionEnabled = NO;
    __weak typeof(self) ws = self;
    [VGCoverSearch loadImage:r.bigURL completion:^(UIImage *img) {
        if (!ws) return;
        if (!img) img = ws.thumbs[@(ip.item)];
        if (!img) {
            cv.userInteractionEnabled = YES;
            ws.navigationItem.rightBarButtonItem = nil;
            [VGActions alert:@"Couldn't download that picture" message:@"Try another one." from:ws];
            return;
        }
        void (^pick)(UIImage *, VGCoverResult *) = ws.onPick;
        [ws dismissViewControllerAnimated:YES completion:^{ if (pick) pick(img, r); }];
    }];
}

@end
