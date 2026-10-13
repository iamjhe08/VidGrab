#import "VGThemeGalleryViewController.h"
#import "VGCustomThemeViewController.h"
#import "VGCustomTheme.h"
#import "VGThemeViews.h"
#import "VGTheme.h"
#import "VGLocalize.h"
#import "VGActions.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface VGThemeCell : UITableViewCell
@property (nonatomic, strong) VGThemePreviewView *preview;
@property (nonatomic, strong) UILabel *nameLabel, *detailLabel;
@property (nonatomic, strong) UIImageView *check;
@property (nonatomic, strong) UIButton *more;
@end

@implementation VGThemeCell
- (instancetype)initWithStyle:(UITableViewCellStyle)st reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:st reuseIdentifier:rid])) {
        _preview = [VGThemePreviewView new]; _preview.compact = YES; _preview.layer.borderWidth = 1;
        _nameLabel = [UILabel new]; _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _detailLabel = [UILabel new]; _detailLabel.font = [UIFont systemFontOfSize:12]; _detailLabel.numberOfLines = 1;
        _check = [UIImageView new]; _check.image = [UIImage systemImageNamed:@"checkmark.circle.fill"]; _check.contentMode = UIViewContentModeScaleAspectFit;
        _more = [UIButton buttonWithType:UIButtonTypeSystem];
        [_more setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
        _more.showsMenuAsPrimaryAction = YES;
        for (UIView *v in @[_preview, _nameLabel, _detailLabel, _check, _more]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self.contentView addSubview:v]; }
        [NSLayoutConstraint activateConstraints:@[
            [_preview.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_preview.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_preview.widthAnchor constraintEqualToConstant:64], [_preview.heightAnchor constraintEqualToConstant:44],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_preview.trailingAnchor constant:14],
            [_nameLabel.bottomAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:1],
            [_detailLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_detailLabel.topAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:2],
            [_more.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
            [_more.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_more.widthAnchor constraintEqualToConstant:40], [_more.heightAnchor constraintEqualToConstant:40],
            [_check.trailingAnchor constraintEqualToAnchor:_more.leadingAnchor constant:-2],
            [_check.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_check.widthAnchor constraintEqualToConstant:24], [_check.heightAnchor constraintEqualToConstant:24],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_check.leadingAnchor constant:-8],
            [_detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_check.leadingAnchor constant:-8],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:64],
        ]];
    }
    return self;
}
@end

@interface VGThemeGalleryViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSArray<NSNumber *> *presets;
@property (nonatomic, strong) NSArray<VGThemeSpec *> *customs;
@property (nonatomic, strong) NSURL *tempExport;
@end

@implementation VGThemeGalleryViewController

+ (void)presentFrom:(UIViewController *)host {
    VGThemeGalleryViewController *vc = [[VGThemeGalleryViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.overrideUserInterfaceStyle = VGInterfaceStyle;
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = VGT(@"Themes");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.tableView.backgroundColor = VGScreen;
    self.tableView.separatorColor = VGStroke;
    NSMutableArray *p = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)VGPalette.all.count; i++) if (i != VGCustomThemeSlot) [p addObject:@(i)];
    self.presets = p;
    [self reload];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)reload { self.customs = [VGThemeStore all]; [self.tableView reloadData]; }

#pragma mark Data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s == 0 ? (NSInteger)self.presets.count : (NSInteger)self.customs.count + 2; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return VGT(s == 0 ? @"Built-in presets" : @"Custom themes"); }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return s == 0 ? VGT(@"Presets can't be changed. Use Customize to make your own copy.") : (self.customs.count ? nil : VGT(@"Themes you make or import appear here."));
}
- (void)tableView:(UITableView *)t willDisplayHeaderView:(UIView *)v forSection:(NSInteger)s {
    if ([v isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)v).textLabel.textColor = VGSecondary;
}
- (void)tableView:(UITableView *)t willDisplayFooterView:(UIView *)v forSection:(NSInteger)s {
    if ([v isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)v).textLabel.textColor = VGTertiary;
}

