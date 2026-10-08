#import "VGSettingsBackup.h"
#import "VGActions.h"
#import "VGBlocker.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// What goes in the file. Never included: the vault lock and passcode, downloads,
// website sign-ins, playback positions, or anything only meant for this phone.
static NSDictionary<NSString *, NSString *> *Known(void) {
    return @{
        @"vgClipboardCheck":   @"Find copied links",
        @"vgKeepDownloading":  @"Keep downloading in background",
        @"vgAutoClearCache":   @"Auto-clear cache on launch",
        @"vgAdblock":          @"Ad blocker",
        @"vgAdblockAllow":     @"Ad blocker allowed sites",
        @"vgSkipYTAds":        @"Skip YouTube ads",
        @"vgFavorites":        @"Browser favorites",
        @"vgOverlayBubble":    @"Bubble outside the app",
        @"vgFinishSound":      @"Sound when done",
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
    NSDictionary *file = @{@"app": @"VidGrab",
                           @"kind": @"settings",
                           @"format": @1,
                           @"version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
                           @"exported": [f stringFromDate:NSDate.date],
                           @"settings": settings};
    NSData *data = [NSJSONSerialization dataWithJSONObject:file options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"yyyy-MM-dd";
    NSString *name = [NSString stringWithFormat:@"VidGrab Settings %@.json", [df stringFromDate:NSDate.date]];
    NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    if (![data writeToURL:tmp atomically:YES]) { [VGActions alert:@"Couldn't save the settings file" message:nil from:vc]; return; }

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
        [VGActions alert:@"That's not a VidGrab settings file" message:@"Pick a file made with Settings > Export settings." from:vc];
        return;
    }
    NSDictionary *known = Known();
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (NSString *k in settings) {
        if (!known[k]) continue;   // ignore anything VidGrab doesn't know
        id v = settings[k];
        if (![v isKindOfClass:NSNumber.class] && ![v isKindOfClass:NSString.class] && ![v isKindOfClass:NSArray.class] && ![v isKindOfClass:NSDictionary.class]) continue;
        [d setObject:v forKey:k];
        [names addObject:known[k]];
    }
    if (settings[@"vgAdblock"]) [VGBlocker shared].enabled = [settings[@"vgAdblock"] boolValue];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    NSString *list = names.count ? [names.array componentsJoinedByString:@", "] : @"nothing (the file was empty)";
    [VGActions alert:@"Settings imported" message:[NSString stringWithFormat:@"Loaded: %@.\n\nIf something doesn't look updated, close VidGrab and open it again.", list] from:vc];
    if (done) done();
}

@end

@implementation VGBackupPicker

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.tempFile) {
        [NSFileManager.defaultManager removeItemAtURL:self.tempFile error:nil];
        if (self.host) [VGActions toast:@"Settings exported" icon:@"checkmark.circle.fill" in:self.host.view.window ?: self.host.view];
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
