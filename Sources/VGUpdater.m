#import "VGUpdater.h"
#import "VGActions.h"
#import "VGTheme.h"

static NSString *const kRepo = @"iamjhe08/VidGrab";
static NSString *const kLastCheck = @"vgUpdateLastCheck";
static NSString *const kSkipped = @"vgUpdateSkipped";

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
    vc.view.backgroundColor = VGSurface;
    vc.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    vc.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    vc.sheetPresentationController.prefersGrabberVisible = YES;
    vc.sheetPresentationController.preferredCornerRadius = 22;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.app.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightSemibold]]];
    icon.tintColor = VGAccent;
    icon.contentMode = UIViewContentModeLeft;
    UILabel *title = [UILabel new];
    title.text = [NSString stringWithFormat:@"VidGrab %@ is available", version];
    title.font = VGFont(24, UIFontWeightHeavy); title.textColor = VGText; title.numberOfLines = 0;
    UILabel *sub = [UILabel new];
    sub.text = [NSString stringWithFormat:@"You have %@. Your downloads and settings stay after updating.", [self currentVersion]];
    sub.font = VGFont(14, UIFontWeightMedium); sub.textColor = VGSecondary; sub.numberOfLines = 0;
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
    void (^close)(void (^)(void)) = ^(void (^then)(void)) { [wvc dismissViewControllerAnimated:YES completion:then]; };
    NSMutableArray *buttons = [NSMutableArray array];
    NSURL *troll = ipa ? [NSURL URLWithString:[@"apple-magnifier://install?url=" stringByAppendingString:
                          [ipa stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]]] : nil;
    BOOL hasTroll = troll && [UIApplication.sharedApplication canOpenURL:troll];
    NSString *dl = page ?: [NSString stringWithFormat:@"https://github.com/%@/releases/latest", kRepo];
    if (hasTroll) {
        UIButton *b = VGPrimaryButton(@"Install with TrollStore", @"arrow.down.circle.fill");
        [b addAction:[UIAction actionWithHandler:^(UIAction *x) {
            close(^{ [UIApplication.sharedApplication openURL:troll options:@{} completionHandler:nil]; });
        }] forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:b];
    }
    UIButton *open = hasTroll ? VGSecondaryButton(@"Open download page", @"safari") : VGPrimaryButton(@"Open download page", @"safari");
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
    [head setCustomSpacing:20 afterView:sub];
    UIStackView *foot = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    foot.axis = UILayoutConstraintAxisVertical; foot.spacing = 10;
    UIStackView *root = [[UIStackView alloc] initWithArrangedSubviews:@[head, log, foot]];
    root.axis = UILayoutConstraintAxisVertical; root.spacing = 14;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:root];
    UILayoutGuide *g = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:g.topAnchor constant:28],
        [root.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],
        [root.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:22],
        [root.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-22],
        [log.heightAnchor constraintGreaterThanOrEqualToConstant:90],
    ]];

    UIViewController *top = host;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:vc animated:YES completion:nil];
}

+ (void)checkQuietlyFrom:(UIViewController *)host {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSDate *last = [d objectForKey:kLastCheck];
    if (last && -last.timeIntervalSinceNow < 12 * 3600) return;
    [d setObject:[NSDate date] forKey:kLastCheck];
    [self fetch:^(NSString *version, NSString *notes, NSString *ipa, NSString *page, NSString *problem) {
        if (problem || ![self isNewer:version]) return;
        if ([[d stringForKey:kSkipped] isEqualToString:version]) return;
        [self offer:version notes:notes ipa:ipa page:page from:host quiet:YES];
    }];
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
