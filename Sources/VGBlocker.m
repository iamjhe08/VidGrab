#import "VGBlocker.h"
#import "VGCrash.h"
#import <objc/runtime.h>

NSString *const VGBlockerDidChangeNotification = @"VGBlockerDidChangeNotification";

@interface VGBlocker ()
@property (nonatomic, readwrite) BOOL ready;
@property (nonatomic, readwrite) NSUInteger ruleCount;
@property (nonatomic, strong) NSMutableArray<WKContentRuleList *> *lists;
@property (nonatomic) BOOL preparing;
@property (nonatomic, copy) NSArray<NSString *> *files;
@property (nonatomic, copy) NSArray<NSString *> *identifiers;
@property (nonatomic, copy) NSString *rulesDir;
@end

@implementation VGBlocker

+ (instancetype)shared {
    static VGBlocker *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        b = [VGBlocker new];
        [NSUserDefaults.standardUserDefaults registerDefaults:@{@"vgAdblock": @YES, @"vgSkipYTAds": @YES}];
    });
    return b;
}

- (BOOL)enabled { return [NSUserDefaults.standardUserDefaults boolForKey:@"vgAdblock"]; }
- (void)setEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"vgAdblock"];
    [NSNotificationCenter.defaultCenter postNotificationName:VGBlockerDidChangeNotification object:nil];
}

- (BOOL)skipYouTubeAds { return [NSUserDefaults.standardUserDefaults boolForKey:@"vgSkipYTAds"]; }
- (void)setSkipYouTubeAds:(BOOL)skip {
    [NSUserDefaults.standardUserDefaults setBool:skip forKey:@"vgSkipYTAds"];
    [NSNotificationCenter.defaultCenter postNotificationName:VGBlockerDidChangeNotification object:nil];
}

static NSString *siteKey(NSString *host) {
    NSString *h = host.lowercaseString;
    for (NSString *p in @[@"www.", @"m.", @"mobile."]) if ([h hasPrefix:p]) h = [h substringFromIndex:p.length];
    return h;
}

- (BOOL)isAllowedSite:(NSString *)host {
    if (!host.length) return NO;
    NSArray *allow = [NSUserDefaults.standardUserDefaults stringArrayForKey:@"vgAdblockAllow"] ?: @[];
    NSString *k = siteKey(host);
    for (NSString *a in allow) if ([k isEqualToString:a] || [k hasSuffix:[@"." stringByAppendingString:a]]) return YES;
    return NO;
}

- (void)setAllowed:(BOOL)allowed forSite:(NSString *)host {
    if (!host.length) return;
    NSMutableArray *allow = [[NSUserDefaults.standardUserDefaults stringArrayForKey:@"vgAdblockAllow"] ?: @[] mutableCopy];
    NSString *k = siteKey(host);
    [allow removeObject:k];
    if (allowed) [allow addObject:k];
    [NSUserDefaults.standardUserDefaults setObject:allow forKey:@"vgAdblockAllow"];
    [NSNotificationCenter.defaultCenter postNotificationName:VGBlockerDidChangeNotification object:nil];
}

#pragma mark Rules

- (void)prepare {
    if (self.preparing || self.ready) return;
    self.preparing = YES;
    self.lists = [NSMutableArray array];

    NSString *dir = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"blocker"];
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"manifest.json"]] ?: [NSData data]
                                                             options:0 error:nil];
    NSArray<NSString *> *files = manifest[@"files"] ?: @[];
    NSString *version = manifest[@"version"] ?: @"1";
    NSDictionary *stats = manifest[@"stats"];
    self.ruleCount = [stats[@"network"] unsignedIntegerValue] + [stats[@"cosmetic_generic"] unsignedIntegerValue] + [stats[@"cosmetic_specific"] unsignedIntegerValue];

    WKContentRuleListStore *store = WKContentRuleListStore.defaultStore;
    NSMutableArray<NSString *> *wanted = [NSMutableArray array];
    for (NSString *f in files) [wanted addObject:[NSString stringWithFormat:@"vg.%@.%@", version, f.stringByDeletingPathExtension]];

    // Remove rules left over from older versions of the app.
    [store getAvailableContentRuleListIdentifiers:^(NSArray<NSString *> *ids) {
        for (NSString *i in ids) if ([i hasPrefix:@"vg."] && ![wanted containsObject:i]) [store removeContentRuleListForIdentifier:i completionHandler:^(NSError *e) {}];
    }];

    self.files = files;
    self.identifiers = wanted;
    self.rulesDir = dir;
    [self loadFile:0];
}

