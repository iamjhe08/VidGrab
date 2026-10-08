#import "VGBrowserViewController.h"
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import "VGEngine.h"
#import "VGTheme.h"
#import "VGActions.h"
#import "VGQualitySheet.h"
#import "VGBlocker.h"
#import "VGCrash.h"

// Injected into every page: finds the main playing video and puts a Download
// button on top of it. Taps are sent to the app through the "vidgrab" handler.
static NSString *const kOverlayJS = @""
"(function(){\n"
"if (window.__vgInstalled) return; window.__vgInstalled = true;\n"
"var post = function(m){ try { window.webkit.messageHandlers.vidgrab.postMessage(m); } catch(e){} };\n"
"var btn = document.createElement('div');\n"
"btn.setAttribute('aria-label','Download with VidGrab');\n"
"btn.innerHTML = '<svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#fff\" stroke-width=\"2.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 4v11\"/><path d=\"M7 10l5 5 5-5\"/><path d=\"M5 20h14\"/></svg><span style=\"margin-left:6px\">Download</span>';\n"
"var st = btn.style;\n"
"st.position='fixed'; st.zIndex='2147483647'; st.display='none'; st.alignItems='center';\n"
"st.padding='8px 13px 8px 11px'; st.borderRadius='20px'; st.background='rgba(255,61,104,0.96)';\n"
"st.color='#fff'; st.font='700 13px -apple-system, system-ui, sans-serif'; st.letterSpacing='0.2px';\n"
"st.boxShadow='0 4px 16px rgba(0,0,0,.5)'; st.webkitUserSelect='none'; st.userSelect='none';\n"
"st.webkitTapHighlightColor='transparent'; st.cursor='pointer';\n"
"var current = null, lastState = '';\n"
"var fire = function(e){ e.preventDefault(); e.stopPropagation();\n"
"  var src = (current && (current.currentSrc || current.src)) || '';\n"
"  post({type:'download', page: location.href, src: src, title: document.title}); };\n"
"btn.addEventListener('click', fire, true);\n"
"btn.addEventListener('touchend', fire, true);\n"
"function visibleArea(r){ var w=Math.min(r.right,innerWidth)-Math.max(r.left,0); var h=Math.min(r.bottom,innerHeight)-Math.max(r.top,0); return (w>0&&h>0)?w*h:0; }\n"
"function best(){ var b=null, ba=0; var vids=document.querySelectorAll('video');\n"
"  for (var i=0;i<vids.length;i++){ var v=vids[i], r=v.getBoundingClientRect(); var a=visibleArea(r);\n"
"    if (r.width>=120 && r.height>=68 && a>ba){ ba=a; b=v; } } return b; }\n"
"function tick(){\n"
"  if (!btn.isConnected && document.body) document.body.appendChild(btn);\n"
"  var v = best(); current = v;\n"
"  if (v) { var r=v.getBoundingClientRect(); st.display='flex';\n"
"    var bw = btn.offsetWidth || 110; var top = Math.max(10, r.top + 10);\n"
"    var left = Math.min(innerWidth - bw - 10, r.right - bw - 10); st.top = top + 'px'; st.left = Math.max(10,left) + 'px'; }\n"
"  else { st.display='none'; }\n"
"  var vs = v ? (v.currentSrc || v.src || '') : '';\n"
"  var s = (v?'v':'-') + (v && !v.paused ? 'p' : '') + location.href + '|' + vs;\n"
"  if (s !== lastState) { lastState = s; post({type:'state', hasVideo: !!v, playing: !!(v && !v.paused), page: location.href, title: document.title, src: vs}); }\n"
"}\n"
"setInterval(tick, 350);\n"
"addEventListener('scroll', tick, {passive:true}); addEventListener('resize', tick);\n"
"document.addEventListener('play', tick, true); document.addEventListener('pause', tick, true);\n"
"tick();\n"
"})();";

@interface VGBrowserViewController () <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UITextFieldDelegate>
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic, strong) UITextField *address;
@property (nonatomic, strong) UIButton *closeButton, *backButton, *reloadButton, *shieldButton;
@property (nonatomic, copy) NSString *appliedHost;
@property (nonatomic, strong) UIProgressView *loadBar;
@property (nonatomic, strong) UIView *startPage;
@property (nonatomic, strong) UIStackView *favGrid;
@property (nonatomic, strong) UIButton *starButton;
@property (nonatomic, strong) UIButton *fab;          // floating Download button
@property (nonatomic, strong) VGProgressBar *fabBar;  // progress inside it
@property (nonatomic, strong) UILabel *fabBadge;      // number of downloads when more than one
@property (nonatomic) BOOL pageHasVideo;
@property (nonatomic, copy) NSString *activeStream;    // the stream whose pieces the page fetched most recently (the one playing)
@property (nonatomic, copy) NSString *playingSrc;      // the playing video element's own address, when it is a plain link
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *captured;   // video streams this page asked for while it played
@end

@implementation VGBrowserViewController

