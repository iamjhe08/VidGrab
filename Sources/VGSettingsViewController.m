#import "VGSettingsViewController.h"
#import "VGDownloadDefaults.h"
#import "VGTheme.h"
#import "VGLocalize.h"
#import "VGEngine.h"
#import "VGCache.h"
#import "VGActions.h"
#import "VGSupportViewController.h"
#import "VGUpdater.h"
#import "VGVaultLock.h"
#import "VGKeepAlive.h"
#import "VGOverlay.h"
#import "VGPlayerGestures.h"
#import "VGSubtitles.h"
#import "VGCoverSearch.h"
#import "VGSettingsBackup.h"
#import "VGCreditsViewController.h"
#import "VGMusic.h"
#import "VGHaptics.h"
#import "VGSidebarController.h"
#import <AVFoundation/AVFoundation.h>

// The order the sections are shown in: downloading, playing, privacy, then housekeeping, and About last.
typedef NS_ENUM(NSInteger, VGSection) { VGSectionLanguage, VGSectionEngine, VGSectionDownloads, VGSectionFloat, VGSectionGestures, VGSectionSubtitles, VGSectionAudio, VGSectionInterface, VGSectionVault, VGSectionStorage, VGSectionBackup, VGSectionAbout, VGSectionCount };

@interface VGSettingsViewController ()
@property (nonatomic, copy) NSString *cacheSize;
@property (nonatomic) BOOL clearing;
@property (nonatomic, copy) NSString *shownSubtitleError;
@property (nonatomic, strong) NSMutableIndexSet *openNotes;   // sections whose explanation is showing
@end

@implementation VGSettingsViewController

+ (void)presentFrom:(UIViewController *)host {
    VGSettingsViewController *s = [[VGSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:s];
    nav.overrideUserInterfaceStyle = VGInterfaceStyle;
    nav.navigationBar.prefersLargeTitles = NO;
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.tableView.backgroundColor = VGScreen;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self action:@selector(done)];
    self.tableView.tableHeaderView = [self coffeeHeader];
    // Explanations stay hidden until the exclamation button is pressed. The one exception: on phones
    // without a jailbreak, Floating progress is greyed out, and the note says why.
    self.openNotes = [NSMutableIndexSet indexSet];
    if (!VGOverlay.bubbleAllowed && !VGOverlay.canInstallHelper) [self.openNotes addIndex:VGSectionFloat];
    self.cacheSize = @"…";
    [self refreshSize];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(subtitleModelChanged) name:VGSubtitleModelDidChange object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

// "Buy me a coffee" sits above the first section, in the same capsule style as before.
- (UIView *)coffeeHeader {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 56)];
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration];
    c.baseBackgroundColor = [VGAccent colorWithAlphaComponent:0.16];
    c.baseForegroundColor = VGAccent;
    c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    c.image = [UIImage systemImageNamed:@"cup.and.saucer.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold]];
    c.imagePadding = 7;
    c.contentInsets = NSDirectionalEdgeInsetsMake(10, 16, 10, 17);
    c.attributedTitle = [[NSAttributedString alloc] initWithString:@"Buy me a coffee" attributes:@{NSFontAttributeName: VGFont(15, UIFontWeightBold)}];
    __weak typeof(self) ws = self;
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) {
        [[UIImpactFeedbackGenerator new] impactOccurred];
        [[VGSupportViewController new] presentFrom:ws];
    }]];
    [b sizeToFit];
    b.center = CGPointMake(160, 28);
    b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [v addSubview:b];
    return v;
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)refreshSize {
    [VGCache size:^(long long bytes) {
        self.cacheSize = [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:VGSectionStorage]] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    UISwitch *sw = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : nil;
    if (!sw || sw.tag == 7117) return;   // one tap sound per switch, added once
    sw.tag = 7117;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) { [VGHaptics select]; }] forControlEvents:UIControlEventValueChanged];
}

#pragma mark Table

// The order rows are shown in. Each number is the row's original position, so the row code itself doesn't change.
- (NSArray<NSNumber *> *)rowOrderForSection:(NSInteger)section {
    switch (section) {
        case VGSectionEngine:   return @[@2, @3, @4, @0, @1];       // the two everyday switches first; engine version and update last
        case VGSectionFloat:    return @[@0, @3, @1, @2];       // each switch followed by its own test
        case VGSectionGestures: return @[@0, @2, @1, @3, @4, @5];   // each gesture followed by its own option
        default: return nil;
    }
}

- (NSInteger)originalRow:(NSIndexPath *)ip {
    NSArray<NSNumber *> *order = [self rowOrderForSection:ip.section];
    return order && ip.row < (NSInteger)order.count ? order[ip.row].integerValue : ip.row;
}

- (NSIndexPath *)shownPathForOriginalRow:(NSInteger)row section:(NSInteger)section {
    NSArray<NSNumber *> *order = [self rowOrderForSection:section];
    NSUInteger at = order ? [order indexOfObject:@(row)] : (NSUInteger)row;
    return [NSIndexPath indexPathForRow:at == NSNotFound ? row : (NSInteger)at inSection:section];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return VGSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case VGSectionStorage: return 3;
        case VGSectionEngine: return 5;
        case VGSectionDownloads: return 7;
        case VGSectionFloat: return 4;
        case VGSectionGestures: return 6;
        case VGSectionSubtitles: return 6;
        case VGSectionAudio: return 3;
        case VGSectionInterface: return 2;
        case VGSectionLanguage: return 1;
        case VGSectionBackup: return 2;
        case VGSectionVault: return [VGVaultLock usesPasscode] ? 2 : 1;
        default: return 6;   // About: version, GitHub, jailbreak repo, sideload source, check for updates, credits
    }
}

