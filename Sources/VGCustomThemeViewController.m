#import "VGCustomThemeViewController.h"
#import "VGTheme.h"
#import "VGThemeViews.h"
#import "VGLocalize.h"
#import "VGActions.h"
#import <PhotosUI/PhotosUI.h>

@interface VGCustomThemeViewController () <PHPickerViewControllerDelegate, UIColorPickerViewControllerDelegate, UITextFieldDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) VGThemeSpec *working, *original;
@property (nonatomic, assign) BOOL isNew;
@property (nonatomic, copy) void (^onSaved)(VGThemeSpec *);
@property (nonatomic, strong) UIImage *pendingPhoto;
@property (nonatomic, strong) NSData *pendingPhotoData;
@property (nonatomic, strong) UIImage *lastPhotoPreview;
@property (nonatomic, assign) NSInteger renderToken;

@property (nonatomic, strong) VGThemePreviewView *preview;
@property (nonatomic, strong) UITextField *nameField, *hexField;
@property (nonatomic, strong) UIButton *presetButton, *photoButton, *resetPhotoButton, *advancedToggle;
@property (nonatomic, strong) NSArray<UIButton *> *accentSwatches, *bgSwatches, *gradChips;
@property (nonatomic, strong) UISegmentedControl *modeControl, *directionControl;
@property (nonatomic, strong) UIStackView *colorPanel, *gradientPanel, *photoPanel, *texturePanel, *advancedPanel;
@property (nonatomic, strong) VGColorRow *bgRow, *grad1Row, *grad2Row, *textureBaseRow;
@property (nonatomic, strong) NSMutableDictionary<NSString *, VGColorRow *> *advancedRows;
@property (nonatomic, strong) NSMutableArray<UIButton *> *textureRows;
@property (nonatomic, strong) UISlider *dimSlider, *blurSlider;
@property (nonatomic, strong) UILabel *dimValue, *blurValue, *photoHint;
@property (nonatomic, copy) void (^colorApply)(unsigned);
@end

static const unsigned kAccentChoices[] = {0xFF3D68, 0xFF5500, 0xF5B800, 0x1DB954, 0x2DD4E0, 0x3E8BFF, 0x8A6CFF, 0xEC4899, 0xD9A0A7, 0xFFFFFF};
static const unsigned kBgChoices[] = {0x0A0A0D, 0x000000, 0x111827, 0x0F1F17, 0x1A1033, 0x2A0F14, 0x22101C, 0x1B1B1B, 0x0B2530, 0xF4F4F6};

static NSArray<NSDictionary *> *GradientPresets(void) {
    return @[@{@"c1": @0x2B1055, @"c2": @0x0A0A0D, @"d": @0, @"n": @"Dusk"}, @{@"c1": @0x0F3057, @"c2": @0x050B14, @"d": @1, @"n": @"Ocean"},
             @{@"c1": @0x5A1A0E, @"c2": @0x0F0605, @"d": @0, @"n": @"Ember"}, @{@"c1": @0x0F3B2A, @"c2": @0x040D09, @"d": @1, @"n": @"Forest"},
             @{@"c1": @0x5B1E3A, @"c2": @0x140812, @"d": @3, @"n": @"Rose"}, @{@"c1": @0x2A2F3A, @"c2": @0x0B0D12, @"d": @0, @"n": @"Slate"},
             @{@"c1": @0xDDEBFF, @"c2": @0xF7FAFF, @"d": @1, @"n": @"Frost"}];
}

@implementation VGCustomThemeViewController

+ (void)presentFrom:(UIViewController *)host spec:(VGThemeSpec *)spec isNew:(BOOL)isNew onSaved:(void (^)(VGThemeSpec *))onSaved {
    VGCustomThemeViewController *vc = [VGCustomThemeViewController new];
    vc.working = [spec copy]; vc.original = [spec copy]; vc.isNew = isNew; vc.onSaved = onSaved;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.presentationController.delegate = vc;
    [host presentViewController:nav animated:YES completion:nil];
}

#pragma mark Dirty state

- (BOOL)dirty { return ![self.working isEqualToSpec:self.original] || self.pendingPhoto != nil; }

- (void)updateDirtyUI {
    BOOL d = self.dirty;
    self.navigationController.modalInPresentation = d;
    self.title = d ? VGT(@"Custom Theme (edited)") : VGT(@"Custom Theme");
}