- (void)dealloc {
    [self.web removeObserver:self forKeyPath:@"estimatedProgress"];
    [self.web removeObserver:self forKeyPath:@"URL"];
    [self.web removeObserver:self forKeyPath:@"canGoBack"];
    [self.web removeObserver:self forKeyPath:@"canGoForward"];
    [self.web.configuration.userContentController removeScriptMessageHandlerForName:@"vidgrab"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VGBackground;
    self.title = @"Browse";

    // Web view
    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.allowsPictureInPictureMediaPlayback = YES;
    // Tell sites the real iOS version, so older iPhones get code their web engine can run.
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    cfg.applicationNameForUserAgent = [NSString stringWithFormat:@"Version/%ld.%ld Mobile/15E148 Safari/604.1", (long)os.majorVersion, (long)os.minorVersion];
    cfg.websiteDataStore = WKWebsiteDataStore.defaultDataStore;  // remembers sign-ins
    [cfg.userContentController addScriptMessageHandler:self name:@"vidgrab"];
    self.web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    self.web.navigationDelegate = self;
    self.web.UIDelegate = self;
    self.web.allowsBackForwardNavigationGestures = YES;
    self.web.backgroundColor = VGBackground;
    self.web.opaque = NO;
    self.web.scrollView.backgroundColor = VGBackground;
    self.web.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.web];
    [VGCrash breadcrumb:@"browser opened"];
    self.captured = [NSMutableArray array];
    [self installScripts];
    [[VGBlocker shared] prepare];
    [[VGBlocker shared] applyTo:self.web.configuration.userContentController host:nil];
    for (NSString *k in @[@"estimatedProgress", @"URL", @"canGoBack", @"canGoForward"]) {
        [self.web addObserver:self forKeyPath:k options:NSKeyValueObservingOptionNew context:nil];
    }

    // Top bar
    UIView *bar = [UIView new];
    bar.backgroundColor = VGBackground;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];

    self.closeButton = [self iconButton:@"xmark" action:@selector(closeSite)];
    self.closeButton.accessibilityLabel = @"Close site";
    self.backButton = [self iconButton:@"chevron.backward" action:@selector(goBack)];
    self.reloadButton = [self iconButton:@"arrow.clockwise" action:@selector(reloadOrStop)];
    self.shieldButton = [self iconButton:@"shield.lefthalf.filled" action:nil];
    self.shieldButton.accessibilityLabel = @"Ad blocker";
    self.shieldButton.showsMenuAsPrimaryAction = YES;
    __weak typeof(self) wself = self;
    self.shieldButton.menu = [UIMenu menuWithChildren:@[[UIDeferredMenuElement elementWithUncachedProvider:^(void (^done)(NSArray<UIMenuElement *> *)) {
        done([wself shieldMenuItems]);
    }]]];

    UIView *field = [UIView new];
    field.backgroundColor = VGSurface2;
    field.layer.cornerRadius = 11;
    UIImageView *mag = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    mag.tintColor = VGTertiary;
    mag.contentMode = UIViewContentModeScaleAspectFit;
    self.address = [UITextField new];
    self.address.textColor = VGText;
    self.address.tintColor = VGAccent;
    self.address.font = VGFont(15, UIFontWeightMedium);
    self.address.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Search or enter website"
                                                                         attributes:@{NSForegroundColorAttributeName: VGTertiary}];
    self.address.keyboardType = UIKeyboardTypeWebSearch;
    self.address.keyboardAppearance = UIKeyboardAppearanceDark;
    self.address.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.address.autocorrectionType = UITextAutocorrectionTypeNo;
    self.address.returnKeyType = UIReturnKeyGo;
    self.address.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.address.delegate = self;
    self.starButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.starButton.frame = CGRectMake(0, 0, 34, 34);
    [self.starButton addTarget:self action:@selector(toggleStar) forControlEvents:UIControlEventTouchUpInside];
    self.address.rightView = self.starButton;
    self.address.rightViewMode = UITextFieldViewModeNever;
    for (UIView *v in @[mag, self.address]) { v.translatesAutoresizingMaskIntoConstraints = NO; [field addSubview:v]; }

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.closeButton, self.backButton, field, self.shieldButton, self.reloadButton]];
    row.spacing = 4;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:row];

    self.loadBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.loadBar.progressTintColor = VGAccent;
    self.loadBar.trackTintColor = UIColor.clearColor;
    self.loadBar.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:self.loadBar];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:safe.topAnchor constant:56],
        [row.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:6],
        [row.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-6],
        [row.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-8],
        [field.heightAnchor constraintEqualToConstant:40],
        [mag.leadingAnchor constraintEqualToAnchor:field.leadingAnchor constant:11],
        [mag.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
        [mag.widthAnchor constraintEqualToConstant:16],
        [self.address.leadingAnchor constraintEqualToAnchor:mag.trailingAnchor constant:8],
        [self.address.trailingAnchor constraintEqualToAnchor:field.trailingAnchor constant:-6],
        [self.address.topAnchor constraintEqualToAnchor:field.topAnchor],
        [self.address.bottomAnchor constraintEqualToAnchor:field.bottomAnchor],
        [self.loadBar.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [self.loadBar.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [self.loadBar.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [self.loadBar.heightAnchor constraintEqualToConstant:2],
        [self.web.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [self.web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.web.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];

    [self buildStartPageBelow:bar];
    [self buildFab];
    [self updateButtons];

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(tasksChanged) name:VGTasksDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(taskFinished:) name:VGTaskFinishedNotification object:nil];
    [nc addObserver:self selector:@selector(blockerChanged) name:VGBlockerDidChangeNotification object:nil];
    [self updateShield];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (UIButton *)iconButton:(NSString *)icon action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]]
       forState:UIControlStateNormal];
    b.tintColor = VGText;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [b.widthAnchor constraintEqualToConstant:38].active = YES;
    [b.heightAnchor constraintEqualToConstant:40].active = YES;
    return b;
}

#pragma mark Ad blocker

