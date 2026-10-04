#import "VGUpdater.h"
#import "VGActions.h"
#import "VGTheme.h"

static NSString *const kRepo = @"iamjhe08/VidGrab";
static NSString *const kLastCheck = @"vgUpdateLastCheck";
static NSString *const kSkipped = @"vgUpdateSkipped";
static BOOL gShowing = NO;   // the update screen is on screen right now

@implementation VGUpdater

+ (NSString *)currentVersion {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
}

static NSString *clean(NSString *tag) {
    NSString *t = [tag stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([t.lowercaseString hasPrefix:@"v"]) t = [t substringFromIndex:1];
    return t;
}

/// Asks GitHub for the latest release. completion(version, notes, ipaURL, pageURL, error) on the main queue.
+ (void)fetch:(void (^)(NSString *_Nullable, NSString *_Nullable, NSString *_Nullable, NSString *_Nullable, NSString *_Nullable))completion {
    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", kRepo]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:[@"VidGrab/" stringByAppendingString:[self currentVersion]] forHTTPHeaderField:@"User-Agent"];
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSString *version = nil, *notes = nil, *ipa = nil, *page = nil, *problem = nil;
        NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (err) problem = @"Couldn't reach GitHub. Check your internet connection.";
        else if (code == 404) problem = @"No releases have been published yet.";
        else if (code != 200 || ![json isKindOfClass:NSDictionary.class]) problem = @"GitHub didn't answer properly. Try again later.";
        else {
            version = [json[@"tag_name"] isKindOfClass:NSString.class] ? clean(json[@"tag_name"]) : nil;
            notes = [json[@"body"] isKindOfClass:NSString.class] ? json[@"body"] : nil;
            page = [json[@"html_url"] isKindOfClass:NSString.class] ? json[@"html_url"] : nil;
            for (NSDictionary *a in [json[@"assets"] isKindOfClass:NSArray.class] ? json[@"assets"] : @[]) {
                if (![a isKindOfClass:NSDictionary.class]) continue;
                NSString *name = [a[@"name"] isKindOfClass:NSString.class] ? a[@"name"] : @"";
                if ([name.lowercaseString hasSuffix:@".ipa"]) { ipa = a[@"browser_download_url"]; break; }
            }
            if (!version.length) problem = @"The latest release has no version number.";
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(version, notes, ipa, page, problem); });
    }] resume];
}

/// Which TrollStore installed this copy: @"TrollStore", @"TrollStore Lite", or nil.
/// iOS doesn't let apps look at the folder around them, so this checks the app itself instead:
/// - it must be a normally installed app (not running inside LiveContainer or similar), and
/// - it must have no signing profile (embedded.mobileprovision). AltStore, SideStore, Sideloadly,
///   ESign and other sideloading tools always add one; TrollStore doesn't.
/// If iOS does allow a look around, TrollStore's own marker file (.TrollStore / .TrollStoreLite) also counts.
+ (NSString *)trollStoreFlavor {
    NSString *bundle = NSBundle.mainBundle.bundlePath;
    NSString *container = bundle.stringByDeletingLastPathComponent;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *m in @[@".TrollStoreLite", @"_TrollStoreLite"])
        if ([fm fileExistsAtPath:[container stringByAppendingPathComponent:m]]) return @"TrollStore Lite";
    for (NSString *m in @[@".TrollStore", @"_TrollStore"])
        if ([fm fileExistsAtPath:[container stringByAppendingPathComponent:m]]) return @"TrollStore";
    if ([self jailbreakInstall]) return nil;
    BOOL installedApp = [bundle hasPrefix:@"/private/var/containers/Bundle/Application/"] || [bundle hasPrefix:@"/var/containers/Bundle/Application/"];
    BOOL hasProfile = [fm fileExistsAtPath:[bundle stringByAppendingPathComponent:@"embedded.mobileprovision"]];
    return (installedApp && !hasProfile) ? @"TrollStore" : nil;
}

+ (BOOL)installedByTrollStore { return [self trollStoreFlavor] != nil; }

/// True when VidGrab was installed as a jailbreak package (.deb): rootful /Applications,
/// rootless /var/jb/Applications, or roothide's hidden .jbroot folder. Those update through Sileo.
+ (BOOL)jailbreakInstall {
    NSString *b = NSBundle.mainBundle.bundlePath;
    return [b hasPrefix:@"/Applications/"] || [b hasPrefix:@"/var/jb/"] || [b hasPrefix:@"/private/preboot/"] || [b containsString:@"/.jbroot-"];
}