- (NSString *)sectionTitle:(NSInteger)section {
    return @[@"Language", @"Download engine", @"Downloads", @"Floating progress", @"Video player", @"Auto subtitles", @"Audio", @"Interface", @"Private Vault 2.0", @"Storage", @"Backup and restore", @"About"][section];
}

// A small exclamation button in front of the section title; it opens and closes the section's note.
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    UIView *v = [UIView new];
    UILabel *l = [UILabel new];
    l.text = VGT([self sectionTitle:section]).uppercaseString;
    l.font = VGFont(13, UIFontWeightSemibold);
    l.textColor = VGTertiary;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL open = [self.openNotes containsIndex:section];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    [b setImage:[UIImage systemImageNamed:open ? @"exclamationmark.circle.fill" : @"exclamationmark.circle" withConfiguration:cfg] forState:UIControlStateNormal];
    b.tintColor = open ? VGAccent : VGTertiary;
    b.tag = section;
    b.accessibilityLabel = [NSString stringWithFormat:@"About %@", [self sectionTitle:section]];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b addTarget:self action:@selector(toggleNote:) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:l];
    [v addSubview:b];
    // The button comes first ("ⓘ STORAGE"). It is 40 wide so it's easy to hit, and shifted left by 11 so the
    // icon itself lines up with the text of the rows below.
    [NSLayoutConstraint activateConstraints:@[
        [b.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:tv.layoutMargins.left + 16 - 11],
        [b.widthAnchor constraintEqualToConstant:40], [b.heightAnchor constraintEqualToConstant:40],
        [l.leadingAnchor constraintEqualToAnchor:b.trailingAnchor constant:-5],
        [l.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-7],
        [b.centerYAnchor constraintEqualToAnchor:l.centerYAnchor]]];
    return v;
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section { return 42; }

- (void)toggleNote:(UIButton *)b {
    NSInteger section = b.tag;
    if ([self.openNotes containsIndex:section]) [self.openNotes removeIndex:section]; else [self.openNotes addIndex:section];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:UITableViewRowAnimationFade];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    return [self.openNotes containsIndex:section] ? [self explanationForSection:section] : nil;
}

- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)section {
    return [self.openNotes containsIndex:section] ? UITableViewAutomaticDimension : 4;
}

- (NSString *)explanationForSection:(NSInteger)section {
    if (section == VGSectionStorage)
        return @"Cache is temporary files: engine scratch files, leftover partial downloads, saved site icons and the browser's page cache. Your downloaded videos, website sign-ins, favorites and ad-blocker settings are never removed.";
    if (section == VGSectionAbout)
        return @"VidGrab checks for new versions every time you open it. Updates keep your downloads and settings.";
    if (section == VGSectionDownloads)
        return [NSString stringWithFormat:@"%@\n\nConnections per download: how many pieces are fetched at once. It helps most with downloads that arrive in many small parts. Files only hides every Save to Photos button, so your downloads stay in VidGrab's folder in the Files app. Wi-Fi only makes new downloads wait while you are on mobile data or a hotspot; ones already running keep going. Auto-start shared links makes Share > VidGrab start the download by itself when a default type and quality are set above; turn it off to always see the card with the quality list and Stream. Ask to delete finished videos shows a question after a saved video plays to the end.", VGDownloadDefaults.skipSheet ? @"The Download card shows only a Start button and uses these choices. Switch to Stream on the card to see every quality. Set either one to Always ask to pick a quality every time. Playlists always ask." : @"Right now the Download card shows every quality. To get just a Start button, set Default type to Video and pick a Default quality, or set Default type to Audio only."];
    if (section == VGSectionEngine)
        return @"With Find copied links on, a video link you copied shows up on Home as soon as you open VidGrab. With Keep downloading in background on, downloads carry on when you leave the app and you get a notification when they finish. If downloads from a site stop working, update the engine: sites change often and fixes arrive here first.";
    if (section == VGSectionFloat) {
        NSString *bubble = @"With Bubble outside the app on, the download bubble stays on screen when you leave VidGrab or use other apps. It fades after 3 seconds so it won't get in the way; touch it to bring it back. Drag it anywhere, tap it to return to your downloads.";
        NSString *sound = @"Sound when done plays VidGrab's own sound when your downloads finish while you're outside the app. It never plays inside VidGrab.";
        if (VGOverlay.bubbleAllowed) return [NSString stringWithFormat:@"%@\n\n%@", bubble, sound];
        return [NSString stringWithFormat:@"Floating progress works when VidGrab is installed as a jailbreak package, or with the TrollStore .tipa file. On TrollStore, tap Install bubble helper once and choose TrollStore. The bubble inside VidGrab, background downloads and the finish notification still work here.\n\nInstalled at: %@\nIf this is a jailbreak package and these are greyed out, please report it with this line.", NSBundle.mainBundle.bundlePath];
    }
    if (section == VGSectionGestures)
        return @"In the video player, swipe up or down on one half of the screen to change brightness and on the other half to change volume. Brightness/Volume gesture turns both on or off and Brightness side picks which half does what; they work when the phone is sideways. Swipe to seek jumps forward or back as you swipe sideways, in either direction of the phone, and the video follows your finger frame by frame. Seek distance is how far one swipe across the whole screen jumps. Progress line shows a thin bar along the bottom edge while the buttons are hidden. Brightness goes back to normal when you close the player. Swipes that start on the player's own buttons still work as usual.";
    if (section == VGSectionSubtitles)
        return @"Auto subtitles listen to the video on your phone and write what is said in English, whatever the language. Nothing is uploaded and no account is needed. The speech model downloads once, only when you turn this on. It uses extra battery and warms the phone while it works, and older phones can fall behind the video, so Fast is the safe choice. Accuracy drops with music, background noise and rare languages. In the player, turn it on from the CC button.";
    if (section == VGSectionInterface)
        return @"iPad layout swaps the bottom tab bar for a list on the left side, with the page next to it, and only shows on iPad. Haptic feedback gives a small tap on the phone when you switch tabs, flip a switch, or a download finishes.";
    if (section == VGSectionAudio)
        return @"Crossfade: Gapless starts the next song the moment one ends. Seconds blend the end of one song into the start of the next. It only applies in the Library music player. With Find cover art online on, VidGrab looks up each new audio download (MP3, M4A, WAV, FLAC) on the internet and uses its album picture, and fills in a missing artist and album. If nothing matches, the picture from the video is kept. You can also search by hand: Library > hold an audio file > Edit audio info > Find cover art online. Only the song name and artist are sent for the search.";
    if (section == VGSectionBackup)
        return @"Back up saves your settings, theme, language, browser favorites and saved playlists to one file. Restore loads that file after reinstalling or on another phone. Your downloaded videos and audio, vault passcode and website sign-ins are never included, so they can't be restored from a backup.";
    if (section == VGSectionVault)
        return @"Choose a passcode, Face ID, or both. With both, either one opens the vault, so you're never locked out.";
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = VGTertiary;
}

- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = VGTertiary;
}

- (UITableViewCell *)cellWithTitle:(NSString *)title value:(NSString *)value icon:(NSString *)icon tint:(UIColor *)tint {
    // Plain cell labels (not a content configuration): iOS 27.2 beta throws "Unknown style" on the configuration route.
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    c.textLabel.text = VGT(title);
    c.textLabel.textColor = tint ?: VGText;
    c.textLabel.font = VGFont(16, UIFontWeightMedium);
    c.detailTextLabel.text = value ? VGT(value) : nil;
    c.detailTextLabel.textColor = VGSecondary;
    c.detailTextLabel.font = [UIFont systemFontOfSize:17];
    if (icon) {
        UIImage *img = [[UIImage systemImageNamed:icon] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        c.imageView.image = img;
        c.imageView.tintColor = tint ?: VGAccent;
    }
    c.backgroundColor = VGSurface;
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    ip = [NSIndexPath indexPathForRow:[self originalRow:ip] inSection:ip.section];   // rows may be shown in a different order
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
    if (ip.section == VGSectionDownloads) {
        if (ip.row == 0) {
            UITableViewCell *c = [self cellWithTitle:@"Default quality" value:[VGDownloadDefaults nameForQuality:VGDownloadDefaults.quality] icon:@"sparkles.tv" tint:nil];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        if (ip.row == 2) {
            UITableViewCell *c = [self cellWithTitle:@"Connections per download" value:[NSString stringWithFormat:@"%ld", (long)VGDownloadDefaults.threads] icon:@"point.3.connected.trianglepath.dotted" tint:nil];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        if (ip.row == 3) {
            UITableViewCell *c = [self cellWithTitle:@"Files only (no Photos)" value:nil icon:@"folder" tint:nil];
            UISwitch *sw = [UISwitch new];
            sw.on = VGDownloadDefaults.filesOnly;
            sw.onTintColor = VGAccent;
            [sw addTarget:self action:@selector(filesOnlyChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row == 6) {
            UITableViewCell *c = [self cellWithTitle:@"Auto-start shared links" value:nil icon:@"square.and.arrow.down" tint:nil];
            UISwitch *sw = [UISwitch new];
            sw.on = VGDownloadDefaults.autoStartShared;
            sw.onTintColor = VGAccent;
            [sw addTarget:self action:@selector(autoStartSharedChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row == 4 || ip.row == 5) {
            BOOL wifi = ip.row == 4;
            UITableViewCell *c = [self cellWithTitle:wifi ? @"Wi-Fi only" : @"Ask to delete finished videos" value:nil icon:wifi ? @"wifi" : @"trash" tint:nil];
            UISwitch *sw = [UISwitch new];
            sw.on = wifi ? VGDownloadDefaults.wifiOnly : VGDownloadDefaults.askDeleteWatched;
            sw.onTintColor = VGAccent;
            [sw addTarget:self action:wifi ? @selector(wifiOnlyChanged:) : @selector(askDeleteChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row == 1) {
            UITableViewCell *c = [self cellWithTitle:@"Default type" value:[VGDownloadDefaults kindName] icon:@"film" tint:nil];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
    }
    if (ip.section == VGSectionEngine) {
        if (ip.row == 0) {
            UITableViewCell *c = [self cellWithTitle:@"yt-dlp version" value:[VGEngine shared].engineVersion icon:@"shippingbox" tint:nil];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row == 2) {
            UITableViewCell *c = [self cellWithTitle:@"Find copied links" value:nil icon:@"doc.on.clipboard" tint:nil];
            UISwitch *sw = [UISwitch new];
            NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
            sw.on = [d objectForKey:@"vgClipboardCheck"] ? [d boolForKey:@"vgClipboardCheck"] : YES;
            sw.onTintColor = VGAccent;
            [sw addTarget:self action:@selector(clipboardChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row == 4) {
            UITableViewCell *c = [self cellWithTitle:@"Update engine automatically" value:nil icon:@"arrow.triangle.2.circlepath.circle" tint:nil];
            UISwitch *sw = [UISwitch new];
            sw.on = VGEngine.autoUpdateEnabled;
            sw.onTintColor = VGAccent;
            [sw addTarget:self action:@selector(autoEngineChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row == 3) {
            UITableViewCell *c = [self cellWithTitle:@"Keep downloading in background" value:nil icon:@"moon.zzz" tint:nil];
            UISwitch *sw = [UISwitch new];
            sw.on = VGKeepAlive.enabled;
            sw.onTintColor = VGAccent;
            [sw addTarget:self action:@selector(backgroundChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        return [self cellWithTitle:@"Update download engine" value:nil icon:@"arrow.triangle.2.circlepath" tint:VGAccent];
    }
    if (ip.section == VGSectionFloat) {
        // Bubble rows: jailbreak packages only. Sound rows: TrollStore or jailbreak. Otherwise greyed out.
        BOOL bubbleRow = ip.row == 0 || ip.row == 3;
        BOOL allowed = bubbleRow ? VGOverlay.bubbleAllowed : VGOverlay.fullInstall;
        BOOL install = ip.row == 3 && VGOverlay.canInstallHelper;
        if (install) allowed = YES;
        if (ip.row >= 2) {
            UITableViewCell *c = [self cellWithTitle:ip.row == 2 ? @"Test sound" : (install ? @"Install bubble helper" : @"Test bubble") value:nil
                                                icon:ip.row == 2 ? @"speaker.wave.3" : @"play.circle" tint:allowed ? VGAccent : VGTertiary];
            if (!allowed) c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        UITableViewCell *c = [self cellWithTitle:bubbleRow ? @"Bubble outside the app" : @"Sound when done" value:nil
                                            icon:bubbleRow ? @"circle.circle" : @"speaker.wave.2.fill" tint:allowed ? nil : VGTertiary];
        UISwitch *sw = [UISwitch new];
        sw.on = allowed && (bubbleRow ? VGOverlay.enabled : VGOverlay.finishSound);
        sw.enabled = allowed;
        sw.onTintColor = VGAccent;
        [sw addTarget:self action:bubbleRow ? @selector(overlayChanged:) : @selector(soundChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    if (ip.section == VGSectionGestures) {
        if (ip.row == 2) {
            UITableViewCell *c = [self cellWithTitle:@"Brightness side" value:VGPlayerGestures.brightnessOnRight ? @"Right" : @"Left" icon:@"arrow.left.arrow.right" tint:nil];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        if (ip.row == 5) {
            UITableViewCell *c = [self cellWithTitle:@"Clock and temperature" value:nil icon:@"clock" tint:nil];
            UISwitch *sw = [UISwitch new];
            sw.on = VGPlayerViewController.statusPillEnabled;
            sw.onTintColor = VGAccent;
            [sw addTarget:self action:@selector(statusPillChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row == 4) {
            UITableViewCell *c = [self cellWithTitle:@"Progress line" value:nil icon:@"minus" tint:nil];
            UISwitch *sw = [UISwitch new];
            sw.on = VGPlayerViewController.miniProgressEnabled;
            sw.onTintColor = VGAccent;
            [sw addTarget:self action:@selector(miniBarChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row == 3) {
            UITableViewCell *c = [self cellWithTitle:@"Seek distance" value:VGPlayerGestures.seekShortName icon:@"arrow.left.and.right" tint:nil];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        NSArray *titles = @[@"Brightness/Volume gesture", @"Swipe to seek"];
        NSArray *icons = @[@"sun.max.fill", @"forward.fill"];
        UITableViewCell *c = [self cellWithTitle:titles[ip.row] value:nil icon:icons[ip.row] tint:nil];
        UISwitch *sw = [UISwitch new];
        sw.tag = ip.row;
        sw.on = ip.row == 0 ? VGPlayerGestures.levelsEnabled : VGPlayerGestures.seekEnabled;
        sw.onTintColor = VGAccent;
        [sw addTarget:self action:@selector(gestureChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    if (ip.section == VGSectionAudio && ip.row == 1) {
        UITableViewCell *c = [self cellWithTitle:@"Crossfade" value:[VGMusicPlayer nameForCrossfade:VGMusicPlayer.crossfade] icon:@"waveform.path" tint:nil];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    if (ip.section == VGSectionLanguage) {
        NSString *ch = VGLocalize.choice;
        UITableViewCell *c = [self cellWithTitle:@"Language" value:[ch isEqualToString:@"auto"] ? VGT(@"Auto") : [VGLocalize nameForChoice:ch] icon:@"globe" tint:nil];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    if (ip.section == VGSectionInterface) {
        BOOL pad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
        if (ip.row == 0) {
            UITableViewCell *c = [self cellWithTitle:@"iPad layout" value:pad ? nil : @"iPad only" icon:@"sidebar.left" tint:pad ? nil : VGTertiary];
            UISwitch *sw = [UISwitch new];
            sw.on = VGSidebarController.layoutOn;
            sw.enabled = pad;
            sw.onTintColor = VGAccent;
            [sw addTarget:self action:@selector(padLayoutChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (NO) {
            NSString *ch = VGLocalize.choice;
            UITableViewCell *c = [self cellWithTitle:@"Language" value:[ch isEqualToString:@"auto"] ? VGT(@"Auto") : [VGLocalize nameForChoice:ch] icon:@"globe" tint:nil];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        UITableViewCell *c = [self cellWithTitle:@"Haptic feedback" value:nil icon:@"hand.tap" tint:nil];
        UISwitch *sw = [UISwitch new];
        sw.on = VGHaptics.enabled;
        sw.onTintColor = VGAccent;
        [sw addTarget:self action:@selector(hapticsChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    if (ip.section == VGSectionAudio && ip.row == 2) {
        UITableViewCell *c = [self cellWithTitle:@"Spinning CD cover" value:nil icon:@"opticaldisc" tint:nil];
        UISwitch *sw = [UISwitch new];
        sw.on = ![NSUserDefaults.standardUserDefaults objectForKey:@"vgCDEnabled"] || [NSUserDefaults.standardUserDefaults boolForKey:@"vgCDEnabled"];
        sw.onTintColor = VGAccent;
        [sw addTarget:self action:@selector(cdCoverChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    if (ip.section == VGSectionAudio) {
        UITableViewCell *c = [self cellWithTitle:@"Find cover art online" value:nil icon:@"photo.on.rectangle" tint:nil];
        UISwitch *sw = [UISwitch new];
        sw.on = VGCoverSearch.autoEnabled;
        sw.onTintColor = VGAccent;
        [sw addTarget:self action:@selector(autoCoverChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    if (ip.section == VGSectionSubtitles) {
        BOOL on = VGSubtitles.enabled;
        if (ip.row == 0) {
            UITableViewCell *c = [self cellWithTitle:@"Auto English subtitles" value:nil icon:@"captions.bubble" tint:nil];
            UISwitch *sw = [UISwitch new];
            sw.on = on;
            sw.onTintColor = VGAccent;
            [sw addTarget:self action:@selector(subtitlesChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row == 1) {
            UITableViewCell *c = [self cellWithTitle:@"Quality" value:[VGSubtitles nameFor:VGSubtitles.quality] icon:@"slider.horizontal.3" tint:on ? nil : VGTertiary];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            if (!on) c.selectionStyle = UITableViewCellSelectionStyleNone;
            return c;
        }
        if (ip.row >= 3) {
            NSArray *titles = @[@"Text size", @"Text color", @"Background"];
            NSArray *icons = @[@"textformat.size", @"paintpalette", @"rectangle.fill"];
            NSInteger idx = ip.row - 3;
            NSString *val = idx == 0 ? VGSubtitles.sizeNames[VGSubtitles.textSize] : idx == 1 ? VGSubtitles.colorNames[VGSubtitles.textColor] : VGSubtitles.backgroundNames[VGSubtitles.backgroundStyle];
            UITableViewCell *c = [self cellWithTitle:titles[idx] value:val icon:icons[idx] tint:nil];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        VGSubtitleQuality q = VGSubtitles.quality;
        NSString *state;
        if (VGSubtitles.downloading) state = [NSString stringWithFormat:@"Downloading %d%%", (int)round(VGSubtitles.downloadProgress * 100)];
        else if ([VGSubtitles modelReady:q]) state = [NSString stringWithFormat:@"Ready · %ld MB", (long)[VGSubtitles megabytesFor:q]];
        else if (VGSubtitles.lastError.length) state = @"Failed · tap to retry";
        else state = [NSString stringWithFormat:@"Not downloaded · %ld MB", (long)[VGSubtitles megabytesFor:q]];
        UITableViewCell *c = [self cellWithTitle:@"Speech model" value:state icon:@"arrow.down.circle" tint:on ? nil : VGTertiary];
        if (!on) c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    if (ip.section == VGSectionBackup) {
        UITableViewCell *c = [self cellWithTitle:ip.row == 0 ? @"Back up" : @"Restore" value:nil
                                            icon:ip.row == 0 ? @"square.and.arrow.up" : @"square.and.arrow.down" tint:nil];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    if (ip.section == VGSectionVault) {
        if (ip.row == 1) return [self cellWithTitle:@"Change passcode" value:nil icon:@"key" tint:nil];
        UITableViewCell *c = [self cellWithTitle:@"Lock with" value:[VGVaultLock methodDescription] icon:@"lock.fill" tint:nil];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    if (ip.row == 5) {
        UITableViewCell *c = [self cellWithTitle:@"Credits" value:@"yt-dlp, FFmpeg, Whisper and more" icon:@"heart.text.square" tint:nil];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    if (ip.row == 4) return [self cellWithTitle:@"Check for app updates" value:nil icon:@"arrow.down.app" tint:VGAccent];
    if (ip.row == 2 || ip.row == 3) {
        BOOL repo = ip.row == 2;
        NSString *url = repo ? @"https://iamjhe08.github.io/repo/" : @"https://iamjhe08.github.io/repo/vidgrab-source.json";
        UITableViewCell *c = [self cellWithTitle:repo ? @"Jailbreak repo" : @"Sideload source" value:url icon:repo ? @"shippingbox" : @"arrow.down.app" tint:nil];
        UIButton *cp = [UIButton buttonWithType:UIButtonTypeSystem];
        [cp setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
        cp.tintColor = VGSecondary;
        cp.frame = CGRectMake(0, 0, 40, 40);
        cp.accessibilityLabel = @"Copy";
        cp.tag = ip.row;
        [cp addTarget:self action:@selector(copySource:) forControlEvents:UIControlEventTouchUpInside];
        c.accessoryView = cp;
        return c;
    }
    if (ip.row == 1) {
        UITableViewCell *c = [self cellWithTitle:@"GitHub" value:@"@iamjhe08" icon:@"chevron.left.forwardslash.chevron.right" tint:nil];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    // Test builds carry a build number above 1 so you can tell which one is installed; releases show just the version.
    NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSString *shown = ([build integerValue] > 1) ? [NSString stringWithFormat:@"%@ (build %@)", version, build] : version;
    UITableViewCell *c = [self cellWithTitle:@"VidGrab" value:[NSString stringWithFormat:@"%@ · by T4MAG0", shown] icon:@"info.circle" tint:nil];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSInteger row = [self originalRow:ip];
    if (ip.section == VGSectionStorage && row == 1) [self clearCache];
    else if (ip.section == VGSectionEngine && row == 1) [self updateEngine];
    else if (ip.section == VGSectionDownloads && row == 0) [self chooseDefaultQuality:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionDownloads && row == 1) [self chooseDefaultKind:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionDownloads && row == 2) [self chooseThreads:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionLanguage && row == 0) [self chooseLanguage:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionFloat && row == 3 && VGOverlay.canInstallHelper) [VGOverlay installHelperFrom:self];
    else if (ip.section == VGSectionFloat && row == 3 && !VGOverlay.bubbleAllowed) return;   // greyed out
    else if (ip.section == VGSectionFloat && row == 2 && !VGOverlay.fullInstall) return;
    else if (ip.section == VGSectionFloat && row == 3) [self testBubble];
    else if (ip.section == VGSectionFloat && row == 2) [self testSound:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionGestures && row == 2) [self chooseBrightnessSide:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionGestures && row == 3) [self chooseSeekDistance:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionSubtitles && row == 1 && VGSubtitles.enabled) [self chooseSubtitleQuality:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionSubtitles && row == 2 && VGSubtitles.enabled) [self tapSpeechModel:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionSubtitles && row >= 3) [self chooseSubtitleStyle:row - 3 from:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionAudio && row == 1) [self chooseCrossfade:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionBackup && row == 0) [VGSettingsBackup exportFrom:self];
    else if (ip.section == VGSectionBackup && row == 1) [VGSettingsBackup importFrom:self completion:^{ [tv reloadData]; }];
    else if (ip.section == VGSectionVault && row == 0) [VGVaultLock changeLockFrom:self completion:^{ [tv reloadData]; }];
    else if (ip.section == VGSectionVault && row == 1) [VGVaultLock changePasscodeFrom:self completion:^{ [tv reloadData]; }];
    else if (ip.section == VGSectionAbout && row == 5) [self.navigationController pushViewController:[VGCreditsViewController new] animated:YES];
    else if (ip.section == VGSectionAbout && row == 4) [VGUpdater checkNowFrom:self];
    else if (ip.section == VGSectionAbout && (row == 2 || row == 3)) [self copyLinkForRow:row];
    else if (ip.section == VGSectionAbout && row == 1)
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/iamjhe08"] options:@{} completionHandler:nil];
}

#pragma mark Actions

- (void)cdCoverChanged:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"vgCDEnabled"];
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)copyLinkForRow:(NSInteger)row {
    UIPasteboard.generalPasteboard.string = row == 2 ? @"https://iamjhe08.github.io/repo/" : @"https://iamjhe08.github.io/repo/vidgrab-source.json";
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:VGSectionAbout]];
    UIButton *b = [cell.accessoryView isKindOfClass:UIButton.class] ? (UIButton *)cell.accessoryView : nil;
    if (!b) return;
    [b setImage:[UIImage systemImageNamed:@"checkmark"] forState:UIControlStateNormal];
    b.tintColor = VGOn;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [b setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
        b.tintColor = VGSecondary;
    });
}

- (void)copySource:(UIButton *)b { [self copyLinkForRow:b.tag]; }

- (void)clipboardChanged:(UISwitch *)sw {
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:@"vgClipboardCheck"];
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)testBubble {
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"Starting the bubble…" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:wait animated:YES completion:nil];
    [VGOverlay testWithCompletion:^(BOOL ok, NSString *details) {
        [wait dismissViewControllerAnimated:YES completion:^{
            NSString *title = ok ? @"Bubble is running" : ([details hasPrefix:@"This copy"] ? @"Not available on this install" : @"Bubble couldn't start");
            NSString *msg = ok ? [NSString stringWithFormat:@"Swipe home now. A sample bubble should float over your Home Screen for 20 seconds.\n\n%@", details]
                               : ([details hasPrefix:@"This copy"] ? details : [NSString stringWithFormat:@"Please send a screenshot of this.\n\n%@", details]);
            UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"Copy details" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { UIPasteboard.generalPasteboard.string = details; }]];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }];
    }];
}

- (void)soundChanged:(UISwitch *)sw {
    VGOverlay.finishSound = sw.on;
    [[UISelectionFeedbackGenerator new] selectionChanged];
    if (sw.on) [VGKeepAlive playFinishSound];   // let you hear it
}

- (void)testSound:(UIView *)from {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Test sound"
        message:@"You'll hear the sound twice: first like a notification (ringer volume), then like music (media volume)." preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Play now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self runSoundTest:NO]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Play after I leave the app" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self runSoundTest:YES]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = from;
    a.popoverPresentationController.sourceRect = from.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)runSoundTest:(BOOL)later {
    if (later) [VGActions alert:@"Swipe home now" message:@"The sound plays 5 seconds after you tap OK. Come back to VidGrab afterwards to see the results." from:self];
    __weak typeof(self) ws = self;
    [VGKeepAlive testSoundLater:later completion:^(NSString *report) {
        void (^show)(void) = ^{
            UIViewController *host = ws.presentedViewController ? ws.presentedViewController : ws;
            UIAlertController *r = [UIAlertController alertControllerWithTitle:@"Sound test results"
                message:[NSString stringWithFormat:@"Which ones did you hear? Copy this and send it.\n\n%@", report] preferredStyle:UIAlertControllerStyleAlert];
            [r addAction:[UIAlertAction actionWithTitle:@"Copy details" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { UIPasteboard.generalPasteboard.string = report; }]];
            [r addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [host presentViewController:r animated:YES completion:nil];
        };
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) show();
        else {
            __block id tok = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
                                                                      usingBlock:^(NSNotification *n) { [NSNotificationCenter.defaultCenter removeObserver:tok]; show(); }];
        }
    }];
}

#pragma mark Auto subtitles

- (void)reloadSubtitleSection {
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:VGSectionSubtitles] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)subtitleModelChanged {
    [self reloadSubtitleSection];
    NSString *err = VGSubtitles.lastError;
    if (!VGSubtitles.downloading && err.length && ![err isEqualToString:self.shownSubtitleError]) {
        self.shownSubtitleError = err;
        [VGActions alert:@"Couldn't download the speech model" message:err from:self.presentedViewController ?: self];
    }
}

- (void)autoCoverChanged:(UISwitch *)sw { VGCoverSearch.autoEnabled = sw.on; }

- (void)subtitlesChanged:(UISwitch *)sw {
    [[UISelectionFeedbackGenerator new] selectionChanged];
    VGSubtitles.enabled = sw.on;
    if (!sw.on) VGSubtitles.startOn = NO;
    if (sw.on && !VGSubtitles.currentModelReady && !VGSubtitles.downloading) [self askDownload:VGSubtitles.quality turnOffIfCancelled:YES];
    else [self reloadSubtitleSection];
}

- (void)askDownload:(VGSubtitleQuality)q turnOffIfCancelled:(BOOL)off {
    NSString *msg = [NSString stringWithFormat:@"This downloads the %@ speech model once, about %ld MB. Subtitles are then made on your phone, so nothing is uploaded. Keep VidGrab open while it downloads.",
                     [VGSubtitles nameFor:q], (long)[VGSubtitles megabytesFor:q]];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Download speech model?" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        self.shownSubtitleError = nil;
        [VGSubtitles downloadModel:q];
        [self reloadSubtitleSection];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
        if (off) VGSubtitles.enabled = NO;
        [self reloadSubtitleSection];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)chooseSubtitleQuality:(UIView *)from {
    NSMutableString *msg = [NSMutableString string];
    for (VGSubtitleQuality q = VGSubtitleFast; q <= VGSubtitleBest; q++)
        [msg appendFormat:@"%@: %@\n", [VGSubtitles nameFor:q], [VGSubtitles detailFor:q]];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Quality" message:[msg stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet] preferredStyle:UIAlertControllerStyleActionSheet];
    for (VGSubtitleQuality q = VGSubtitleFast; q <= VGSubtitleBest; q++) {
        NSString *name = [NSString stringWithFormat:@"%@ · %ld MB", [VGSubtitles nameFor:q], (long)[VGSubtitles megabytesFor:q]];
        if (q == VGSubtitles.quality) name = [name stringByAppendingString:@" \u2713"];
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            VGSubtitles.quality = q;
            [self reloadSubtitleSection];
            if (VGSubtitles.enabled && ![VGSubtitles modelReady:q] && !VGSubtitles.downloading) [self askDownload:q turnOffIfCancelled:NO];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = from;
    a.popoverPresentationController.sourceRect = from.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)tapSpeechModel:(UIView *)from {
    VGSubtitleQuality q = VGSubtitles.quality;
    if (VGSubtitles.downloading) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Downloading speech model" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [a addAction:[UIAlertAction actionWithTitle:@"Stop download" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [VGSubtitles cancelDownload]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Keep going" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = from;
        a.popoverPresentationController.sourceRect = from.bounds;
        [self presentViewController:a animated:YES completion:nil];
    } else if ([VGSubtitles modelReady:q]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Speech model" message:@"Delete it to free up space. You can download it again any time." preferredStyle:UIAlertControllerStyleActionSheet];
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Delete (%ld MB)", (long)[VGSubtitles megabytesFor:q]] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [VGSubtitles deleteModel:q]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = from;
        a.popoverPresentationController.sourceRect = from.bounds;
        [self presentViewController:a animated:YES completion:nil];
    } else {
        [self askDownload:q turnOffIfCancelled:NO];
    }
}

- (void)autoEngineChanged:(UISwitch *)sw {
    VGEngine.autoUpdateEnabled = sw.on;
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)statusPillChanged:(UISwitch *)sw {
    VGPlayerViewController.statusPillEnabled = sw.on;
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)miniBarChanged:(UISwitch *)sw {
    VGPlayerViewController.miniProgressEnabled = sw.on;
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)gestureChanged:(UISwitch *)sw {
    if (sw.tag == 0) VGPlayerGestures.levelsEnabled = sw.on;
    else VGPlayerGestures.seekEnabled = sw.on;
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)chooseBrightnessSide:(UIView *)from {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Brightness side"
        message:@"Brightness goes on this side of the screen. Volume takes the other side." preferredStyle:UIAlertControllerStyleActionSheet];
    BOOL right = VGPlayerGestures.brightnessOnRight;
    for (NSNumber *n in @[@NO, @YES]) {
        BOOL r = n.boolValue;
        NSString *name = r ? @"Right (volume on the left)" : @"Left (volume on the right)";
        if (r == right) name = [name stringByAppendingString:@" \u2713"];
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            VGPlayerGestures.brightnessOnRight = r;
            [self.tableView reloadRowsAtIndexPaths:@[[self shownPathForOriginalRow:2 section:VGSectionGestures]] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = from;
    a.popoverPresentationController.sourceRect = from.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)chooseDefaultQuality:(UIView *)from {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Default quality"
        message:@"Pick a quality and the Download card shows just a Start button, using the closest lower quality if a video lacks it. Always ask shows every quality." preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *n in VGDownloadDefaults.qualityChoices) {
        NSInteger q = n.integerValue;
        NSString *name = [VGDownloadDefaults nameForQuality:q];
        if (q == VGDownloadDefaults.quality) name = [name stringByAppendingString:@" \u2713"];
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            VGDownloadDefaults.quality = q;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:VGSectionDownloads] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = from;
    a.popoverPresentationController.sourceRect = from.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)filesOnlyChanged:(UISwitch *)sw { VGDownloadDefaults.filesOnly = sw.on; }

- (void)wifiOnlyChanged:(UISwitch *)sw {
    VGDownloadDefaults.wifiOnly = sw.on;
    [[VGEngine shared] pump];   // turning it off lets waiting downloads start right away
}
- (void)autoStartSharedChanged:(UISwitch *)sw { VGDownloadDefaults.autoStartShared = sw.on; }
- (void)askDeleteChanged:(UISwitch *)sw { VGDownloadDefaults.askDeleteWatched = sw.on; }
- (void)hapticsChanged:(UISwitch *)sw { VGHaptics.enabled = sw.on; if (sw.on) [VGHaptics select]; }
- (void)padLayoutChanged:(UISwitch *)sw {
    VGSidebarController.layoutOn = sw.on;   // the whole screen changes at once
    [NSNotificationCenter.defaultCenter postNotificationName:VGLayoutDidChangeNotification object:nil];
}

/// A list of choices in an action sheet; `done` gets the position that was picked.
- (void)pickFrom:(UIView *)from title:(NSString *)title names:(NSArray<NSString *> *)names selected:(NSInteger)sel done:(void (^)(NSInteger))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < (NSInteger)names.count; i++) {
        NSString *n = i == sel ? [names[i] stringByAppendingString:@"  \u2713"] : names[i];
        [a addAction:[UIAlertAction actionWithTitle:n style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { done(i); [self.tableView reloadData]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = from;
    a.popoverPresentationController.sourceRect = from.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)chooseSubtitleStyle:(NSInteger)which from:(UIView *)from {
    if (which == 0) [self pickFrom:from title:@"Text size" names:VGSubtitles.sizeNames selected:VGSubtitles.textSize done:^(NSInteger i) { VGSubtitles.textSize = i; }];
    else if (which == 1) [self pickFrom:from title:@"Text color" names:VGSubtitles.colorNames selected:VGSubtitles.textColor done:^(NSInteger i) { VGSubtitles.textColor = i; }];
    else [self pickFrom:from title:@"Background" names:VGSubtitles.backgroundNames selected:VGSubtitles.backgroundStyle done:^(NSInteger i) { VGSubtitles.backgroundStyle = i; }];
}

- (void)chooseCrossfade:(UIView *)from {
    NSArray<NSNumber *> *vals = VGMusicPlayer.crossfadeChoices;
    NSMutableArray *names = [NSMutableArray array];
    for (NSNumber *v in vals) [names addObject:[VGMusicPlayer nameForCrossfade:v.integerValue]];
    NSInteger sel = [vals indexOfObject:@(VGMusicPlayer.crossfade)];
    [self pickFrom:from title:@"Crossfade" names:names selected:sel == NSNotFound ? 0 : sel done:^(NSInteger i) { VGMusicPlayer.crossfade = vals[i].integerValue; }];
}

- (void)chooseLanguage:(UIView *)from {
    [VGLocalize presentPickerFrom:self source:from done:^{ [self.tableView reloadData]; }];
}

- (void)chooseThreads:(UIView *)from {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Connections per download"
        message:@"How many pieces are fetched at the same time. More can be faster for downloads that arrive in many small parts. Some sites block downloads if it is too high. Try 1 or 2 if a site gives errors." preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *n in VGDownloadDefaults.threadChoices) {
        NSInteger v = n.integerValue;
        NSString *name = v == 8 ? @"8 (default)" : [NSString stringWithFormat:@"%ld", (long)v];
        if (v == VGDownloadDefaults.threads) name = [name stringByAppendingString:@" \u2713"];
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            VGDownloadDefaults.threads = v;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:VGSectionDownloads] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = from;
    a.popoverPresentationController.sourceRect = from.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)chooseDefaultKind:(UIView *)from {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Default type" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *names = @[@"Always ask", @"Video", @"Audio only"];
    for (NSInteger i = 0; i < 3; i++) {
        NSInteger val = i - 1;
        NSString *name = val == VGDownloadDefaults.kind ? [names[i] stringByAppendingString:@" \u2713"] : names[i];
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            VGDownloadDefaults.kind = val;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:VGSectionDownloads] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = from;
    a.popoverPresentationController.sourceRect = from.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)chooseSeekDistance:(UIView *)from {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Seek distance"
        message:@"How far one swipe across the whole screen jumps in the video." preferredStyle:UIAlertControllerStyleActionSheet];
    NSInteger current = VGPlayerGestures.seekChoiceIndex;
    for (NSInteger i = 0; i < (NSInteger)VGPlayerGestures.seekChoices.count; i++) {
        NSString *name = [VGPlayerGestures seekChoiceName:i];
        if (i == current) name = [name stringByAppendingString:@" \u2713"];
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            VGPlayerGestures.seekChoiceIndex = i;
            [self.tableView reloadRowsAtIndexPaths:@[[self shownPathForOriginalRow:3 section:VGSectionGestures]] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = from;
    a.popoverPresentationController.sourceRect = from.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)overlayChanged:(UISwitch *)sw {
    VGOverlay.enabled = sw.on;
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)backgroundChanged:(UISwitch *)sw {
    VGKeepAlive.enabled = sw.on;
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

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
