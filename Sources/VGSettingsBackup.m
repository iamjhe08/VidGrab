#import "VGSettingsBackup.h"
#import "VGActions.h"
#import "VGBlocker.h"
#import "VGPlaylistStore.h"
#import "VGLocalize.h"
#import "VGTheme.h"
#import "VGCustomTheme.h"
#import "VGMusic.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// What goes in the file. Never included: the vault lock and passcode, downloads,
// website sign-ins, playback positions, or anything only meant for this phone.
static NSDictionary<NSString *, NSString *> *Known(void) {
    return @{
        @"vgClipboardCheck":   @"Find copied links",
        @"vgDefQuality":       @"Default download quality",
        @"vgDefKind":          @"Default download type",
        @"vgKeepDownloading":  @"Keep downloading in background",
        @"vgAutoClearCache":   @"Auto-clear cache on launch",
        @"vgAdblock":          @"Ad blocker",
        @"vgAdblockAllow":     @"Ad blocker allowed sites",
        @"vgSkipYTAds":        @"Skip YouTube ads",
        @"vgFavorites":        @"Browser favorites",
        @"vgOverlayBubble":    @"Bubble outside the app",
        @"vgFinishSound":      @"Sound when done",
        @"vgThreads":          @"Connections per download",
        @"vgFilesOnly":        @"Files only",
        @"vgTheme":            @"Theme",
        @"vgCustomThemes":     @"Custom themes",
        @"vgActiveCustomTheme": @"Custom themes",
        @"vgLanguage":         @"Language",
        @"vgStatusPill":       @"Clock and temperature in the player",
        @"vgCDEnabled":        @"Spinning CD cover",
        @"vgCDShape":          @"Spinning CD cover",
        @"vgEngineAuto":       @"Automatic engine updates",
        @"vgMusicShuffle":     @"Shuffle",
        @"vgMusicRepeat":      @"Repeat",
        @"vgWifiOnly":         @"Wi-Fi only downloads",
        @"vgAskDeleteWatched": @"Ask to delete finished videos",
        @"vgAutoStartShared":   @"Auto-start shared links",
        @"vgCrossfade":        @"Crossfade",
        @"vgSubSize":          @"Subtitle text size",
        @"vgSubColor":         @"Subtitle text color",
        @"vgSubBack":          @"Subtitle background",
        @"vgHaptics":          @"Haptic feedback",
        @"vgIPadLayout":       @"iPad layout",
        @"vgBubbleSide":       @"Bubble position",
        @"vgBubbleY":          @"Bubble position",
        @"vgGestureLevels":     @"Player brightness and volume swipe",
        @"vgGestureSeek":       @"Player seek swipe",
        @"vgPlayerMiniBar":     @"Player progress line",
        @"vgSubsEnabled":       @"Auto English subtitles",
        @"vgSubsQuality":       @"Subtitle quality",
        @"vgPlayerAspect":      @"Player screen size",
        @"vgGestureBrightnessRight": @"Player brightness side",
        @"vgGestureSeekSpan":   @"Player seek distance",
    };
}

@interface VGBackupPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, copy) void (^done)(void);
@property (nonatomic, strong) NSURL *tempFile;
@end

static VGBackupPicker *gPicker;   // kept alive while the picker is open

@implementation VGSettingsBackup

+ (void)exportFrom:(UIViewController *)vc {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *k in Known()) {
        id v = [d objectForKey:k];
        if (v && [NSJSONSerialization isValidJSONObject:@[v]]) settings[k] = v;
    }
    NSISO8601DateFormatter *f = [NSISO8601DateFormatter new];
    NSMutableDictionary *file = [@{@"app": @"VidGrab",
                           @"kind": @"backup",
                           @"format": @2,
                           @"version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
                           @"exported": [f stringFromDate:NSDate.date],
                           @"settings": settings,
                           @"playlists": [VGPlaylistStore exportDicts]} mutableCopy];
    file[@"customThemes"] = [VGThemeStore backupPayload];   // every custom theme, with its photo
    NSData *data = [NSJSONSerialization dataWithJSONObject:file options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"yyyy-MM-dd";
    NSString *name = [NSString stringWithFormat:@"VidGrab Backup %@.json", [df stringFromDate:NSDate.date]];
    NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    if (![data writeToURL:tmp atomically:YES]) { [VGActions alert:@"Couldn't save the backup file" message:nil from:vc]; return; }

    gPicker = [VGBackupPicker new];
    gPicker.host = vc;
    gPicker.tempFile = tmp;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[tmp] asCopy:YES];
    p.delegate = gPicker;
    [vc presentViewController:p animated:YES completion:nil];
}