+ (BOOL)isNewer:(NSString *)v {
    return [v compare:[self currentVersion] options:NSNumericSearch] == NSOrderedDescending;
}

/// Turns GitHub release notes (Markdown) into clean text: headings in bold, bullets as dots.
+ (NSAttributedString *)changelog:(NSString *)md {
    NSMutableAttributedString *out = [NSMutableAttributedString new];
    NSDictionary *body = @{NSFontAttributeName: VGFont(15, UIFontWeightRegular), NSForegroundColorAttributeName: VGText};
    NSDictionary *head = @{NSFontAttributeName: VGFont(16, UIFontWeightHeavy), NSForegroundColorAttributeName: VGText};
    NSMutableParagraphStyle *bullet = [NSMutableParagraphStyle new];
    bullet.headIndent = 18; bullet.paragraphSpacing = 4;
    bullet.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:18 options:@{}]];
    NSRegularExpression *link = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\([^)]+\\)" options:0 error:nil];
    NSString *norm = [md stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    BOOL first = YES;
    for (NSString *raw in [norm componentsSeparatedByString:@"\n"]) {
        NSString *l = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        l = [link stringByReplacingMatchesInString:l options:0 range:NSMakeRange(0, l.length) withTemplate:@"$1"];
        for (NSString *m in @[@"**", @"__", @"`"]) l = [l stringByReplacingOccurrencesOfString:m withString:@""];
        if (!l.length) { if (!first) [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:body]]; continue; }
        NSString *prefix = first ? @"" : @"\n";
        first = NO;
        if ([l hasPrefix:@"#"]) {
            while ([l hasPrefix:@"#"]) l = [l substringFromIndex:1];
            l = [l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:[prefix stringByAppendingString:l] attributes:head]];
        } else if ([l hasPrefix:@"- "] || [l hasPrefix:@"* "] || [l hasPrefix:@"+ "]) {
            NSMutableDictionary *a = [body mutableCopy]; a[NSParagraphStyleAttributeName] = bullet;
            NSString *t = [NSString stringWithFormat:@"%@•\t%@", prefix, [l substringFromIndex:2]];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:a]];
        } else {
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:[prefix stringByAppendingString:l] attributes:body]];
        }
    }
    if (!out.length) [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"Bug fixes and improvements." attributes:body]];
    return out;
}