/// One file at a time: use the saved compiled copy, or compile it the first time.
/// A file that fails is skipped. (Plain method calls, so nothing refers to freed memory.)
- (void)loadFile:(NSUInteger)i {
    if (i >= self.files.count) {
        [VGCrash breadcrumb:@"ad blocker ready"];
        self.ready = YES;
        self.preparing = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:VGBlockerDidChangeNotification object:nil];
        return;
    }
    NSString *file = self.files[i];
    NSString *ident = self.identifiers[i];
    WKContentRuleListStore *store = WKContentRuleListStore.defaultStore;
    [store lookUpContentRuleListForIdentifier:ident completionHandler:^(WKContentRuleList *list, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (list) {
                [self.lists addObject:list];
                [self loadFile:i + 1];
                return;
            }
            NSString *path = [self.rulesDir stringByAppendingPathComponent:file];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                NSString *json = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!json) { [self loadFile:i + 1]; return; }
                    [VGCrash breadcrumb:[NSString stringWithFormat:@"adblock compile %@", file]];
                    [store compileContentRuleListForIdentifier:ident encodedContentRuleList:json completionHandler:^(WKContentRuleList *compiled, NSError *e) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [VGCrash breadcrumb:[NSString stringWithFormat:@"adblock compiled %@ %@", file, compiled ? @"ok" : @"failed"]];
                            if (compiled) [self.lists addObject:compiled];
                            else NSLog(@"[VidGrab] ad-block file %@ skipped: %@", file, e.localizedDescription);
                            [self loadFile:i + 1];
                        });
                    }];
                });
            });
        });
    }];
}

- (void)applyTo:(WKUserContentController *)controller host:(NSString *)host {
    [controller removeAllContentRuleLists];
    if (!self.ready || !self.enabled || [self isAllowedSite:host]) return;
    for (WKContentRuleList *l in self.lists) [controller addContentRuleList:l];
}

#pragma mark YouTube

+ (NSString *)youTubeAdSkipScript {
    // While YouTube marks the player as showing an ad: mute it, jump to its end, and press Skip.
    // Restores sound and speed when the real video resumes. Also hides ad cards in the feed.
    return @""
    "(function(){\n"
    "if (!/(^|\\.)youtube\\.com$/.test(location.hostname) || window.__vgYT) return; window.__vgYT = true;\n"
    "var inAd = false, wasMuted = false;\n"
    "setInterval(function(){\n"
    "  var v = document.querySelector('video');\n"
    "  var ad = document.querySelector('.ad-showing, .ad-interrupting');\n"
    "  if (ad && v) {\n"
    "    if (!inAd) { inAd = true; wasMuted = v.muted; }\n"
    "    v.muted = true;\n"
    "    if (isFinite(v.duration) && v.duration > 0 && v.currentTime < v.duration - 0.2) v.currentTime = v.duration - 0.1;\n"
    "  } else if (inAd && v) { inAd = false; v.muted = wasMuted; v.playbackRate = 1; }\n"
    "  var skip = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytm-skip-ad-button, [class*=\"skip-ad\"] button');\n"
    "  if (skip) skip.click();\n"
    "  var junk = document.querySelectorAll('ytm-promoted-sparkles-web-renderer, ytm-companion-ad-renderer, ytm-ad-slot-renderer, ytd-ad-slot-renderer, ytm-promoted-video-renderer, ytd-in-feed-ad-layout-renderer, ytd-banner-promo-renderer');\n"
    "  for (var i = 0; i < junk.length; i++) junk[i].style.display = 'none';\n"
    "}, 250);\n"
    "})();";
}

@end