- (UITableViewCell *)actionCell:(NSString *)title icon:(NSString *)icon {
    UITableViewCell *c = [UITableViewCell new];
    c.backgroundColor = VGSurface; c.textLabel.text = VGT(title); c.textLabel.textColor = VGAccent;
    c.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    c.imageView.image = [UIImage systemImageNamed:icon]; c.imageView.tintColor = VGAccent;
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 1 && ip.row >= (NSInteger)self.customs.count) {
        return ip.row == (NSInteger)self.customs.count ? [self actionCell:@"New custom theme" icon:@"plus.circle.fill"] : [self actionCell:@"Import a theme file" icon:@"square.and.arrow.down"];
    }
    VGThemeCell *c = [t dequeueReusableCellWithIdentifier:@"theme"];
    if (!c) c = [[VGThemeCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"theme"];
    c.backgroundColor = VGSurface;
    c.nameLabel.textColor = VGText; c.detailLabel.textColor = VGSecondary; c.check.tintColor = VGAccent; c.more.tintColor = VGSecondary;
    c.preview.layer.borderColor = VGStroke.CGColor;
    VGPalette *p; UIImage *bg = nil; BOOL active; NSArray<UIAction *> *actions;
    __weak typeof(self) w = self;
    if (ip.section == 0) {
        NSInteger i = self.presets[ip.row].integerValue;
        p = VGPalette.all[i];
        if (p.carbon) bg = [self thumbForPresetCarbon];
        active = VGPalette.selectedIndex == i;
        c.nameLabel.text = p.title; c.detailLabel.text = VGT(p.detail);
        actions = @[[UIAction actionWithTitle:VGT(@"Apply") image:[UIImage systemImageNamed:@"checkmark.circle"] identifier:nil handler:^(UIAction *a) { [w applyPreset:i]; }],
                    [UIAction actionWithTitle:VGT(@"Customize") image:[UIImage systemImageNamed:@"slider.horizontal.3"] identifier:nil handler:^(UIAction *a) { [w customizePreset:i]; }]];
    } else {
        VGThemeSpec *s = self.customs[ip.row];
        p = [VGPalette paletteForSpec:s];
        if (p.carbon) bg = [self thumbForSpec:s];
        active = VGPalette.selectedIndex == VGCustomThemeSlot && [VGThemeStore.active.identifier isEqual:s.identifier];
        c.nameLabel.text = s.name; c.detailLabel.text = VGT(@"Custom theme");
        actions = @[[UIAction actionWithTitle:VGT(@"Apply") image:[UIImage systemImageNamed:@"checkmark.circle"] identifier:nil handler:^(UIAction *a) { [w applyCustom:s]; }],
                    [UIAction actionWithTitle:VGT(@"Edit") image:[UIImage systemImageNamed:@"slider.horizontal.3"] identifier:nil handler:^(UIAction *a) { [w editCustom:s]; }],
                    [UIAction actionWithTitle:VGT(@"Rename") image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(UIAction *a) { [w renameCustom:s]; }],
                    [UIAction actionWithTitle:VGT(@"Duplicate") image:[UIImage systemImageNamed:@"plus.square.on.square"] identifier:nil handler:^(UIAction *a) { [w duplicateCustom:s]; }],
                    [UIAction actionWithTitle:VGT(@"Export") image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *a) { [w exportCustom:s]; }],
                    ({ UIAction *d = [UIAction actionWithTitle:VGT(@"Delete") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *a) { [w deleteCustom:s]; }]; d.attributes = UIMenuElementAttributesDestructive; d; })];
    }
    [c.preview showPalette:p background:bg];
    c.check.hidden = !active;
    c.more.menu = [UIMenu menuWithChildren:actions];
    c.more.accessibilityLabel = VGT(@"More");
    c.accessibilityTraits = active ? UIAccessibilityTraitSelected : 0;
    return c;
}

// Small pictures for themes that sit on a texture, gradient or photo.
- (UIImage *)thumbForPresetCarbon {
    static UIImage *img;
    if (!img) { VGThemeSpec *s = [VGThemeSpec specFromPreset:6]; img = VGRenderThemeBackground(s, CGSizeMake(64, 44), 2, nil); }
    return img;
}
- (UIImage *)thumbForSpec:(VGThemeSpec *)s {
    if ([s.bgMode isEqual:@"photo"]) {
        // Photos are decoded off the main thread, then the row updates.
        static NSCache *cache; if (!cache) cache = [NSCache new];
        NSString *key = s.cacheKey; UIImage *hit = [cache objectForKey:key];
        if (hit) return hit;
        VGRenderThemeBackgroundAsync(s, CGSizeMake(64, 44), 2, nil, ^(UIImage *img) {
            if (!img) return;
            [cache setObject:img forKey:key];
            [self.tableView reloadData];
        });
        return nil;
    }
    return VGRenderThemeBackground(s, CGSizeMake(64, 44), 2, nil);
}

#pragma mark Selection

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) { [self applyPreset:self.presets[ip.row].integerValue]; return; }
    if (ip.row < (NSInteger)self.customs.count) { [self applyCustom:self.customs[ip.row]]; return; }
    if (ip.row == (NSInteger)self.customs.count) { [self newCustom]; return; }
    [self importTheme];
}