+ (void)offer:(NSString *)version notes:(NSString *)notes ipa:(NSString *)ipa page:(NSString *)page from:(UIViewController *)host quiet:(BOOL)quiet {
    UIViewController *vc = [UIViewController new];
    // A card in the middle of the screen over a dimmed background.
    vc.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    vc.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.app.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightSemibold]]];
    icon.tintColor = VGAccent;
    icon.contentMode = UIViewContentModeCenter;
    UILabel *title = [UILabel new];
    title.text = [NSString stringWithFormat:@"VidGrab %@ is available", version];
    title.font = VGFont(22, UIFontWeightHeavy); title.textColor = VGText; title.numberOfLines = 0; title.textAlignment = NSTextAlignmentCenter;
    UILabel *sub = [UILabel new];
    sub.text = [NSString stringWithFormat:@"You have %@. Your downloads and settings stay after updating.", [self currentVersion]];
    sub.font = VGFont(14, UIFontWeightMedium); sub.textColor = VGSecondary; sub.numberOfLines = 0; sub.textAlignment = NSTextAlignmentCenter;
    UILabel *whatsNew = [UILabel new];
    whatsNew.attributedText = [[NSAttributedString alloc] initWithString:@"WHAT'S NEW" attributes:@{NSKernAttributeName: @1.0,
        NSFontAttributeName: VGFont(12, UIFontWeightHeavy), NSForegroundColorAttributeName: VGTertiary}];

    UITextView *log = [UITextView new];
    log.attributedText = [self changelog:notes ?: @""];
    log.editable = NO;
    log.backgroundColor = VGSurface2;
    log.layer.cornerRadius = 14;
    log.layer.cornerCurve = kCACornerCurveContinuous;
    log.textContainerInset = UIEdgeInsetsMake(14, 12, 14, 12);
    log.dataDetectorTypes = UIDataDetectorTypeLink;

    __weak UIViewController *wvc = vc;
    gShowing = YES;
    void (^close)(void (^)(void)) = ^(void (^then)(void)) {
        gShowing = NO;
        [wvc dismissViewControllerAnimated:YES completion:then];
    };
    NSMutableArray *buttons = [NSMutableArray array];
    NSURL *troll = ipa.length ? [NSURL URLWithString:[@"apple-magnifier://install?url=" stringByAppendingString:
                          [ipa stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]]] : nil;
    // Only apps installed by TrollStore can update through it. TrollStore leaves a "_TrollStore"
    // marker next to the app; anything else (LiveContainer, AltStore, sideloading) gets a greyed-out button.
    BOOL hasTroll = troll && [self installedByTrollStore];
    NSString *dl = page.length ? page : [NSString stringWithFormat:@"https://github.com/%@/releases/latest", kRepo];
    NSString *trollName = [@"Install with " stringByAppendingString:[self trollStoreFlavor] ?: @"TrollStore"];
    if ([self jailbreakInstall]) {
        NSURL *sileo = [NSURL URLWithString:@"sileo://package/com.t4mag0.vidgrab"];
        UIButton *sb = VGPrimaryButton(@"Update in Sileo", @"shippingbox.fill");
        [sb addAction:[UIAction actionWithHandler:^(UIAction *x) {
            close(^{ [UIApplication.sharedApplication openURL:sileo options:@{} completionHandler:nil]; });
        }] forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:sb];
        troll = nil;   // no TrollStore button for jailbreak installs
    }
    UIButton *b = hasTroll ? VGPrimaryButton(trollName, @"arrow.down.circle.fill")
                           : VGSecondaryButton(trollName, @"arrow.down.circle.fill");
    if (hasTroll) {
        [b addAction:[UIAction actionWithHandler:^(UIAction *x) {
            close(^{ [UIApplication.sharedApplication openURL:troll options:@{} completionHandler:nil]; });
        }] forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:b];
    } else if (troll) {
        b.enabled = NO;
        b.alpha = 0.4;
        UILabel *why = [UILabel new];
        why.text = @"Only for VidGrab installed with TrollStore. Use the download page instead.";
        why.font = VGFont(12, UIFontWeightMedium);
        why.textColor = VGTertiary;
        why.textAlignment = NSTextAlignmentCenter;
        why.numberOfLines = 0;
        UIStackView *pair = [[UIStackView alloc] initWithArrangedSubviews:@[b, why]];
        pair.axis = UILayoutConstraintAxisVertical;
        pair.spacing = 6;
        [buttons addObject:pair];
    }
    BOOL secondary = hasTroll || [self jailbreakInstall];
    UIButton *open = secondary ? VGSecondaryButton(@"Open download page", @"safari") : VGPrimaryButton(@"Open download page", @"safari");
    [open addAction:[UIAction actionWithHandler:^(UIAction *x) {
        close(^{ [UIApplication.sharedApplication openURL:[NSURL URLWithString:dl] options:@{} completionHandler:nil]; });
    }] forControlEvents:UIControlEventTouchUpInside];
    [buttons addObject:open];
    NSMutableArray *small = [NSMutableArray array];
    if (quiet) {
        UIButton *skip = [UIButton buttonWithType:UIButtonTypeSystem];
        [skip setTitle:@"Skip this version" forState:UIControlStateNormal];
        skip.titleLabel.font = VGFont(15, UIFontWeightSemibold);
        skip.tintColor = VGSecondary;
        [skip addAction:[UIAction actionWithHandler:^(UIAction *x) {
            [NSUserDefaults.standardUserDefaults setObject:version forKey:kSkipped];
            close(nil);
        }] forControlEvents:UIControlEventTouchUpInside];
        [small addObject:skip];
    }
    UIButton *later = [UIButton buttonWithType:UIButtonTypeSystem];
    [later setTitle:@"Later" forState:UIControlStateNormal];
    later.titleLabel.font = VGFont(15, UIFontWeightSemibold);
    later.tintColor = VGSecondary;
    [later addAction:[UIAction actionWithHandler:^(UIAction *x) { close(nil); }] forControlEvents:UIControlEventTouchUpInside];
    [small addObject:later];
    UIStackView *smallRow = [[UIStackView alloc] initWithArrangedSubviews:small];
    smallRow.distribution = UIStackViewDistributionFillEqually;
    [buttons addObject:smallRow];

    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, sub, whatsNew]];
    head.axis = UILayoutConstraintAxisVertical; head.spacing = 8;
    [head setCustomSpacing:12 afterView:icon];
    [head setCustomSpacing:18 afterView:sub];
    UIStackView *foot = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    foot.axis = UILayoutConstraintAxisVertical; foot.spacing = 10;
    UIStackView *root = [[UIStackView alloc] initWithArrangedSubviews:@[head, log, foot]];
    root.axis = UILayoutConstraintAxisVertical; root.spacing = 14;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *card = [UIView new];
    card.backgroundColor = VGSurface;
    card.layer.cornerRadius = 24;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderColor = VGStroke.CGColor;
    card.layer.borderWidth = 1;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:root];
    [vc.view addSubview:card];
    UILayoutGuide *g = vc.view.safeAreaLayoutGuide;
    NSLayoutConstraint *wide = [card.widthAnchor constraintEqualToConstant:400];
    wide.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *logH = [log.heightAnchor constraintEqualToConstant:MIN(260, MAX(90, [log sizeThatFits:CGSizeMake(330, CGFLOAT_MAX)].height))];
    logH.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:g.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
        wide,
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:g.leadingAnchor constant:20],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:g.trailingAnchor constant:-20],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:g.topAnchor constant:20],
        [card.bottomAnchor constraintLessThanOrEqualToAnchor:g.bottomAnchor constant:-20],
        [root.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [root.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [root.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [root.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        logH,
        [log.heightAnchor constraintGreaterThanOrEqualToConstant:70],
    ]];

    UIViewController *top = host;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:vc animated:YES completion:nil];
}