- (void)installScripts {
    WKUserContentController *ucc = self.web.configuration.userContentController;
    [ucc removeAllUserScripts];
    // On iOS 15 and 16, add the newer JavaScript features modern sites expect (runs before the page's own code).
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 17) {
        NSString *poly = [NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"polyfills" ofType:@"js"] encoding:NSUTF8StringEncoding error:nil];
        if (poly.length) [ucc addUserScript:[[WKUserScript alloc] initWithSource:poly injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    }
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:kOverlayJS injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO]];
    // Notes the streams a page asks for while it plays, for sites that only show their video once it plays.
    NSString *sniff = [NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"sniffer" ofType:@"js"] encoding:NSUTF8StringEncoding error:nil];
    if (sniff.length) [ucc addUserScript:[[WKUserScript alloc] initWithSource:sniff injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    if ([VGBlocker shared].enabled && [VGBlocker shared].skipYouTubeAds) {
        [ucc addUserScript:[[WKUserScript alloc] initWithSource:[VGBlocker youTubeAdSkipScript]
                                                 injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
    }
}

- (NSString *)currentHost {
    return (self.startPage.hidden && [self.web.URL.scheme hasPrefix:@"http"]) ? self.web.URL.host : nil;
}

- (void)applyRulesForHost:(NSString *)host {
    self.appliedHost = host;
    [[VGBlocker shared] applyTo:self.web.configuration.userContentController host:host];
    [self updateShield];
}

- (void)blockerChanged {
    [self installScripts];
    [self applyRulesForHost:[self currentHost]];
}

- (void)updateShield {
    VGBlocker *b = [VGBlocker shared];
    NSString *host = [self currentHost];
    BOOL active = b.enabled && ![b isAllowedSite:host];
    UIImage *img = [UIImage systemImageNamed:active ? @"shield.lefthalf.filled" : @"shield.slash"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]];
    [self.shieldButton setImage:img forState:UIControlStateNormal];
    self.shieldButton.tintColor = active ? VGAccent : VGTertiary;
}

- (NSArray<UIMenuElement *> *)shieldMenuItems {
    VGBlocker *b = [VGBlocker shared];
    NSString *host = [self currentHost];
    __weak typeof(self) ws = self;
    NSMutableArray *items = [NSMutableArray array];

    UIAction *toggle = [UIAction actionWithTitle:@"Block ads & trackers" image:[UIImage systemImageNamed:@"shield.lefthalf.filled"]
                                      identifier:nil handler:^(UIAction *a) { b.enabled = !b.enabled; [ws reloadAfterBlockerChange]; }];
    toggle.state = b.enabled ? UIMenuElementStateOn : UIMenuElementStateOff;
    toggle.subtitle = b.ready ? [NSString stringWithFormat:@"%@ rules from uBlock Origin Lite's lists",
                                 [NSNumberFormatter localizedStringFromNumber:@(b.ruleCount) numberStyle:NSNumberFormatterDecimalStyle]]
                              : @"Getting rules ready…";
    [items addObject:toggle];

    if (host && b.enabled) {
        NSString *site = host;
        for (NSString *p in @[@"www.", @"m."]) if ([site hasPrefix:p]) site = [site substringFromIndex:p.length];
        BOOL allowed = [b isAllowedSite:host];
        UIAction *allow = [UIAction actionWithTitle:[NSString stringWithFormat:@"Turn off on %@", site] image:[UIImage systemImageNamed:@"hand.raised.slash"]
                                         identifier:nil handler:^(UIAction *a) { [b setAllowed:!allowed forSite:host]; [ws reloadAfterBlockerChange]; }];
        allow.state = allowed ? UIMenuElementStateOn : UIMenuElementStateOff;
        allow.subtitle = @"Use this if a site doesn't work right";
        [items addObject:allow];
    }

    UIAction *yt = [UIAction actionWithTitle:@"Skip YouTube video ads" image:[UIImage systemImageNamed:@"forward.end"]
                                  identifier:nil handler:^(UIAction *a) { b.skipYouTubeAds = !b.skipYouTubeAds; [ws reloadAfterBlockerChange]; }];
    yt.state = b.skipYouTubeAds ? UIMenuElementStateOn : UIMenuElementStateOff;
    if (!b.enabled) yt.attributes = UIMenuElementAttributesDisabled;
    [items addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[yt]]];
    return items;
}

- (void)reloadAfterBlockerChange {
    [self blockerChanged];
    if ([self currentHost]) [self.web reload];
}

#pragma mark Favorites (saved on the phone)

static NSString *const kFavKey = @"vgFavorites";

- (NSArray<NSDictionary *> *)defaultFavorites {
    return @[
        @{@"name": @"YouTube", @"url": @"https://m.youtube.com"}, @{@"name": @"TikTok", @"url": @"https://www.tiktok.com"},
        @{@"name": @"Instagram", @"url": @"https://www.instagram.com"}, @{@"name": @"X", @"url": @"https://x.com"},
        @{@"name": @"Facebook", @"url": @"https://m.facebook.com"}, @{@"name": @"Reddit", @"url": @"https://www.reddit.com"},
        @{@"name": @"Vimeo", @"url": @"https://vimeo.com"}, @{@"name": @"Dailymotion", @"url": @"https://www.dailymotion.com"},
    ];
}

- (NSArray<NSDictionary *> *)favorites {
    NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:kFavKey];
    return [saved isKindOfClass:NSArray.class] ? saved : [self defaultFavorites];
}

- (void)saveFavorites:(NSArray *)favs {
    [NSUserDefaults.standardUserDefaults setObject:favs forKey:kFavKey];
    [self reloadFavorites];
    [self updateStar];
}

static NSString *siteDomain(NSString *urlOrHost) {
    NSString *h = [urlOrHost containsString:@"://"] ? [NSURL URLWithString:urlOrHost].host : urlOrHost;
    h = h.lowercaseString ?: @"";
    for (NSString *p in @[@"www.", @"m.", @"mobile."]) if ([h hasPrefix:p]) h = [h substringFromIndex:p.length];
    return h;
}

/// Makes "example.com", "example.com/path" or a full link into a proper https link.
static NSString *normalizedLink(NSString *text) {
    NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!t.length) return nil;
    if (![t containsString:@"://"]) t = [@"https://" stringByAppendingString:t];
    NSURL *u = [NSURL URLWithString:t];
    return (u.host.length && [u.host containsString:@"."]) ? u.absoluteString : nil;
}

- (NSInteger)favoriteIndexForHost:(NSString *)host {
    if (!host.length) return NSNotFound;
    NSString *d = siteDomain(host);
    NSArray *favs = [self favorites];
    for (NSUInteger i = 0; i < favs.count; i++) if ([siteDomain(favs[i][@"url"]) isEqualToString:d]) return (NSInteger)i;
    return NSNotFound;
}

