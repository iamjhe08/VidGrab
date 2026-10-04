#import "VGSettingsViewController.h"
#import "VGTheme.h"
#import "VGEngine.h"
#import "VGCache.h"
#import "VGActions.h"
#import "VGSupportViewController.h"

typedef NS_ENUM(NSInteger, VGSection) { VGSectionStorage, VGSectionEngine, VGSectionSupport, VGSectionAbout, VGSectionCount };

@interface VGSettingsViewController ()
@property (nonatomic, copy) NSString *cacheSize;
@property (nonatomic) BOOL clearing;
@end

@implementation VGSettingsViewController

+ (void)presentFrom:(UIViewController *)host {
    VGSettingsViewController *s = [[VGSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:s];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.navigationBar.prefersLargeTitles = NO;
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.tableView.backgroundColor = VGBackground;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self action:@selector(done)];
    self.cacheSize = @"…";
    [self refreshSize];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)refreshSize {
    [VGCache size:^(long long bytes) {
        self.cacheSize = [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:VGSectionStorage]] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return VGSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case VGSectionStorage: return 3;
        case VGSectionEngine: return 2;
        case VGSectionSupport: return 1;
        default: return 2;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return @[@"Storage", @"Download engine", @"Support", @"About"][section];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (section == VGSectionStorage)
        return @"Cache is temporary files: engine scratch files, leftover partial downloads, saved site icons and the browser's page cache. Your downloaded videos, website sign-ins, favorites and ad-blocker settings are never removed.";
    if (section == VGSectionEngine)
        return @"If downloads from a site stop working, update the engine. Sites change often and fixes arrive here first.";
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = VGTertiary;
}

- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = VGTertiary;
}

- (UITableViewCell *)cellWithTitle:(NSString *)title value:(NSString *)value icon:(NSString *)icon tint:(UIColor *)tint {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    UIListContentConfiguration *cfg = [UIListContentConfiguration valueCellConfiguration];
    cfg.text = title;
    cfg.secondaryText = value;
    cfg.textProperties.color = tint ?: VGText;
    cfg.textProperties.font = VGFont(16, UIFontWeightMedium);
    cfg.secondaryTextProperties.color = VGSecondary;
    if (icon) {
        cfg.image = [UIImage systemImageNamed:icon];
        cfg.imageProperties.tintColor = tint ?: VGAccent;
    }
    c.contentConfiguration = cfg;
    c.backgroundColor = VGSurface;
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (ip.section == VGSectionStorage) {
        if (ip.row == 0) {
            UITableViewCell *c = [self cellWithTitle:@"Cache" value:self.cacheSize icon:@"internaldrive" tint:nil];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row == 1) {
            UITableViewCell *c = [self cellWithTitle:self.clearing ? @"Clearing…" : @"Clear cache now" value:nil icon:@"trash" tint:VGAccent];
            return c;
        }
        UITableViewCell *c = [self cellWithTitle:@"Auto-clear cache on launch" value:nil icon:@"clock.arrow.circlepath" tint:nil];
        UISwitch *sw = [UISwitch new];
        sw.on = VGCache.autoClearOnLaunch;
        sw.onTintColor = VGAccent;
        [sw addTarget:self action:@selector(autoClearChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    if (ip.section == VGSectionEngine) {
        if (ip.row == 0) {
            UITableViewCell *c = [self cellWithTitle:@"yt-dlp version" value:[VGEngine shared].engineVersion icon:@"shippingbox" tint:nil];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        return [self cellWithTitle:@"Update download engine" value:nil icon:@"arrow.triangle.2.circlepath" tint:VGAccent];
    }
    if (ip.section == VGSectionSupport) {
        UITableViewCell *c = [self cellWithTitle:@"Buy me a coffee" value:nil icon:@"cup.and.saucer.fill" tint:nil];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    if (ip.row == 1) {
        UITableViewCell *c = [self cellWithTitle:@"GitHub" value:@"@iamjhe08" icon:@"chevron.left.forwardslash.chevron.right" tint:nil];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    UITableViewCell *c = [self cellWithTitle:@"VidGrab" value:[NSString stringWithFormat:@"%@ · by T4MAG0", version] icon:@"info.circle" tint:nil];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == VGSectionStorage && ip.row == 1) [self clearCache];
    else if (ip.section == VGSectionEngine && ip.row == 1) [self updateEngine];
    else if (ip.section == VGSectionSupport) [[VGSupportViewController new] presentFrom:self];
    else if (ip.section == VGSectionAbout && ip.row == 1)
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/iamjhe08"] options:@{} completionHandler:nil];
}

#pragma mark Actions

- (void)autoClearChanged:(UISwitch *)sw {
    VGCache.autoClearOnLaunch = sw.on;
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)clearCache {
    if (self.clearing) return;
    self.clearing = YES;
    [self.tableView reloadData];
    [VGCache clear:^(long long freed) {
        self.clearing = NO;
        NSString *msg = freed > 0 ? [NSString stringWithFormat:@"Cleared %@", [NSByteCountFormatter stringFromByteCount:freed countStyle:NSByteCountFormatterCountStyleFile]]
                                  : @"Cache is already empty";
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [VGActions toast:msg icon:@"checkmark.circle.fill" in:self.view.window ?: self.view];
        [self.tableView reloadData];
        [self refreshSize];
    }];
}

- (void)updateEngine {
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"Checking for updates…" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:wait animated:YES completion:nil];
    [[VGEngine shared] updateEngine:^(NSString *title, NSString *message) {
        [wait dismissViewControllerAnimated:YES completion:^{
            [VGActions alert:title message:message from:self];
            [self.tableView reloadData];
        }];
    }];
}

@end