+ (void)importFrom:(UIViewController *)vc completion:(void (^)(void))done {
    gPicker = [VGBackupPicker new];
    gPicker.host = vc;
    gPicker.done = done;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON, UTTypePlainText, UTTypeData] asCopy:YES];
    p.delegate = gPicker;
    p.allowsMultipleSelection = NO;
    [vc presentViewController:p animated:YES completion:nil];
}

+ (void)apply:(NSURL *)url from:(UIViewController *)vc done:(void (^)(void))done {
    NSData *data = [NSData dataWithContentsOfURL:url];
    NSDictionary *file = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *settings = [file isKindOfClass:NSDictionary.class] ? file[@"settings"] : nil;
    if (![file[@"app"] isEqual:@"VidGrab"] || ![settings isKindOfClass:NSDictionary.class]) {
        [VGActions alert:@"That's not a VidGrab backup file" message:@"Pick a file made with Settings > Back up." from:vc];
        return;
    }
    NSDictionary *known = Known();
    NSUInteger settingCount = 0;
    for (NSString *k in settings) if (known[k]) settingCount++;
    NSArray *lists = [file[@"playlists"] isKindOfClass:NSArray.class] ? file[@"playlists"] : @[];
    NSUInteger newLists = 0;
    for (NSDictionary *p in lists) if ([p isKindOfClass:NSDictionary.class] && [p[@"url"] isKindOfClass:NSString.class] && ![VGPlaylistStore forURL:p[@"url"]]) newLists++;
    NSDictionary *themePayload = [file[@"customThemes"] isKindOfClass:NSDictionary.class] ? file[@"customThemes"] : nil;
    NSUInteger themeCount = [themePayload[@"themes"] isKindOfClass:NSArray.class] ? [themePayload[@"themes"] count] : 0;
    NSMutableString *msg = [NSMutableString stringWithFormat:@"This backup has %lu settings and %lu saved playlists", (unsigned long)settingCount, (unsigned long)lists.count];
    if (themeCount) [msg appendFormat:@", and %lu custom themes", (unsigned long)themeCount];
    [msg appendFormat:@".\n\nYour settings will be replaced by the ones in the file. Playlists you already have stay as they are, and %lu new ones are added. Downloaded videos and audio are not part of a backup.", (unsigned long)newLists];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Restore this backup?" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        for (NSString *k in settings) {
            if (!known[k]) continue;   // ignore anything VidGrab doesn't know
            id v = settings[k];
            if (![v isKindOfClass:NSNumber.class] && ![v isKindOfClass:NSString.class] && ![v isKindOfClass:NSArray.class] && ![v isKindOfClass:NSDictionary.class]) continue;
            [d setObject:v forKey:k];
        }
        if (themePayload) [VGThemeStore restoreFromPayload:themePayload];
        else [VGThemeStore reload];
        [VGPlaylistStore importDicts:lists];
        if (settings[@"vgAdblock"]) [VGBlocker shared].enabled = [settings[@"vgAdblock"] boolValue];
        [VGLocalize setChoice:[VGLocalize choice]];   // load the restored language
        VGResetCustomThemeCache();
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [NSNotificationCenter.defaultCenter postNotificationName:VGThemeDidChangeNotification object:nil];   // pages rebuild with the restored theme and language
        [VGActions alert:@"Backup restored" message:@"Your settings and saved playlists are back. If something doesn't look updated, close VidGrab and open it again." from:vc];
        if (done) done();
    }]];
    [vc presentViewController:a animated:YES completion:nil];
}

@end

@implementation VGBackupPicker

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.tempFile) {
        [NSFileManager.defaultManager removeItemAtURL:self.tempFile error:nil];
        if (self.host) [VGActions toast:@"Backup saved" icon:@"checkmark.circle.fill" in:self.host.view.window ?: self.host.view];
    } else if (urls.firstObject) {
        NSURL *u = urls.firstObject;
        BOOL scoped = [u startAccessingSecurityScopedResource];
        [VGSettingsBackup apply:u from:self.host done:self.done];
        if (scoped) [u stopAccessingSecurityScopedResource];
    }
    gPicker = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)c {
    if (self.tempFile) [NSFileManager.defaultManager removeItemAtURL:self.tempFile error:nil];
    gPicker = nil;
}

@end