/// Asks for a name and link. Used for adding and editing.
- (void)askFavoriteTitle:(NSString *)title name:(NSString *)name link:(NSString *)link
             askName:(BOOL)askName askLink:(BOOL)askLink done:(void (^)(NSString *name, NSString *link))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    if (askName) [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"Name";
        f.text = name;
        f.autocapitalizationType = UITextAutocapitalizationTypeWords;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    if (askLink) [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"Website, e.g. bilibili.tv";
        f.text = link;
        f.keyboardType = UIKeyboardTypeURL;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *n = askName ? wa.textFields.firstObject.text : name;
        NSString *l = askLink ? wa.textFields.lastObject.text : link;
        NSString *fixed = normalizedLink(l);
        if (!fixed) {
            [VGActions alert:@"That website doesn't look right" message:@"Type something like youtube.com or https://example.com/videos." from:self];
            return;
        }
        n = [n stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!n.length) {
            NSString *d = siteDomain(fixed);
            n = [[d componentsSeparatedByString:@"."].firstObject capitalizedString] ?: d;
        }
        done(n, fixed);
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)addFavorite {
    [self askFavoriteTitle:@"Add to Favorites" name:@"" link:@"" askName:YES askLink:YES done:^(NSString *name, NSString *link) {
        NSMutableArray *favs = [[self favorites] mutableCopy];
        [favs addObject:@{@"name": name, @"url": link}];
        [self saveFavorites:favs];
        [VGActions toast:[name stringByAppendingString:@" added"] icon:@"star.fill" in:self.view.window ?: self.view];
    }];
}

- (void)renameFavoriteAt:(NSUInteger)i {
    NSDictionary *f = [self favorites][i];
    [self askFavoriteTitle:@"Rename" name:f[@"name"] link:f[@"url"] askName:YES askLink:NO done:^(NSString *name, NSString *link) {
        NSMutableArray *favs = [[self favorites] mutableCopy];
        favs[i] = @{@"name": name, @"url": f[@"url"]};
        [self saveFavorites:favs];
    }];
}

- (void)editFavoriteAt:(NSUInteger)i {
    NSDictionary *f = [self favorites][i];
    [self askFavoriteTitle:@"Edit favorite" name:f[@"name"] link:f[@"url"] askName:YES askLink:YES done:^(NSString *name, NSString *link) {
        NSMutableArray *favs = [[self favorites] mutableCopy];
        favs[i] = @{@"name": name, @"url": link};
        [self saveFavorites:favs];
    }];
}

- (void)removeFavoriteAt:(NSUInteger)i {
    NSMutableArray *favs = [[self favorites] mutableCopy];
    NSString *name = favs[i][@"name"];
    [favs removeObjectAtIndex:i];
    [self saveFavorites:favs];
    [VGActions toast:[name stringByAppendingString:@" removed"] icon:@"star.slash" in:self.view.window ?: self.view];
}

- (void)moveFavoriteAt:(NSUInteger)i by:(NSInteger)delta {
    NSMutableArray *favs = [[self favorites] mutableCopy];
    NSInteger j = (NSInteger)i + delta;
    if (j < 0 || j >= (NSInteger)favs.count) return;
    [favs exchangeObjectAtIndex:i withObjectAtIndex:(NSUInteger)j];
    [self saveFavorites:favs];
}

/// Star in the address bar: add or remove the site you're on.
- (void)toggleStar {
    NSString *host = [self currentHost];
    if (!host) return;
    NSInteger idx = [self favoriteIndexForHost:host];
    if (idx != NSNotFound) { [self removeFavoriteAt:(NSUInteger)idx]; return; }
    NSString *d = siteDomain(host);
    NSString *title = [self.web.title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Page titles are often long ("Home - Site name"); keep the short part.
    for (NSString *sep in @[@" - ", @" | ", @" – ", @" · ", @": "]) {
        NSArray *parts = [title componentsSeparatedByString:sep];
        if (parts.count > 1) title = [parts.lastObject length] < [parts.firstObject length] ? parts.lastObject : parts.firstObject;
    }
    if (!title.length || title.length > 24) title = [[d componentsSeparatedByString:@"."].firstObject capitalizedString] ?: d;
    NSString *link = [NSString stringWithFormat:@"%@://%@", self.web.URL.scheme ?: @"https", self.web.URL.host];
    [self askFavoriteTitle:@"Add to Favorites" name:title link:link askName:YES askLink:NO done:^(NSString *name, NSString *l) {
        NSMutableArray *favs = [[self favorites] mutableCopy];
        [favs addObject:@{@"name": name, @"url": l}];
        [self saveFavorites:favs];
        [VGActions toast:[name stringByAppendingString:@" added to Favorites"] icon:@"star.fill" in:self.view.window ?: self.view];
    }];
}

- (void)updateStar {
    NSString *host = [self currentHost];
    BOOL fav = host && [self favoriteIndexForHost:host] != NSNotFound;
    [self.starButton setImage:[UIImage systemImageNamed:fav ? @"star.fill" : @"star"
                                       withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]
                     forState:UIControlStateNormal];
    self.starButton.tintColor = fav ? VGAccent : VGTertiary;
    self.starButton.accessibilityLabel = fav ? @"Remove from Favorites" : @"Add to Favorites";
    self.address.rightViewMode = host ? UITextFieldViewModeUnlessEditing : UITextFieldViewModeNever;
}

#pragma mark Start page

- (void)buildStartPageBelow:(UIView *)bar {
    UIScrollView *page = [UIScrollView new];
    page.backgroundColor = VGBackground;
    page.translatesAutoresizingMaskIntoConstraints = NO;
    page.alwaysBounceVertical = YES;
    page.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:page];

    UILabel *h = [UILabel new];
    h.text = @"Browse & download";
    h.font = VGFont(30, UIFontWeightHeavy);
    h.textColor = VGText;
    UILabel *sub = [UILabel new];
    sub.text = @"Open a site, play any video, and tap the pink Download button on it.";
    sub.font = VGFont(15, UIFontWeightRegular);
    sub.textColor = VGSecondary;
    sub.numberOfLines = 0;

    UILabel *favTitle = [UILabel new];
    favTitle.attributedText = [[NSAttributedString alloc] initWithString:@"FAVORITES" attributes:@{
        NSFontAttributeName: VGFont(12, UIFontWeightHeavy), NSForegroundColorAttributeName: VGTertiary, NSKernAttributeName: @1.0}];

    self.favGrid = [UIStackView new];
    self.favGrid.axis = UILayoutConstraintAxisVertical;
    self.favGrid.spacing = 16;

    UILabel *tip = [UILabel new];
    tip.text = @"Touch and hold a favorite to rename, edit, move or remove it. Tap the star in the address bar to save the site you're on.\\n\\nSign in to a site here to download videos that need an account. Your sign-ins stay on this iPhone.";
    tip.text = [tip.text stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
    tip.font = VGFont(13, UIFontWeightMedium);
    tip.textColor = VGTertiary;
    tip.numberOfLines = 0;

    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[h, sub, favTitle, self.favGrid, tip]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10;
    [s setCustomSpacing:26 afterView:sub];
    [s setCustomSpacing:14 afterView:favTitle];
    [s setCustomSpacing:26 afterView:self.favGrid];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [page addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [page.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [page.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [page.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [page.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [s.topAnchor constraintEqualToAnchor:page.contentLayoutGuide.topAnchor constant:24],
        [s.bottomAnchor constraintEqualToAnchor:page.contentLayoutGuide.bottomAnchor constant:-24],
        [s.leadingAnchor constraintEqualToAnchor:page.frameLayoutGuide.leadingAnchor constant:20],
        [s.trailingAnchor constraintEqualToAnchor:page.frameLayoutGuide.trailingAnchor constant:-20],
    ]];
    self.startPage = page;
    [self reloadFavorites];
}

- (void)reloadFavorites {
    for (UIView *v in self.favGrid.arrangedSubviews) { [self.favGrid removeArrangedSubview:v]; [v removeFromSuperview]; }
    NSArray *favs = [self favorites];
    NSMutableArray *tiles = [NSMutableArray array];
    for (NSUInteger i = 0; i < favs.count; i++) [tiles addObject:[self tileForFavorite:favs[i] index:i count:favs.count]];
    [tiles addObject:[self addTile]];
    for (NSUInteger r = 0; r < tiles.count; r += 4) {
        UIStackView *line = [UIStackView new];
        line.distribution = UIStackViewDistributionFillEqually;
        line.alignment = UIStackViewAlignmentTop;
        line.spacing = 12;
        for (NSUInteger i = r; i < r + 4; i++) [line addArrangedSubview:i < tiles.count ? tiles[i] : [UIView new]];
        [self.favGrid addArrangedSubview:line];
    }
}

/// Shared tile layout: a rounded "app icon" square with a name under it.
- (UIButton *)tileWithName:(NSString *)name box:(UIView **)boxOut {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    UIView *box = [UIView new];
    box.backgroundColor = VGSurface2;
    box.layer.cornerRadius = 15;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.clipsToBounds = YES;
    UILabel *label = [UILabel new];
    label.text = name;
    label.font = VGFont(12, UIFontWeightSemibold);
    label.textColor = VGSecondary;
    label.textAlignment = NSTextAlignmentCenter;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    for (UIView *v in @[box, label]) { v.translatesAutoresizingMaskIntoConstraints = NO; v.userInteractionEnabled = NO; [b addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [box.topAnchor constraintEqualToAnchor:b.topAnchor],
        [box.centerXAnchor constraintEqualToAnchor:b.centerXAnchor],
        [box.widthAnchor constraintEqualToConstant:60],
        [box.heightAnchor constraintEqualToConstant:60],
        [label.topAnchor constraintEqualToAnchor:box.bottomAnchor constant:7],
        [label.leadingAnchor constraintEqualToAnchor:b.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:b.trailingAnchor],
        [label.bottomAnchor constraintEqualToAnchor:b.bottomAnchor],
    ]];
    b.accessibilityLabel = name;
    *boxOut = box;
    return b;
}

- (UIView *)addTile {
    UIView *box = nil;
    UIButton *b = [self tileWithName:@"Add" box:&box];
    box.backgroundColor = UIColor.clearColor;
    CAShapeLayer *dash = [CAShapeLayer layer];
    dash.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(1, 1, 58, 58) cornerRadius:14].CGPath;
    dash.fillColor = UIColor.clearColor.CGColor;
    dash.strokeColor = VGTertiary.CGColor;
    dash.lineWidth = 1.5;
    dash.lineDashPattern = @[@5, @4];
    [box.layer addSublayer:dash];
    UIImageView *plus = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"plus" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]]];
    plus.tintColor = VGSecondary;
    plus.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:plus];
    [NSLayoutConstraint activateConstraints:@[
        [plus.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [plus.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
    ]];
    b.accessibilityLabel = @"Add favorite";
    [b addTarget:self action:@selector(addFavorite) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIView *)tileForFavorite:(NSDictionary *)fav index:(NSUInteger)i count:(NSUInteger)count {
    NSString *name = fav[@"name"] ?: @"Site";
    NSString *url = fav[@"url"] ?: @"";
    UIView *box = nil;
    UIButton *b = [self tileWithName:name box:&box];

    // Placeholder until the site's icon arrives: its first letter in a color picked from the site name.
    NSString *d = siteDomain(url);
    NSArray *colors = @[@0xE5484D, @0x2BB3C0, @0xD9338F, @0x8E8E99, @0x3E7BFA, @0xFF6A33, @0x3BB4E8, @0x4C6EF5, @0x30A46C, @0xF5A524];
    UIColor *tint = VGHex([colors[(NSUInteger)labs((long)d.hash) % colors.count] unsignedIntValue]);
    UILabel *initial = [UILabel new];
    initial.text = name.length ? [name substringToIndex:1].uppercaseString : @"?";
    initial.font = VGRounded(26, UIFontWeightHeavy);
    initial.textColor = tint;
    initial.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *icon = [UIImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.hidden = YES;
    [box addSubview:initial];
    [box addSubview:icon];
    NSLayoutConstraint *iw = [icon.widthAnchor constraintEqualToConstant:34], *ih = [icon.heightAnchor constraintEqualToConstant:34];
    [NSLayoutConstraint activateConstraints:@[
        [initial.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [initial.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        iw, ih,
    ]];
    [self loadSiteIcon:url done:^(UIImage *img, BOOL fill) {
        icon.image = img;
        icon.hidden = NO;
        initial.hidden = YES;
        if (fill) {
            // A full home-screen icon: let it fill the tile edge to edge.
            iw.constant = 60; ih.constant = 60;
            icon.contentMode = UIViewContentModeScaleAspectFill;
            box.backgroundColor = UIColor.clearColor;
        } else {
            // A small site icon: center it on a white tile, like Safari's favorites.
            iw.constant = 34; ih.constant = 34;
            icon.contentMode = UIViewContentModeScaleAspectFit;
            box.backgroundColor = UIColor.whiteColor;
        }
    }];

    [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [self open:url]; }] forControlEvents:UIControlEventTouchUpInside];

    // Touch and hold for options.
    __weak typeof(self) ws = self;
    NSMutableArray *items = [NSMutableArray arrayWithArray:@[
        [UIAction actionWithTitle:@"Rename" image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(UIAction *a) { [ws renameFavoriteAt:i]; }],
        [UIAction actionWithTitle:@"Edit link" image:[UIImage systemImageNamed:@"link"] identifier:nil handler:^(UIAction *a) { [ws editFavoriteAt:i]; }],
    ]];
    NSMutableArray *moves = [NSMutableArray array];
    if (i > 0) [moves addObject:[UIAction actionWithTitle:@"Move left" image:[UIImage systemImageNamed:@"arrow.left"] identifier:nil handler:^(UIAction *a) { [ws moveFavoriteAt:i by:-1]; }]];
    if (i + 1 < count) [moves addObject:[UIAction actionWithTitle:@"Move right" image:[UIImage systemImageNamed:@"arrow.right"] identifier:nil handler:^(UIAction *a) { [ws moveFavoriteAt:i by:1]; }]];
    UIAction *remove = [UIAction actionWithTitle:@"Remove" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *a) { [ws removeFavoriteAt:i]; }];
    remove.attributes = UIMenuElementAttributesDestructive;
    NSMutableArray *sections = [NSMutableArray arrayWithObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:items]];
    if (moves.count) [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:moves]];
    [sections addObject:remove];
    b.menu = [UIMenu menuWithTitle:name children:sections];
    b.showsMenuAsPrimaryAction = NO;   // tap opens the site; touch and hold shows the menu
    return b;
}

/// Gets a site's icon: its own home-screen icon first (sharp, made to fill a rounded square),
/// otherwise its regular site icon. Saved on the phone so it shows instantly next time.
- (void)loadSiteIcon:(NSString *)url done:(void (^)(UIImage *img, BOOL fill))done {
    NSString *d = siteDomain(url);
    NSString *host = [NSURL URLWithString:url].host ?: d;
    if (!d.length) return;
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"site-icons-v2"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *cache = [dir stringByAppendingPathComponent:[d stringByAppendingString:@".png"]];
    NSString *fillMark = [dir stringByAppendingPathComponent:[d stringByAppendingString:@".fill"]];
    UIImage *cached = [UIImage imageWithContentsOfFile:cache];
    if (cached) { done(cached, [NSFileManager.defaultManager fileExistsAtPath:fillMark]); return; }

    NSArray *sources = @[
        @[[NSString stringWithFormat:@"https://%@/apple-touch-icon.png", host], @YES],
        @[[NSString stringWithFormat:@"https://%@/apple-touch-icon.png", d], @YES],
        @[[NSString stringWithFormat:@"https://www.google.com/s2/favicons?domain=%@&sz=128", d], @NO],
        @[[NSString stringWithFormat:@"https://icons.duckduckgo.com/ip3/%@.ico", d], @NO],
    ];
    [self fetchIconFrom:sources index:0 cache:cache fillMark:fillMark done:done];
}

/// True if the image's corners are solid (a full icon), false if transparent (a logo shape).
static BOOL cornersOpaque(UIImage *img) {
    CGImageRef cg = img.CGImage;
    if (!cg) return NO;
    uint8_t px[8 * 8 * 4] = {0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(px, 8, 8, 8, 32, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!c) return NO;
    CGContextDrawImage(c, CGRectMake(0, 0, 8, 8), cg);
    CGContextRelease(c);
    int idx[] = {0, 7, 56, 63};
    for (int k = 0; k < 4; k++) if (px[idx[k] * 4 + 3] < 200) return NO;
    return YES;
}

- (void)fetchIconFrom:(NSArray *)sources index:(NSUInteger)i cache:(NSString *)cache fillMark:(NSString *)fillMark
                 done:(void (^)(UIImage *, BOOL))done {
    if (i >= sources.count) return;
    NSString *src = sources[i][0];
    BOOL touchIcon = [sources[i][1] boolValue];
    [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:src] completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        NSInteger status = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 200;
        UIImage *img = (data && status < 400) ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            CGFloat px = img.size.width * img.scale;
            if (!img || px < (touchIcon ? 96 : 32)) {   // missing, or a tiny generic placeholder
                [self fetchIconFrom:sources index:i + 1 cache:cache fillMark:fillMark done:done];
                return;
            }
            BOOL fill = touchIcon && cornersOpaque(img);
            [UIImagePNGRepresentation(img) writeToFile:cache atomically:YES];
            if (fill) [NSData.data writeToFile:fillMark atomically:YES];
            done(img, fill);
        });
    }] resume];
}