- (void)presentationControllerDidAttemptToDismiss:(UIPresentationController *)p { [self askDiscard]; }

- (void)askDiscard {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:VGT(@"Discard your changes?") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:VGT(@"Discard Changes") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [self dismissViewControllerAnimated:YES completion:nil]; }]];
    [a addAction:[UIAlertAction actionWithTitle:VGT(@"Keep Editing") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark Layout

- (UILabel *)heading:(NSString *)t {
    UILabel *l = [UILabel new]; l.text = t; l.textColor = UIColor.whiteColor; l.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    return l;
}
- (UILabel *)note:(NSString *)t {
    UILabel *l = [UILabel new]; l.text = t; l.textColor = VGHex(0xA3A3AE); l.font = [UIFont systemFontOfSize:13]; l.numberOfLines = 0;
    return l;
}
- (UIButton *)wideButton:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    b.tintColor = UIColor.whiteColor; b.backgroundColor = VGHex(0x1F1F27); b.layer.cornerRadius = 12;
    [b.heightAnchor constraintEqualToConstant:46].active = YES;
    if (sel) [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (NSArray<UIButton *> *)swatches:(const unsigned *)hexes count:(int)n action:(SEL)sel into:(UIStackView *)row {
    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; i < n; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.backgroundColor = VGHex(hexes[i]); b.tag = hexes[i];
        b.layer.cornerRadius = 8; b.layer.borderWidth = 1; b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        b.accessibilityLabel = VGHexString(hexes[i]);
        [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:b]; [out addObject:b];
    }
    return out;
}
- (UIStackView *)hstackFill {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal; row.distribution = UIStackViewDistributionFillEqually; row.spacing = 6;
    [row.heightAnchor constraintEqualToConstant:36].active = YES;
    return row;
}
- (UIStackView *)vstack:(CGFloat)spacing {
    UIStackView *s = [[UIStackView alloc] init]; s.axis = UILayoutConstraintAxisVertical; s.spacing = spacing; return s;
}
- (VGColorRow *)colorRow:(NSString *)title action:(SEL)sel {
    VGColorRow *r = [VGColorRow new]; r.title = title;
    [r addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return r;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VGHex(0x0A0A0D);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:VGT(@"Cancel") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:VGT(@"Save") style:UIBarButtonItemStyleDone target:self action:@selector(save)];

    self.preview = [VGThemePreviewView new];
    self.preview.translatesAutoresizingMaskIntoConstraints = NO;
    self.preview.layer.cornerRadius = 16;
    [self.view addSubview:self.preview];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO; scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];
    UIStackView *stack = [self vstack:14];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.preview.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [self.preview.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.preview.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.preview.heightAnchor constraintEqualToConstant:178],
        [scroll.topAnchor constraintEqualToAnchor:self.preview.bottomAnchor constant:6],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-40],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-16],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-32],
    ]];

    // Name and starting point
    self.nameField = [UITextField new];
    self.nameField.placeholder = @"Theme name"; self.nameField.text = self.working.name;
    self.nameField.textColor = UIColor.whiteColor; self.nameField.backgroundColor = VGHex(0x15151B); self.nameField.layer.cornerRadius = 12;
    self.nameField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 10)]; self.nameField.leftViewMode = UITextFieldViewModeAlways;
    self.nameField.returnKeyType = UIReturnKeyDone; self.nameField.delegate = self; self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.nameField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:VGT(@"Theme name") attributes:@{NSForegroundColorAttributeName: VGHex(0x6C6C78)}];
    [self.nameField.heightAnchor constraintEqualToConstant:46].active = YES;
    [self.nameField addTarget:self action:@selector(nameChanged) forControlEvents:UIControlEventEditingChanged];
    [stack addArrangedSubview:self.nameField];
    self.presetButton = [self wideButton:@"" action:nil];
    self.presetButton.showsMenuAsPrimaryAction = YES;
    [stack addArrangedSubview:self.presetButton];
    [stack addArrangedSubview:[self note:@"Choosing a preset loads its colors into this theme. The preset itself never changes."]];

    // Accent
    [stack addArrangedSubview:[self heading:@"Accent color"]];
    UIStackView *accentRow = [self hstackFill];
    self.accentSwatches = [self swatches:kAccentChoices count:10 action:@selector(accentSwatch:) into:accentRow];
    [stack addArrangedSubview:accentRow];
    UIStackView *hexLine = [[UIStackView alloc] init]; hexLine.axis = UILayoutConstraintAxisHorizontal; hexLine.spacing = 8;
    self.hexField = [UITextField new];
    self.hexField.placeholder = @"#RRGGBB"; self.hexField.textColor = UIColor.whiteColor; self.hexField.backgroundColor = VGHex(0x15151B); self.hexField.layer.cornerRadius = 12;
    self.hexField.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular]; self.hexField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.hexField.autocorrectionType = UITextAutocorrectionTypeNo; self.hexField.returnKeyType = UIReturnKeyDone; self.hexField.delegate = self;
    self.hexField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 10)]; self.hexField.leftViewMode = UITextFieldViewModeAlways;
    self.hexField.accessibilityLabel = @"HEX";
    [self.hexField addTarget:self action:@selector(hexEditing) forControlEvents:UIControlEventEditingChanged];
    [self.hexField.heightAnchor constraintEqualToConstant:46].active = YES;
    UIButton *copyB = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyB setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal]; copyB.tintColor = UIColor.whiteColor;
    copyB.backgroundColor = VGHex(0x1F1F27); copyB.layer.cornerRadius = 12; copyB.accessibilityLabel = VGT(@"Copy HEX value");
    [copyB addTarget:self action:@selector(copyHex) forControlEvents:UIControlEventTouchUpInside];
    UIButton *pickB = [UIButton buttonWithType:UIButtonTypeSystem];
    [pickB setImage:[UIImage systemImageNamed:@"eyedropper"] forState:UIControlStateNormal]; pickB.tintColor = UIColor.whiteColor;
    pickB.backgroundColor = VGHex(0x1F1F27); pickB.layer.cornerRadius = 12; pickB.accessibilityLabel = VGT(@"Pick any accent color");
    [pickB addTarget:self action:@selector(pickAccent) forControlEvents:UIControlEventTouchUpInside];
    [copyB.widthAnchor constraintEqualToConstant:46].active = YES; [pickB.widthAnchor constraintEqualToConstant:46].active = YES;
    [hexLine addArrangedSubview:self.hexField]; [hexLine addArrangedSubview:copyB]; [hexLine addArrangedSubview:pickB];
    [stack addArrangedSubview:hexLine];

    // Background
    [stack addArrangedSubview:[self heading:@"Background"]];
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[VGT(@"Color"), VGT(@"Gradient"), VGT(@"Photo"), VGT(@"Texture")]];
    [self.modeControl addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.modeControl];

    self.colorPanel = [self vstack:10];
    UIStackView *bgRowSw = [self hstackFill];
    self.bgSwatches = [self swatches:kBgChoices count:10 action:@selector(bgSwatch:) into:bgRowSw];
    [self.colorPanel addArrangedSubview:bgRowSw];
    self.bgRow = [self colorRow:@"Background color" action:@selector(pickBackground)];
    [self.colorPanel addArrangedSubview:self.bgRow];
    [stack addArrangedSubview:self.colorPanel];

    self.gradientPanel = [self vstack:10];
    NSMutableArray *chips = [NSMutableArray array];
    UIStackView *chipRow = [self hstackFill];
    [chipRow.heightAnchor constraintEqualToConstant:44].active = YES;
    for (NSUInteger i = 0; i < GradientPresets().count; i++) {
        NSDictionary *g = GradientPresets()[i];
        VGThemeSpec *t = [VGThemeSpec new]; t.bgMode = @"gradient"; t.grad1 = [g[@"c1"] unsignedIntValue]; t.grad2 = [g[@"c2"] unsignedIntValue]; t.gradDirection = [g[@"d"] integerValue];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.tag = i;
        [b setBackgroundImage:VGRenderThemeBackground(t, CGSizeMake(44, 44), 2, nil) forState:UIControlStateNormal];
        b.layer.cornerRadius = 10; b.clipsToBounds = YES; b.layer.borderWidth = 1; b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        b.accessibilityLabel = g[@"n"];
        [b addTarget:self action:@selector(gradientPreset:) forControlEvents:UIControlEventTouchUpInside];
        [chipRow addArrangedSubview:b]; [chips addObject:b];
    }
    self.gradChips = chips;
    [self.gradientPanel addArrangedSubview:chipRow];
    self.grad1Row = [self colorRow:@"First color" action:@selector(pickGrad1)];
    self.grad2Row = [self colorRow:@"Second color" action:@selector(pickGrad2)];
    [self.gradientPanel addArrangedSubview:self.grad1Row]; [self.gradientPanel addArrangedSubview:self.grad2Row];
    self.directionControl = [[UISegmentedControl alloc] initWithItems:@[[UIImage systemImageNamed:@"arrow.down"], [UIImage systemImageNamed:@"arrow.down.right"], [UIImage systemImageNamed:@"arrow.right"], [UIImage systemImageNamed:@"arrow.up.right"]]];
    [self.directionControl addTarget:self action:@selector(directionChanged) forControlEvents:UIControlEventValueChanged];
    [self.gradientPanel addArrangedSubview:[self note:@"Direction"]];
    [self.gradientPanel addArrangedSubview:self.directionControl];
    [stack addArrangedSubview:self.gradientPanel];

    self.photoPanel = [self vstack:10];
    self.photoButton = [self wideButton:@"Choose a photo" action:@selector(pickPhoto)];
    [self.photoPanel addArrangedSubview:self.photoButton];
    self.photoHint = [self note:@"Pick a photo to use as the background."];
    [self.photoPanel addArrangedSubview:self.photoHint];
    [self.photoPanel addArrangedSubview:[self sliderBlock:@"Darken the photo so text stays easy to read" slider:&_dimSlider value:&_dimValue max:0.85 action:@selector(dimChanged)]];
    [self.photoPanel addArrangedSubview:[self sliderBlock:@"Blur" slider:&_blurSlider value:&_blurValue max:1 action:@selector(blurChanged)]];
    self.resetPhotoButton = [self wideButton:@"Reset photo adjustments" action:@selector(resetPhotoAdjust)];
    [self.photoPanel addArrangedSubview:self.resetPhotoButton];
    [stack addArrangedSubview:self.photoPanel];

    self.texturePanel = [self vstack:8];
    self.textureRows = [NSMutableArray array];
    for (NSUInteger i = 0; i < VGTextureIDs().count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem]; b.tag = i;
        [b setTitle:VGT(VGTextureTitle(VGTextureIDs()[i])) forState:UIControlStateNormal];
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
        b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        b.tintColor = UIColor.whiteColor; b.backgroundColor = VGHex(0x15151B); b.layer.cornerRadius = 12;
        [b.heightAnchor constraintEqualToConstant:44].active = YES;
        [b addTarget:self action:@selector(textureTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.texturePanel addArrangedSubview:b]; [self.textureRows addObject:b];
    }
    self.textureBaseRow = [self colorRow:@"Base color" action:@selector(pickTextureBase)];
    [self.texturePanel addArrangedSubview:self.textureBaseRow];
    [self.texturePanel addArrangedSubview:[self note:@"Textures are drawn on the device and stay subtle so text is easy to read."]];
    [stack addArrangedSubview:self.texturePanel];

    // Advanced colors
    self.advancedToggle = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.advancedToggle setTitle:VGT(@"Advanced Colors") forState:UIControlStateNormal];
    [self.advancedToggle setImage:[UIImage systemImageNamed:@"chevron.right"] forState:UIControlStateNormal];
    self.advancedToggle.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.advancedToggle.titleEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
    self.advancedToggle.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.advancedToggle.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    self.advancedToggle.tintColor = UIColor.whiteColor;
    [self.advancedToggle addTarget:self action:@selector(toggleAdvanced) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.advancedToggle];
    self.advancedPanel = [self vstack:8]; self.advancedPanel.hidden = YES;
    self.advancedRows = [NSMutableDictionary dictionary];
    NSArray *adv = @[@[@"text", @"Primary text"], @[@"secondary", @"Secondary text"], @[@"surface", @"Cards and surfaces"], @[@"stroke", @"Borders and separators"],
                     @[@"buttonBg", @"Button color"], @[@"buttonFg", @"Button text"], @[@"selected", @"Selected highlight"], @[@"bars", @"Tab bar"]];
    for (NSArray *a in adv) {
        VGColorRow *r = [self colorRow:a[1] action:@selector(pickAdvanced:)];
        NSString *key = a[0]; r.accessibilityIdentifier = key;
        __weak typeof(self) w = self;
        r.onReset = ^{ [w.working.overrides removeObjectForKey:key]; [w refresh]; };
        self.advancedRows[key] = r; [self.advancedPanel addArrangedSubview:r];
    }
    [self.advancedPanel addArrangedSubview:[self note:@"Sliders and toggles follow the accent color. Anything you don't change stays as the theme or preset sets it."]];
    [stack addArrangedSubview:self.advancedPanel];

    // Reset / save as new
    UIButton *resetB = [self wideButton:@"Reset" action:@selector(resetTapped)];
    resetB.tintColor = VGHex(0xFF8A8A);
    [stack addArrangedSubview:resetB];
    if (!self.isNew) [stack addArrangedSubview:[self wideButton:@"Save as New Theme" action:@selector(saveAsNew)]];

    [self buildPresetMenu];
    [self refresh];
}