/// Shows the update screen once the app is settled (waits if something else is on screen).
+ (void)present:(NSDictionary *)rel from:(UIViewController *)host tries:(int)tries {
    if (gShowing) return;
    UIViewController *top = host;
    while (top.presentedViewController) top = top.presentedViewController;
    BOOL busy = !host.view.window || top.isBeingPresented || top.isBeingDismissed || [top isKindOfClass:UIAlertController.class];
    if (busy) {
        if (tries > 0) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self present:rel from:host tries:tries - 1];
        });
        return;
    }
    [self offer:rel[@"v"] notes:rel[@"n"] ipa:rel[@"i"] page:rel[@"p"] from:host quiet:YES];
}

+ (void)checkQuietlyFrom:(UIViewController *)host {
    // Runs every time the app opens. GitHub is asked at most once a minute; in between,
    // the last answer is reused so the update screen still shows on every open.
    if (gShowing) {
        UIViewController *top = host;
        while (top.presentedViewController) top = top.presentedViewController;
        if (top != host) return;     // still on screen
        gShowing = NO;               // it was swiped away
    }
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    void (^decide)(NSDictionary *) = ^(NSDictionary *rel) {
        NSString *v = rel[@"v"];
        if (!v.length || ![self isNewer:v]) return;
        if ([[d stringForKey:kSkipped] isEqualToString:v]) return;
        [self present:rel from:host tries:6];
    };
    NSDate *last = [d objectForKey:kLastCheck];
    NSDictionary *cached = [d dictionaryForKey:@"vgUpdateLatest"];
    if (last && -last.timeIntervalSinceNow < 60 && cached) { decide(cached); return; }
    __block int attempts = 0;
    __block void (^ask)(void);
    void (^askOnce)(void) = ^{
        attempts++;
        [self fetch:^(NSString *version, NSString *notes, NSString *ipa, NSString *page, NSString *problem) {
            if (problem) {
                // The first request right after opening can fail while the connection wakes up; try again shortly.
                if (attempts < 3) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ask);
                else ask = nil;
                return;
            }
            ask = nil;
            NSDictionary *rel = @{@"v": version ?: @"", @"n": notes ?: @"", @"i": ipa ?: @"", @"p": page ?: @""};
            [d setObject:[NSDate date] forKey:kLastCheck];
            [d setObject:rel forKey:@"vgUpdateLatest"];
            decide(rel);
        }];
    };
    ask = askOnce;
    ask();
}

+ (void)checkNowFrom:(UIViewController *)host {
    [self fetch:^(NSString *version, NSString *notes, NSString *ipa, NSString *page, NSString *problem) {
        [NSUserDefaults.standardUserDefaults setObject:[NSDate date] forKey:kLastCheck];
        if (problem) { [VGActions alert:@"Couldn't check for updates" message:problem from:host]; return; }
        if (![self isNewer:version]) {
            [VGActions alert:@"You're up to date" message:[NSString stringWithFormat:@"VidGrab %@ is the latest version.", [self currentVersion]] from:host];
            return;
        }
        [self offer:version notes:notes ipa:ipa page:page from:host quiet:NO];
    }];
}

@end