#pragma mark Floating button

- (void)buildFab {
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration];
    c.baseBackgroundColor = VGAccent;
    c.baseForegroundColor = UIColor.whiteColor;
    c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    c.image = [UIImage systemImageNamed:@"arrow.down.to.line" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold]];
    c.imagePadding = 7;
    c.contentInsets = NSDirectionalEdgeInsetsMake(13, 18, 13, 20);
    c.attributedTitle = [[NSAttributedString alloc] initWithString:@"Download" attributes:@{NSFontAttributeName: VGFont(15, UIFontWeightBold)}];
    self.fab = [UIButton buttonWithConfiguration:c primaryAction:nil];
    self.fab.layer.shadowColor = UIColor.blackColor.CGColor;
    self.fab.layer.shadowOpacity = 0.5;
    self.fab.layer.shadowRadius = 12;
    self.fab.layer.shadowOffset = CGSizeMake(0, 4);
    self.fab.translatesAutoresizingMaskIntoConstraints = NO;
    [self.fab addTarget:self action:@selector(fabTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.fab];

    self.fabBar = [VGProgressBar new];
    self.fabBar.userInteractionEnabled = NO;
    self.fabBar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
    self.fabBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.fabBar.hidden = YES;
    [self.fab addSubview:self.fabBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.fab.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.fab.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [self.fabBar.leadingAnchor constraintEqualToAnchor:self.fab.leadingAnchor constant:18],
        [self.fabBar.trailingAnchor constraintEqualToAnchor:self.fab.trailingAnchor constant:-18],
        [self.fabBar.bottomAnchor constraintEqualToAnchor:self.fab.bottomAnchor constant:-6],
        [self.fabBar.heightAnchor constraintEqualToConstant:3],
    ]];
    self.fabBadge = [UILabel new];
    self.fabBadge.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightHeavy];
    self.fabBadge.textColor = VGAccent;
    self.fabBadge.backgroundColor = UIColor.whiteColor;
    self.fabBadge.textAlignment = NSTextAlignmentCenter;
    self.fabBadge.layer.cornerRadius = 11;
    self.fabBadge.clipsToBounds = YES;
    self.fabBadge.hidden = YES;
    self.fabBadge.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.fabBadge];
    [NSLayoutConstraint activateConstraints:@[
        [self.fabBadge.centerXAnchor constraintEqualToAnchor:self.fab.trailingAnchor constant:-6],
        [self.fabBadge.centerYAnchor constraintEqualToAnchor:self.fab.topAnchor constant:4],
        [self.fabBadge.heightAnchor constraintEqualToConstant:22],
        [self.fabBadge.widthAnchor constraintGreaterThanOrEqualToConstant:22],
    ]];
    self.fab.hidden = YES;
}

