#import "VGFolderEditorViewController.h"
#import "VGTheme.h"

static NSArray<NSString *> *presetColors(void) {
    return @[@"FF3D68", @"FF9F0A", @"FFD60A", @"30D158", @"40C8E0", @"0A84FF", @"5E5CE6", @"BF5AF2", @"AC8E68", @"98989D"];
}

@interface VGFolderEditorViewController () <UITextFieldDelegate>
@property (nonatomic, strong, nullable) VGFolder *folder;
@property (nonatomic, copy) NSString *hex;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) NSMutableArray<UIButton *> *swatches;
@property (nonatomic, strong) UIColorWell *well;
@end

@implementation VGFolderEditorViewController

+ (UINavigationController *)sheetWithFolder:(VGFolder *)folder onSave:(void (^)(NSString *, NSString *))onSave {
    VGFolderEditorViewController *vc = [[VGFolderEditorViewController alloc] initWithFolder:folder];
    vc.onSave = onSave;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.navigationBar.tintColor = VGAccent;
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sp = nav.sheetPresentationController;
    if (sp) {
        sp.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        sp.prefersGrabberVisible = YES;
    }
    return nav;
}

- (instancetype)initWithFolder:(VGFolder *)folder {
    if ((self = [super init])) {
        _folder = folder;
        _hex = folder.colorHex ?: @"0A84FF";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VGBackground;
    self.title = self.folder ? @"Edit Folder" : @"New Folder";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItem = save;

    UIImageSymbolConfiguration *big = [UIImageSymbolConfiguration configurationWithPointSize:64 weight:UIImageSymbolWeightRegular];
    self.preview = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"folder.fill" withConfiguration:big]];
    self.preview.contentMode = UIViewContentModeScaleAspectFit;
    [self.preview.heightAnchor constraintEqualToConstant:76].active = YES;

    self.field = [UITextField new];
    self.field.text = self.folder.name;
    self.field.placeholder = @"Folder name";
    self.field.font = VGFont(17, UIFontWeightSemibold);
    self.field.textColor = VGText;
    self.field.tintColor = VGAccent;
    self.field.backgroundColor = VGSurface;
    self.field.layer.cornerRadius = 12;
    self.field.layer.borderWidth = 1;
    self.field.layer.borderColor = VGStroke.CGColor;
    self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.field.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.field.returnKeyType = UIReturnKeyDone;
    self.field.delegate = self;
    self.field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Folder name" attributes:@{NSForegroundColorAttributeName: VGTertiary}];
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 10)];
    self.field.leftView = pad;
    self.field.leftViewMode = UITextFieldViewModeAlways;
    [self.field.heightAnchor constraintEqualToConstant:50].active = YES;

    UILabel *cl = [UILabel new];
    cl.attributedText = [[NSAttributedString alloc] initWithString:@"COLOR" attributes:@{
        NSFontAttributeName: VGFont(12, UIFontWeightHeavy), NSForegroundColorAttributeName: VGTertiary, NSKernAttributeName: @1.0}];

    self.swatches = [NSMutableArray array];
    NSMutableArray<UIView *> *all = [NSMutableArray array];
    for (NSString *h in presetColors()) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.accessibilityLabel = @"Folder color";
        unsigned int v = 0;
        [[NSScanner scannerWithString:h] scanHexInt:&v];
        b.backgroundColor = VGHex(v);
        b.layer.cornerRadius = 20;
        b.layer.borderColor = UIColor.whiteColor.CGColor;
        b.restorationIdentifier = h;
        [b addTarget:self action:@selector(pickSwatch:) forControlEvents:UIControlEventTouchUpInside];
        [b.widthAnchor constraintEqualToConstant:40].active = YES;
        [b.heightAnchor constraintEqualToConstant:40].active = YES;
        [self.swatches addObject:b];
        [all addObject:b];
    }
    // Any color you like, from the system color picker.
    self.well = [UIColorWell new];
    self.well.supportsAlpha = NO;
    self.well.title = @"Custom color";
    if (![presetColors() containsObject:self.hex]) self.well.selectedColor = [self currentColor];   // a custom color from before
    [self.well addTarget:self action:@selector(wellChanged) forControlEvents:UIControlEventValueChanged];
    [self.well.widthAnchor constraintEqualToConstant:40].active = YES;
    [self.well.heightAnchor constraintEqualToConstant:40].active = YES;
    [all addObject:self.well];

    UIStackView *r1 = [self rowWith:[all subarrayWithRange:NSMakeRange(0, 6)]];
    UIStackView *r2 = [self rowWith:[all subarrayWithRange:NSMakeRange(6, all.count - 6)]];
    UIStackView *swatchBox = [[UIStackView alloc] initWithArrangedSubviews:@[r1, r2]];
    swatchBox.axis = UILayoutConstraintAxisVertical;
    swatchBox.spacing = 14;

    UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:@[self.preview, self.field, cl, swatchBox]];
    st.axis = UILayoutConstraintAxisVertical;
    st.spacing = 14;
    [st setCustomSpacing:22 afterView:self.field];
    [st setCustomSpacing:10 afterView:cl];
    st.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *sv = [UIScrollView new];
    sv.alwaysBounceVertical = YES;
    sv.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    [sv addSubview:st];
    [self.view addSubview:sv];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:g.topAnchor],
        [sv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [sv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [st.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor constant:16],
        [st.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor constant:-24],
        [st.leadingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.leadingAnchor constant:20],
        [st.trailingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.trailingAnchor constant:-20],
    ]];
    [self apply];
}

- (UIStackView *)rowWith:(NSArray<UIView *> *)views {
    UIStackView *r = [[UIStackView alloc] initWithArrangedSubviews:views];
    r.axis = UILayoutConstraintAxisHorizontal;
    r.distribution = UIStackViewDistributionEqualSpacing;
    r.alignment = UIStackViewAlignmentCenter;
    // Keep both rows the same width, so the 5 and 6 colors line up under each other.
    if (views.count < 6) {
        UIView *spacer = [UIView new];
        [spacer.widthAnchor constraintEqualToConstant:40].active = YES;
        [spacer.heightAnchor constraintEqualToConstant:40].active = YES;
        spacer.userInteractionEnabled = NO;
        [r addArrangedSubview:spacer];
    }
    return r;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.folder) [self.field becomeFirstResponder];
}

// Shows the chosen color on the big folder and rings the matching swatch.
- (void)apply {
    self.preview.tintColor = [self currentColor];
    BOOL matched = NO;
    for (UIButton *b in self.swatches) {
        BOOL on = [b.restorationIdentifier isEqualToString:self.hex];
        b.layer.borderWidth = on ? 3 : 0;
        if (on) matched = YES;
    }
    self.well.layer.borderColor = UIColor.whiteColor.CGColor;
    self.well.layer.cornerRadius = 20;
    self.well.layer.borderWidth = matched ? 0 : 3;
}

- (UIColor *)currentColor {
    unsigned int v = 0;
    [[NSScanner scannerWithString:self.hex] scanHexInt:&v];
    return VGHex(v);
}

- (void)pickSwatch:(UIButton *)b {
    self.hex = b.restorationIdentifier;
    [self.field resignFirstResponder];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self apply];
}

- (void)wellChanged {
    if (!self.well.selectedColor) return;
    self.hex = [VGFolder hexFromColor:self.well.selectedColor];
    [self apply];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    return YES;
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)save {
    NSString *name = self.field.text ?: @"";
    void (^cb)(NSString *, NSString *) = self.onSave;
    NSString *hex = self.hex;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) cb(name, hex); }];
}

@end