- (UIView *)sliderBlock:(NSString *)title slider:(UISlider *__strong *)sl value:(UILabel *__strong *)vl max:(float)max action:(SEL)sel {
    UIStackView *v = [self vstack:6];
    UIStackView *top = [[UIStackView alloc] init]; top.axis = UILayoutConstraintAxisHorizontal;
    UILabel *t = [self note:title]; *vl = [UILabel new]; (*vl).textColor = UIColor.whiteColor; (*vl).font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    [(*vl) setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [top addArrangedSubview:t]; [top addArrangedSubview:*vl];
    *sl = [UISlider new]; (*sl).minimumValue = 0; (*sl).maximumValue = max; (*sl).accessibilityLabel = title;
    [(*sl) addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [v addArrangedSubview:top]; [v addArrangedSubview:*sl];
    return v;
}

- (void)buildPresetMenu {
    NSMutableArray *items = [NSMutableArray array];
    NSArray<VGPalette *> *all = VGPalette.all;
    __weak typeof(self) w = self;
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) {
        if (i == VGCustomThemeSlot) continue;
        [items addObject:[UIAction actionWithTitle:all[i].title image:nil identifier:nil handler:^(UIAction *a) { [w loadPreset:i]; }]];
    }
    self.presetButton.menu = [UIMenu menuWithTitle:VGT(@"Start from a preset") children:items];
}

- (void)loadPreset:(NSInteger)i {
    void (^go)(void) = ^{
        VGThemeSpec *n = [VGThemeSpec specFromPreset:i];
        n.identifier = self.working.identifier; n.name = self.working.name; n.dim = self.working.dim; n.blur = self.working.blur;
        self.working = n;
        [self refresh];
    };
    if (!self.dirty) { go(); return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:VGT(@"Replace your changes?") message:VGT(@"The colors of this preset will replace the changes you made in this editor.") preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:VGT(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:VGT(@"Replace") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { go(); }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark Refresh

- (unsigned)inheritedValueForKey:(NSString *)key {
    VGThemeSpec *c = [self.working copy]; c.assumePhoto = self.pendingPhoto != nil;
    [c.overrides removeObjectForKey:key];
    VGPalette *p = [VGPalette paletteForSpec:c];
    UIColor *bg = nil, *fg = nil; VGPrimaryButtonColors(p, &bg, &fg);
    if ([key isEqual:@"text"]) return VGHexOf(p.text);
    if ([key isEqual:@"secondary"]) return VGHexOf(p.secondary);
    if ([key isEqual:@"surface"]) return VGHexOf(p.surface);
    if ([key isEqual:@"stroke"]) return VGHexOf(p.stroke);
    if ([key isEqual:@"buttonBg"]) return VGHexOf(bg ?: p.accent);
    if ([key isEqual:@"buttonFg"]) return VGHexOf(fg ?: UIColor.whiteColor);
    if ([key isEqual:@"selected"]) return VGHexOf(p.selectedCell);
    return VGHexOf(p.tabBar);
}

- (void)refresh {
    VGThemeSpec *s = self.working;
    s.assumePhoto = self.pendingPhoto != nil;
    // controls
    NSString *mode = s.bgMode;
    NSUInteger mi = [@[@"color", @"gradient", @"photo", @"texture"] indexOfObject:mode];
    self.modeControl.selectedSegmentIndex = mi == NSNotFound ? 0 : mi;
    self.colorPanel.hidden = ![mode isEqual:@"color"]; self.gradientPanel.hidden = ![mode isEqual:@"gradient"];
    self.photoPanel.hidden = ![mode isEqual:@"photo"]; self.texturePanel.hidden = ![mode isEqual:@"texture"];
    if (![self.nameField isFirstResponder]) self.nameField.text = s.name;
    [self.presetButton setTitle:[NSString stringWithFormat:@"%@: %@", VGT(@"Start from a preset"), VGPalette.all[s.base].title] forState:UIControlStateNormal];
    if (![self.hexField isFirstResponder]) self.hexField.text = VGHexString(s.accent);
    self.hexField.layer.borderWidth = 0;
    for (UIButton *b in self.accentSwatches) b.layer.borderWidth = (b.tag == (NSInteger)s.accent) ? 3 : 1, b.layer.borderColor = ((b.tag == (NSInteger)s.accent) ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.25]).CGColor;
    for (UIButton *b in self.bgSwatches) b.layer.borderWidth = (b.tag == (NSInteger)s.bgColor) ? 3 : 1, b.layer.borderColor = ((b.tag == (NSInteger)s.bgColor) ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.25]).CGColor;
    self.bgRow.value = s.bgColor; self.grad1Row.value = s.grad1; self.grad2Row.value = s.grad2; self.textureBaseRow.value = s.bgColor;
    NSArray *gp = GradientPresets();
    for (UIButton *b in self.gradChips) {
        NSDictionary *g = gp[b.tag];
        BOOL on = s.grad1 == [g[@"c1"] unsignedIntValue] && s.grad2 == [g[@"c2"] unsignedIntValue] && s.gradDirection == [g[@"d"] integerValue];
        b.layer.borderWidth = on ? 3 : 1; b.layer.borderColor = (on ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.25]).CGColor;
    }
    self.directionControl.selectedSegmentIndex = s.gradDirection;
    BOOL hasPhoto = s.hasPhoto;
    [self.photoButton setTitle:hasPhoto ? VGT(@"Change photo") : VGT(@"Choose a photo") forState:UIControlStateNormal];
    self.photoHint.hidden = hasPhoto;
    self.dimSlider.value = s.dim; self.blurSlider.value = s.blur;
    self.dimValue.text = [NSString stringWithFormat:@"%d%%", (int)lround(s.dim / 0.85 * 100)];
    self.blurValue.text = [NSString stringWithFormat:@"%d%%", (int)lround(s.blur * 100)];
    self.dimSlider.enabled = self.blurSlider.enabled = self.resetPhotoButton.enabled = hasPhoto;
    for (UIButton *b in self.textureRows) {
        BOOL on = [VGTextureIDs()[b.tag] isEqual:s.texture];
        NSString *t = VGT(VGTextureTitle(VGTextureIDs()[b.tag]));
        [b setTitle:on ? [@"\u2713  " stringByAppendingString:t] : t forState:UIControlStateNormal];
        b.backgroundColor = on ? VGHex(0x26232C) : VGHex(0x15151B);
    }
    self.textureBaseRow.hidden = [s.texture isEqual:@"carbon"];
    for (NSString *key in self.advancedRows) {
        VGColorRow *r = self.advancedRows[key];
        BOOL changed = s.overrides[key] != nil;
        r.value = changed ? s.overrides[key].unsignedIntValue : [self inheritedValueForKey:key];
        r.showsReset = changed;
    }
    [self updateDirtyUI];
    [self redrawPreview];
}

- (void)redrawPreview {
    VGThemeSpec *s = self.working;
    VGPalette *p = [VGPalette paletteForSpec:s];
    NSInteger token = ++self.renderToken;
    CGSize size = CGSizeMake(MAX(self.view.bounds.size.width - 32, 300), 178);
    if (!p.carbon) { self.lastPhotoPreview = nil; [self.preview showPalette:p background:nil]; return; }
    if ([s.bgMode isEqual:@"photo"]) {
        [self.preview showPalette:p background:self.lastPhotoPreview];
        VGRenderThemeBackgroundAsync(s, size, 2, self.pendingPhoto, ^(UIImage *img) {
            if (token != self.renderToken) return;
            self.lastPhotoPreview = img;
            [self.preview showPalette:p background:img];
        });
    } else {
        [self.preview showPalette:p background:VGRenderThemeBackground(s, size, 2, nil)];
    }
}

#pragma mark Actions

- (void)nameChanged { self.working.name = self.nameField.text ?: @""; [self updateDirtyUI]; }
- (BOOL)textFieldShouldReturn:(UITextField *)f { [f resignFirstResponder]; return YES; }
- (void)textFieldDidEndEditing:(UITextField *)f {
    if (f == self.hexField) {
        unsigned h = 0;
        if (VGParseHex(f.text, &h)) { self.working.accent = h; self.hexField.layer.borderWidth = 0; }
        else { self.hexField.layer.borderWidth = 1.5; self.hexField.layer.borderColor = VGHex(0xFF5A5F).CGColor; [VGActions toast:@"That isn't a valid HEX color" icon:@"exclamationmark.triangle.fill" in:self.view.window ?: self.view]; f.text = VGHexString(self.working.accent); self.hexField.layer.borderWidth = 0; }
    }
    [self refresh];
}
- (void)hexEditing {
    unsigned h = 0;
    NSString *t = self.hexField.text;
    NSString *bare = [t hasPrefix:@"#"] ? [t substringFromIndex:1] : t;
    if (bare.length == 6 && VGParseHex(t, &h)) { self.working.accent = h; [self refresh]; }
}
- (void)copyHex {
    UIPasteboard.generalPasteboard.string = VGHexString(self.working.accent);
    [VGActions toast:@"HEX copied" icon:@"checkmark.circle.fill" in:self.view.window ?: self.view];
}
- (void)accentSwatch:(UIButton *)b { self.working.accent = (unsigned)b.tag; [self refresh]; }
- (void)bgSwatch:(UIButton *)b { self.working.bgColor = (unsigned)b.tag; [self refresh]; }
- (void)gradientPreset:(UIButton *)b {
    NSDictionary *g = GradientPresets()[b.tag];
    self.working.grad1 = [g[@"c1"] unsignedIntValue]; self.working.grad2 = [g[@"c2"] unsignedIntValue]; self.working.gradDirection = [g[@"d"] integerValue];
    [self refresh];
}
- (void)directionChanged { self.working.gradDirection = self.directionControl.selectedSegmentIndex; [self refresh]; }
- (void)textureTapped:(UIButton *)b { self.working.texture = VGTextureIDs()[b.tag]; [self refresh]; }
- (void)dimChanged { self.working.dim = self.dimSlider.value; [self refresh]; }
- (void)blurChanged { self.working.blur = self.blurSlider.value; [self refresh]; }
- (void)resetPhotoAdjust { self.working.dim = 0.35; self.working.blur = 0; [self refresh]; }
- (void)modeChanged {
    self.working.bgMode = @[@"color", @"gradient", @"photo", @"texture"][self.modeControl.selectedSegmentIndex];
    if ([self.working.bgMode isEqual:@"photo"] && !self.working.hasPhoto) [self pickPhoto];
    [self refresh];
}
- (void)toggleAdvanced {
    BOOL show = self.advancedPanel.hidden;
    [UIView animateWithDuration:0.2 animations:^{
        self.advancedPanel.hidden = !show;
        self.advancedToggle.imageView.transform = show ? CGAffineTransformMakeRotation(M_PI_2) : CGAffineTransformIdentity;
    }];
}

- (void)presentColorPickerFor:(unsigned)current apply:(void (^)(unsigned))apply {
    self.colorApply = apply;
    UIColorPickerViewController *p = [UIColorPickerViewController new];
    p.selectedColor = VGHex(current); p.supportsAlpha = NO; p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)vc {
    if (self.colorApply) self.colorApply(VGHexOf(vc.selectedColor));
    [self refresh];
}
- (void)pickAccent { __weak typeof(self) w = self; [self presentColorPickerFor:self.working.accent apply:^(unsigned h) { w.working.accent = h; }]; }
- (void)pickBackground { __weak typeof(self) w = self; [self presentColorPickerFor:self.working.bgColor apply:^(unsigned h) { w.working.bgColor = h; }]; }
- (void)pickTextureBase { [self pickBackground]; }
- (void)pickGrad1 { __weak typeof(self) w = self; [self presentColorPickerFor:self.working.grad1 apply:^(unsigned h) { w.working.grad1 = h; }]; }
- (void)pickGrad2 { __weak typeof(self) w = self; [self presentColorPickerFor:self.working.grad2 apply:^(unsigned h) { w.working.grad2 = h; }]; }
- (void)pickAdvanced:(VGColorRow *)row {
    NSString *key = row.accessibilityIdentifier;
    __weak typeof(self) w = self;
    [self presentColorPickerFor:row.value apply:^(unsigned h) { w.working.overrides[key] = @(h); }];
}

#pragma mark Photo

- (void)pickPhoto {
    PHPickerConfiguration *cfg = [PHPickerConfiguration new];
    cfg.filter = [PHPickerFilter imagesFilter]; cfg.selectionLimit = 1;
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *r = results.firstObject;
    if (!r) {
        if (!self.working.hasPhoto && [self.working.bgMode isEqual:@"photo"]) { self.working.bgMode = @"color"; [self refresh]; }
        return;
    }
    [r.itemProvider loadObjectOfClass:UIImage.class completionHandler:^(id obj, NSError *e) {
        UIImage *img = [obj isKindOfClass:UIImage.class] ? obj : nil;
        if (!img) return;
        // Off the main thread: shrink to a sensible size so the app stays quick and backups stay small.
        CGFloat longest = MAX(img.size.width, img.size.height), k = longest > 1800 ? 1800 / longest : 1;
        CGSize s = CGSizeMake(floor(img.size.width * k), floor(img.size.height * k));
        UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat]; f.scale = 1;
        UIImage *small = [[[UIGraphicsImageRenderer alloc] initWithSize:s format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) { [img drawInRect:CGRectMake(0, 0, s.width, s.height)]; }];
        NSData *data = UIImageJPEGRepresentation(small, 0.85);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.pendingPhoto = small; self.pendingPhotoData = data;
            self.working.bgMode = @"photo";
            [self refresh];
        });
    }];
}