- (void)setFabTitle:(NSString *)title icon:(NSString *)icon {
    UIButtonConfiguration *c = self.fab.configuration;
    c.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: VGFont(15, UIFontWeightBold)}];
    c.image = [UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold]];
    self.fab.configuration = c;
}

static BOOL looksLikeVideoPage(NSURL *u) {
    if (!u) return NO;
    NSString *s = u.absoluteString.lowercaseString;
    NSArray *patterns = @[@"youtube\\.com/(watch|shorts/|live/|embed/)", @"youtu\\.be/", @"tiktok\\.com/@[^/]+/video/",
                          @"instagram\\.com/(p|reel|reels|tv)/", @"(x|twitter)\\.com/[^/]+/status/", @"facebook\\.com/.*(watch|videos|reel)",
                          @"fb\\.watch/", @"vimeo\\.com/\\d+", @"reddit\\.com/r/[^/]+/comments/", @"dailymotion\\.com/video/",
                          @"twitch\\.tv/(videos/|[^/]+/clip/)", @"soundcloud\\.com/[^/]+/[^/]+"];
    for (NSString *p in patterns) {
        if ([s rangeOfString:p options:NSRegularExpressionSearch].location != NSNotFound) return YES;
    }
    return NO;
}

- (void)refreshFab {
    BOOL downloading = [VGEngine shared].activeCount > 0;
    BOOL onSite = self.startPage.hidden && [self.web.URL.scheme hasPrefix:@"http"];
    // The lower Download button is retired; the button on the video does the job.
    BOOL show = NO;
    (void)downloading; (void)onSite;
    self.fabBadge.hidden = !show || [VGEngine shared].activeCount < 2;
    if (show == !self.fab.hidden) return;
    if (show) {
        self.fab.hidden = NO;
        self.fab.alpha = 0;
        self.fab.transform = CGAffineTransformMakeScale(0.8, 0.8);
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0
                         animations:^{ self.fab.alpha = 1; self.fab.transform = CGAffineTransformIdentity; } completion:nil];
    } else {
        [UIView animateWithDuration:0.2 animations:^{ self.fab.alpha = 0; } completion:^(BOOL f) { self.fab.hidden = YES; }];
    }
}

