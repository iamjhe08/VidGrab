#import "VGSettingsViewController.h"
#import "VGTheme.h"
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
#import <AVFoundation/AVFoundation.h>

// The order the sections are shown in: downloading, playing, privacy, then housekeeping, and About last.
typedef NS_ENUM(NSInteger, VGSection) { VGSectionEngine, VGSectionFloat, VGSectionGestures, VGSectionSubtitles, VGSectionAudio, VGSectionVault, VGSectionStorage, VGSectionBackup, VGSectionAbout, VGSectionCount };

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

#pragma mark Table

// The order rows are shown in. Each number is the row's original position, so the row code itself doesn't change.
- (NSArray<NSNumber *> *)rowOrderForSection:(NSInteger)section {
    switch (section) {
        case VGSectionEngine:   return @[@2, @3, @0, @1];       // the two everyday switches first; engine version and update last
        case VGSectionFloat:    return @[@0, @3, @1, @2];       // each switch followed by its own test
        case VGSectionGestures: return @[@0, @2, @1, @3, @4];   // each gesture followed by its own option
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
        case VGSectionEngine: return 4;
        case VGSectionFloat: return 4;
        case VGSectionGestures: return 5;
        case VGSectionSubtitles: return 3;
        case VGSectionAudio: return 1;
        case VGSectionBackup: return 2;
        case VGSectionVault: return [VGVaultLock usesPasscode] ? 2 : 1;
        default: return 4;   // About: version, GitHub, check for updates, credits
    }
}

- (NSString *)sectionTitle:(NSInteger)section {
    return @[@"Download engine", @"Floating progress", @"Video player", @"Auto subtitles", @"Audio", @"Private Vault 2.0", @"Storage", @"Backup", @"About"][section];
}

// A small exclamation button in front of the section title; it opens and closes the section's note.
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    UIView *v = [UIView new];
    UILabel *l = [UILabel new];
    l.text = [self sectionTitle:section].uppercaseString;
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
    if (section == VGSectionEngine)
        return @"With Find copied links on, a video link you copied shows up on Home as soon as you open VidGrab. With Keep downloading in background on, downloads carry on when you leave the app and you get a notification when they finish. If downloads from a site stop working, update the engine: sites change often and fixes arrive here first.";
    if (section == VGSectionFloat) {
        NSString *bubble = @"With Bubble outside the app on, the download bubble stays on screen when you leave VidGrab or use other apps. It fades after 3 seconds so it won't get in the way; touch it to bring it back. Drag it anywhere, tap it to return to your downloads.";
        NSString *sound = @"Sound when done plays VidGrab's own sound when your downloads finish while you're outside the app. It never plays inside VidGrab.";
        if (VGOverlay.bubbleAllowed) return [NSString stringWithFormat:@"%@\n\n%@", bubble, sound];
        return @"Floating progress works when VidGrab is installed as a jailbreak package, or with the TrollStore .tipa file. On TrollStore, tap Install bubble helper once and choose TrollStore. The bubble inside VidGrab, background downloads and the finish notification still work here.";
    }
    if (section == VGSectionGestures)
        return @"In the video player, swipe up or down on one half of the screen to change brightness and on the other half to change volume. Brightness/Volume gesture turns both on or off and Brightness side picks which half does what; they work when the phone is sideways. Swipe to seek jumps forward or back as you swipe sideways, in either direction of the phone, and the video follows your finger frame by frame. Seek distance is how far one swipe across the whole screen jumps. Progress line shows a thin bar along the bottom edge while the buttons are hidden. Brightness goes back to normal when you close the player. Swipes that start on the player's own buttons still work as usual.";
    if (section == VGSectionSubtitles)
        return @"Auto subtitles listen to the video on your phone and write what is said in English, whatever the language. Nothing is uploaded and no account is needed. The speech model downloads once, only when you turn this on. It uses extra battery and warms the phone while it works, and older phones can fall behind the video, so Fast is the safe choice. Accuracy drops with music, background noise and rare languages. In the player, turn it on from the CC button.";
    if (section == VGSectionAudio)
        return @"With Find cover art online on, VidGrab looks up each new audio download (MP3, M4A, WAV, FLAC) on the internet and uses its album picture, and fills in a missing artist and album. If nothing matches, the picture from the video is kept. You can also search by hand: Library > hold an audio file > Edit audio info > Find cover art online. Only the song name and artist are sent for the search.";
    if (section == VGSectionBackup)
        return @"Save your settings to a file, then load it after reinstalling or on another phone. It includes your switches, ad blocker sites and browser favorites. Your downloads, vault passcode and website sign-ins are never included.";
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
        UITableViewCell *c = [self cellWithTitle:ip.row == 0 ? @"Export settings" : @"Import settings" value:nil
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
    if (ip.row == 3) {
        UITableViewCell *c = [self cellWithTitle:@"Credits" value:@"yt-dlp, FFmpeg, Whisper and more" icon:@"heart.text.square" tint:nil];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    if (ip.row == 2) return [self cellWithTitle:@"Check for app updates" value:nil icon:@"arrow.down.app" tint:VGAccent];
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
    else if (ip.section == VGSectionFloat && row == 3 && VGOverlay.canInstallHelper) [VGOverlay installHelperFrom:self];
    else if (ip.section == VGSectionFloat && row == 3 && !VGOverlay.bubbleAllowed) return;   // greyed out
    else if (ip.section == VGSectionFloat && row == 2 && !VGOverlay.fullInstall) return;
    else if (ip.section == VGSectionFloat && row == 3) [self testBubble];
    else if (ip.section == VGSectionFloat && row == 2) [self testSound:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionGestures && row == 2) [self chooseBrightnessSide:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionGestures && row == 3) [self chooseSeekDistance:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionSubtitles && row == 1 && VGSubtitles.enabled) [self chooseSubtitleQuality:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionSubtitles && row == 2 && VGSubtitles.enabled) [self tapSpeechModel:[tv cellForRowAtIndexPath:ip]];
    else if (ip.section == VGSectionBackup && row == 0) [VGSettingsBackup exportFrom:self];
    else if (ip.section == VGSectionBackup && row == 1) [VGSettingsBackup importFrom:self completion:^{ [tv reloadData]; }];
    else if (ip.section == VGSectionVault && row == 0) [VGVaultLock changeLockFrom:self completion:^{ [tv reloadData]; }];
    else if (ip.section == VGSectionVault && row == 1) [VGVaultLock changePasscodeFrom:self completion:^{ [tv reloadData]; }];
    else if (ip.section == VGSectionAbout && row == 3) [self.navigationController pushViewController:[VGCreditsViewController new] animated:YES];
    else if (ip.section == VGSectionAbout && row == 2) [VGUpdater checkNowFrom:self];
    else if (ip.section == VGSectionAbout && row == 1)
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/iamjhe08"] options:@{} completionHandler:nil];
}

#pragma mark Actions

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