#pragma mark Finish

- (void)cancel {
    if (self.dirty) [self askDiscard]; else [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetTapped {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:VGT(@"Reset") message:self.dirty ? VGT(@"Your unsaved changes in this editor will be lost. Saved themes are not deleted.") : nil preferredStyle:UIAlertControllerStyleActionSheet];
    if (!self.isNew) [a addAction:[UIAlertAction actionWithTitle:VGT(@"Revert to Saved") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        self.working = [self.original copy]; self.pendingPhoto = nil; self.pendingPhotoData = nil; [self refresh];
    }]];
    NSString *pt = VGPalette.all[self.working.base].title;
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:VGT(@"Reset to %@"), pt] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        VGThemeSpec *n = [VGThemeSpec specFromPreset:self.working.base];
        n.identifier = self.working.identifier; n.name = self.working.name;
        self.working = n; [self refresh];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:VGT(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view; a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height - 60, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (VGThemeSpec *)finalSpecAsNew:(BOOL)asNew {
    VGThemeSpec *s = [self.working copy];
    if (asNew) {
        s.identifier = NSUUID.UUID.UUIDString;
        s.name = [VGThemeStore uniqueNameFor:[s.name stringByAppendingString:@" copy"] excluding:s.identifier];
    } else s.name = [VGThemeStore uniqueNameFor:s.name excluding:s.identifier];
    s.assumePhoto = NO;
    // The photo belongs to whichever theme is saved. A copy keeps the old photo when no new one was picked.
    if (self.pendingPhotoData) [self.pendingPhotoData writeToFile:s.photoPath atomically:YES];
    else if (asNew && self.working.hasPhoto) [NSFileManager.defaultManager copyItemAtPath:self.working.photoPath toPath:s.photoPath error:nil];
    return s;
}

- (void)finishWith:(VGThemeSpec *)s {
    [self.view endEditing:YES];
    [VGThemeStore saveSpec:s];
    void (^cb)(VGThemeSpec *) = self.onSaved;
    if (cb) cb(s);
}

- (void)save { [self finishWith:[self finalSpecAsNew:NO]]; }
- (void)saveAsNew { [self finishWith:[self finalSpecAsNew:YES]]; }

@end