- (void)fabTapped {
    BOOL onSite = self.startPage.hidden && self.web.URL;
    // On a video page the button always offers a new download; otherwise it shows your downloads.
    if (onSite && (self.pageHasVideo || self.captured.count || looksLikeVideoPage(self.web.URL))) {
        [self showSheetFor:self.web.URL.absoluteString fallback:nil];
    } else if ([VGEngine shared].activeCount) {
        self.tabBarController.selectedIndex = 2;
    }
}

- (void)showSheetFor:(NSString *)page fallback:(NSString *)src {
    if (self.presentedViewController) return;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    NSString *fallback = ([src hasPrefix:@"http"]) ? src : nil;  // blob: links can't be downloaded directly
    VGQualitySheet *sheet = [[VGQualitySheet alloc] initWithURL:page fallbackURL:fallback];
    sheet.candidates = [self candidateList];
    sheet.fromBrowser = YES;
    [sheet presentFrom:self];
}

- (void)tasksChanged {
    VGEngine *e = [VGEngine shared];
    VGTask *lead = e.leadTask;
    NSUInteger n = e.activeCount;
    if (n && lead) {
        self.fabBar.hidden = NO;
        [self.fabBar setProgress:lead.fraction animated:YES];
        [self setFabTitle:[NSString stringWithFormat:@"%d%%", (int)round(lead.fraction * 100)] icon:@"arrow.down.circle"];
    } else {
        self.fabBar.hidden = YES;
        [self setFabTitle:@"Download" icon:@"arrow.down.to.line"];
    }
    self.fabBadge.text = [NSString stringWithFormat:@" %lu ", (unsigned long)n];
    [self refreshFab];
}

- (void)taskFinished:(NSNotification *)n {
    VGTask *t = n.object;
    [self tasksChanged];
    if (t.item && self.view.window && !self.presentedViewController && self.tabBarController.selectedViewController == self.navigationController) {
        [VGActions toast:@"Saved to Downloads" icon:@"checkmark.circle.fill" in:self.view.window];
    }
}

#pragma mark Navigation

- (void)open:(NSString *)text {
    NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!t.length) return;
    NSURL *url = nil;
    if ([t hasPrefix:@"http://"] || [t hasPrefix:@"https://"]) url = [NSURL URLWithString:t];
    else if (![t containsString:@" "] && [t containsString:@"."]) url = [NSURL URLWithString:[@"https://" stringByAppendingString:t]];
    if (!url) {
        NSURLComponents *c = [NSURLComponents componentsWithString:@"https://www.google.com/search"];
        c.queryItems = @[[NSURLQueryItem queryItemWithName:@"q" value:t]];
        url = c.URL;
    }
    if (!self.isViewLoaded) [self loadViewIfNeeded];
    self.startPage.hidden = YES;
    [self.web loadRequest:[NSURLRequest requestWithURL:url]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    NSString *typed = [tf.text copy];   // read first: ending editing resets the field
    [self open:typed];
    [tf resignFirstResponder];
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)tf {
    if (self.web.URL) tf.text = self.web.URL.absoluteString;
    dispatch_async(dispatch_get_main_queue(), ^{ [tf selectAll:nil]; });
}

- (void)textFieldDidEndEditing:(UITextField *)tf { [self updateAddress]; }

- (void)goBack {
    if (self.web.canGoBack) [self.web goBack];
    else [self closeSite];
}

/// Leaves the current site and returns to the browser's start page.
- (void)closeSite {
    [self.address resignFirstResponder];
    [self.web stopLoading];
    [self.web evaluateJavaScript:@"document.querySelectorAll('video').forEach(function(v){v.pause()})" completionHandler:nil];
    [self.web loadHTMLString:@"<html><body style='background:#0A0A0D'></body></html>" baseURL:nil];
    self.startPage.hidden = NO;
    self.startPage.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ self.startPage.alpha = 1; }];
    self.pageHasVideo = NO;
    [self.captured removeAllObjects]; self.activeStream = nil; self.playingSrc = nil;
    self.address.text = @"";
    [self refreshFab];
    [self updateButtons];
    [self updateStar];
}
- (void)reloadOrStop { if (self.web.isLoading) [self.web stopLoading]; else [self.web reload]; }

- (void)updateAddress {
    if (self.address.isEditing) return;
    NSString *host = self.web.URL.host;
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    if ([host hasPrefix:@"m."]) host = [host substringFromIndex:2];
    self.address.text = (self.startPage.hidden && host) ? host : @"";
}