- (void)applyPreset:(NSInteger)i {
    [self dismissViewControllerAnimated:YES completion:^{
        if (i == VGPalette.selectedIndex) return;
        [VGPalette selectIndex:i];
        [NSNotificationCenter.defaultCenter postNotificationName:VGThemeDidChangeNotification object:nil];
    }];
}
- (void)applyCustom:(VGThemeSpec *)s {
    [self dismissViewControllerAnimated:YES completion:^{ [VGThemeStore apply:s]; }];
}

- (void)openEditor:(VGThemeSpec *)spec isNew:(BOOL)isNew {
    __weak typeof(self) w = self;
    [VGCustomThemeViewController presentFrom:self spec:spec isNew:isNew onSaved:^(VGThemeSpec *saved) {
        // Saving closes the editor and the gallery and switches the app to the saved theme.
        UIViewController *host = w.presentingViewController;
        [host dismissViewControllerAnimated:YES completion:^{ [VGThemeStore apply:saved]; }];
    }];
}
- (void)customizePreset:(NSInteger)i {
    VGThemeSpec *s = [VGThemeSpec specFromPreset:i];
    s.name = [VGThemeStore uniqueNameFor:[NSString stringWithFormat:@"%@ custom", VGPalette.all[i].title] excluding:s.identifier];
    [self openEditor:s isNew:YES];
}
- (void)newCustom {
    VGThemeSpec *s = [VGThemeSpec specFromPreset:0];
    s.name = [VGThemeStore uniqueNameFor:@"My Theme" excluding:s.identifier];
    [self openEditor:s isNew:YES];
}
- (void)editCustom:(VGThemeSpec *)s { [self openEditor:s isNew:NO]; }

#pragma mark Manage

- (void)renameCustom:(VGThemeSpec *)s {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:VGT(@"Rename theme") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = s.name; f.autocapitalizationType = UITextAutocapitalizationTypeWords; f.clearButtonMode = UITextFieldViewModeWhileEditing; }];
    [a addAction:[UIAlertAction actionWithTitle:VGT(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:VGT(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *n = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!n.length) return;
        VGThemeSpec *c = [s copy]; c.name = [VGThemeStore uniqueNameFor:n excluding:s.identifier];
        [VGThemeStore saveSpec:c]; [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)duplicateCustom:(VGThemeSpec *)s {
    VGThemeSpec *c = [s copy];
    c.identifier = NSUUID.UUID.UUIDString;
    c.name = [VGThemeStore uniqueNameFor:[s.name stringByAppendingString:@" copy"] excluding:c.identifier];
    if (s.hasPhoto) [NSFileManager.defaultManager copyItemAtPath:s.photoPath toPath:c.photoPath error:nil];
    [VGThemeStore saveSpec:c]; [self reload];
}

- (void)deleteCustom:(VGThemeSpec *)s {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:VGT(@"Delete “%@”?"), s.name] message:VGT(@"This can't be undone. Presets are not affected.") preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:VGT(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:VGT(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        BOOL wasActive = VGPalette.selectedIndex == VGCustomThemeSlot && [VGThemeStore.active.identifier isEqual:s.identifier];
        [VGThemeStore deleteSpec:s]; [self reload];
        if (wasActive) [NSNotificationCenter.defaultCenter postNotificationName:VGThemeDidChangeNotification object:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)exportCustom:(VGThemeSpec *)s {
    NSData *data = [VGThemeStore exportDataForSpec:s];
    NSString *safe = [[s.name componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"]] componentsJoinedByString:@"-"];
    NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"VidGrab Theme %@.json", safe]]];
    if (![data writeToURL:tmp atomically:YES]) { [VGActions alert:@"Couldn't save the theme file" message:nil from:self]; return; }
    self.tempExport = tmp;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[tmp] asCopy:YES];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)importTheme {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON, UTTypePlainText, UTTypeData] asCopy:YES];
    p.delegate = self; p.allowsMultipleSelection = NO;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.tempExport) { [NSFileManager.defaultManager removeItemAtURL:self.tempExport error:nil]; self.tempExport = nil; return; }   // an export finished
    NSURL *u = urls.firstObject;
    NSData *data = u ? [NSData dataWithContentsOfURL:u] : nil;
    NSString *msg = nil; BOOL needsPhoto = NO;
    VGThemeSpec *s = [VGThemeStore importData:data message:&msg needsPhoto:&needsPhoto];
    if (!s) { [VGActions alert:@"Couldn't import the theme" message:msg from:self]; return; }
    [self reload];
    [VGActions alert:[NSString stringWithFormat:VGT(@"Imported “%@”"), s.name]
             message:needsPhoto ? @"The photo wasn't included in the file. Edit the theme to choose a new one." : @"You can find it under Custom themes."
                from:self];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)c {
    if (self.tempExport) { [NSFileManager.defaultManager removeItemAtURL:self.tempExport error:nil]; self.tempExport = nil; }
}

@end