- (void)updateButtons {
    BOOL onSite = self.startPage.hidden;
    self.closeButton.hidden = !onSite;
    self.shieldButton.hidden = !onSite;
    self.backButton.hidden = !onSite;
    self.backButton.enabled = onSite;
    UIImage *img = [UIImage systemImageNamed:self.web.isLoading ? @"xmark" : @"arrow.clockwise"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]];
    [self.reloadButton setImage:img forState:UIControlStateNormal];
    self.reloadButton.enabled = self.startPage.hidden;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        double p = self.web.estimatedProgress;
        self.loadBar.hidden = p >= 1.0;
        [self.loadBar setProgress:(float)p animated:p > self.loadBar.progress];
    } else if ([keyPath isEqualToString:@"URL"]) {
        self.pageHasVideo = NO;
        [self updateAddress];
        [self refreshFab];
        [self updateShield];
        [self updateStar];
    }
    [self updateButtons];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [self.captured removeAllObjects]; self.activeStream = nil; self.playingSrc = nil;   // a new page: what the last one played no longer applies
    [self updateButtons];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation { [self updateButtons]; [self updateAddress]; }
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self updateButtons]; }

// Links that open a new window load in this tab instead.
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if (!action.targetFrame.isMainFrame && action.request.URL) [webView loadRequest:action.request];
    return nil;
}

// Keep app-store and app links (like youtube:// ) from leaving the browser silently.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSString *scheme = action.request.URL.scheme.lowercaseString;
    if (action.targetFrame.isMainFrame && [scheme hasPrefix:@"http"]) {
        NSString *host = action.request.URL.host;
        if (![host isEqualToString:self.appliedHost]) [self applyRulesForHost:host];
    }
    if (scheme && ![@[@"http", @"https", @"about", @"data", @"blob"] containsObject:scheme]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark Streams caught while the page plays

/// A page asked for a video stream (playlist, manifest or whole file). Kept with the details the page's own player
/// used, so the download can ask for it the same way: the page it came from (Referer) and the browser name.
- (void)noteMedia:(NSDictionary *)m {
    NSString *url = [m[@"url"] isKindOfClass:NSString.class] ? m[@"url"] : nil;
    if (![url hasPrefix:@"http"]) return;
    for (NSDictionary *c in self.captured) if ([c[@"url"] isEqualToString:url]) return;
    NSString *kind = [m[@"kind"] isKindOfClass:NSString.class] ? m[@"kind"] : @"file";
    NSString *frame = [m[@"frame"] isKindOfClass:NSString.class] ? m[@"frame"] : (self.web.URL.absoluteString ?: @"");
    NSString *ua = [m[@"ua"] isKindOfClass:NSString.class] ? m[@"ua"] : @"";
    NSURL *mediaURL = [NSURL URLWithString:url];
    NSURL *frameURL = [NSURL URLWithString:frame];
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (frame.length) headers[@"Referer"] = frame;
    if (frameURL.scheme.length && frameURL.host.length) {
        headers[@"Origin"] = [NSString stringWithFormat:@"%@://%@%@", frameURL.scheme, frameURL.host,
                              frameURL.port ? [NSString stringWithFormat:@":%@", frameURL.port] : @""];
    }
    if (ua.length) headers[@"User-Agent"] = ua;
    long long size = [m[@"size"] respondsToSelector:@selector(longLongValue)] ? [m[@"size"] longLongValue] : 0;
    NSString *title = [m[@"title"] isKindOfClass:NSString.class] ? m[@"title"] : @"";
    NSString *host = mediaURL.host ?: @"";
    NSString *last = mediaURL.lastPathComponent.length > 1 ? mediaURL.lastPathComponent : @"";
    NSString *what = [kind isEqualToString:@"hls"] ? @"Stream" : ([kind isEqualToString:@"dash"] ? @"Stream (DASH)" : @"Video file");
    NSMutableString *label = [NSMutableString stringWithString:what];
    if (size > 500000) [label appendFormat:@" · %@", [NSByteCountFormatter stringFromByteCount:size countStyle:NSByteCountFormatterCountStyleFile]];
    [label appendFormat:@" · %@", last.length && last.length < 28 ? last : host];
    [self.captured addObject:@{@"url": url, @"kind": kind, @"headers": headers, @"title": title, @"page": frame, @"label": label}];
    while (self.captured.count > 12) [self.captured removeObjectAtIndex:0];
    [VGCrash breadcrumb:[NSString stringWithFormat:@"caught %@ %@", kind, host]];
    [self refreshFab];
}

/// What the sheet may try when the page link itself isn't understood: playlists first, then whole files,
/// the newest of each first, at most six.
- (NSArray<NSDictionary *> *)candidateList {
    // The video that is playing comes first: the stream whose pieces the page is fetching, or the video element's own address.
    // The rest follow, streams before plain files.
    NSArray *sorted = [[self.captured reverseObjectEnumerator].allObjects sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger (^rank)(NSDictionary *) = ^NSInteger(NSDictionary *d) {
            NSString *u = d[@"url"];
            if (self.activeStream.length && [u isEqualToString:self.activeStream]) return -2;
            if (self.playingSrc.length && [u isEqualToString:self.playingSrc]) return -1;
            return [d[@"kind"] isEqualToString:@"hls"] ? 0 : ([d[@"kind"] isEqualToString:@"file"] ? 1 : 2);
        };
        NSInteger ra = rank(a), rb = rank(b);
        return ra < rb ? NSOrderedAscending : (ra > rb ? NSOrderedDescending : NSOrderedSame);
    }];
    return sorted.count > 6 ? [sorted subarrayWithRange:NSMakeRange(0, 6)] : sorted;
}

#pragma mark Messages from the page

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:NSDictionary.class]) return;
    NSDictionary *m = message.body;
    NSString *type = m[@"type"];
    if ([type isEqualToString:@"state"]) {
        if (message.frameInfo.isMainFrame || [m[@"hasVideo"] boolValue]) {
            NSString *src = [m[@"src"] isKindOfClass:NSString.class] ? m[@"src"] : @"";
            if ([m[@"hasVideo"] boolValue] && [src hasPrefix:@"http"]) self.playingSrc = src;
            self.pageHasVideo = [m[@"hasVideo"] boolValue];
            [self refreshFab];
        }
    } else if ([type isEqualToString:@"active"]) {
        NSString *u = [m[@"url"] isKindOfClass:NSString.class] ? m[@"url"] : nil;
        if ([u hasPrefix:@"http"]) self.activeStream = u;
    } else if ([type isEqualToString:@"media"]) {
        [self noteMedia:m];
    } else if ([type isEqualToString:@"download"]) {
        NSString *page = m[@"page"];
        // A video inside an embedded frame: prefer the frame's own page link if it is a known video site.
        NSString *top = self.web.URL.absoluteString;
        NSString *target = (message.frameInfo.isMainFrame || !page.length) ? (top ?: page) : page;
        [self showSheetFor:target fallback:m[@"src"]];
    }
}

@end
