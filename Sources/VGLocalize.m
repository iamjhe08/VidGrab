#import "VGLocalize.h"
#import "VGTheme.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kKey = @"vgLanguage";
static NSString *gCode = nil;                         // active language code
static NSDictionary<NSString *, NSString *> *gExact;  // English -> translated
static NSArray<NSDictionary *> *gTemplates;           // {re, out, n} for strings with %@ %d ...
static NSCache *gCache;
static NSInteger gEpoch;

@implementation VGLocalize

+ (NSArray<NSString *> *)choices { return @[@"auto", @"en", @"zh-Hans", @"es", @"pt", @"ru", @"id", @"ja", @"hi", @"ar"]; }

+ (NSString *)nameForChoice:(NSString *)c {
    if ([c isEqualToString:@"en"]) return @"English";
    if ([c isEqualToString:@"zh-Hans"]) return @"简体中文";
    if ([c isEqualToString:@"es"]) return @"Español";
    if ([c isEqualToString:@"pt"]) return @"Português";
    if ([c isEqualToString:@"ru"]) return @"Русский";
    if ([c isEqualToString:@"id"]) return @"Bahasa Indonesia";
    if ([c isEqualToString:@"ja"]) return @"日本語";
    if ([c isEqualToString:@"hi"]) return @"हिन्दी";
    if ([c isEqualToString:@"ar"]) return @"العربية";
    return @"Auto";
}

+ (NSString *)choice {
    NSString *s = [NSUserDefaults.standardUserDefaults stringForKey:kKey];
    return [self.choices containsObject:s] ? s : @"auto";
}

+ (void)setChoice:(NSString *)choice {
    [NSUserDefaults.standardUserDefaults setObject:choice forKey:kKey];
    [self reload];
}

+ (NSString *)phoneLanguage {
    NSString *l = NSLocale.preferredLanguages.firstObject ?: @"en";
    if ([l hasPrefix:@"zh"]) return @"zh-Hans";
    for (NSString *c in @[@"es", @"pt", @"ru", @"id", @"ja", @"hi", @"ar"]) if ([l hasPrefix:c]) return c;
    if ([l hasPrefix:@"in"]) return @"id";
    return @"en";
}

+ (NSString *)activeCode { return gCode ?: @"en"; }

+ (void)reload {
    NSString *c = self.choice;
    gCode = [c isEqualToString:@"auto"] ? [self phoneLanguage] : c;
    gExact = nil; gTemplates = nil; gCache = [NSCache new]; gEpoch++;
    if ([gCode isEqualToString:@"en"]) return;
    NSString *path = [NSBundle.mainBundle pathForResource:gCode ofType:@"json" inDirectory:@"lang"] ?: [NSBundle.mainBundle pathForResource:gCode ofType:@"json"];
    NSData *d = path ? [NSData dataWithContentsOfFile:path] : nil;
    NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    if (![j isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *exact = [NSMutableDictionary dictionary];
    NSMutableArray *temps = [NSMutableArray array];
    NSRegularExpression *spec = [NSRegularExpression regularExpressionWithPattern:@"%(?:\\.\\d+)?(?:ld|lu|lld|d|@|s|g|f)" options:0 error:nil];
    [j enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        if (![v isKindOfClass:NSString.class] || !v.length) return;
        if ([spec numberOfMatchesInString:k options:0 range:NSMakeRange(0, k.length)] == 0) { exact[k] = v; return; }
        // build a pattern: literal text stays, each %-spec becomes a capture
        NSMutableString *pat = [NSMutableString stringWithString:@"^"];
        NSUInteger pos = 0; NSInteger n = 0;
        for (NSTextCheckingResult *m in [spec matchesInString:k options:0 range:NSMakeRange(0, k.length)]) {
            [pat appendString:[NSRegularExpression escapedPatternForString:[k substringWithRange:NSMakeRange(pos, m.range.location - pos)]]];
            NSString *t = [k substringWithRange:m.range];
            [pat appendString:([t hasSuffix:@"d"] ? @"(-?\\d+)" : @"([\\s\\S]*?)")];
            pos = NSMaxRange(m.range); n++;
        }
        [pat appendString:[NSRegularExpression escapedPatternForString:[k substringFromIndex:pos]]];
        [pat appendString:@"$"];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:nil];
        if (re) [temps addObject:@{@"re": re, @"out": v, @"n": @(n), @"len": @(k.length)}];
    }];
    [temps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"len"] compare:a[@"len"]]; }];
    gExact = exact; gTemplates = temps;
}

+ (NSString *)translate:(NSString *)s {
    if (![s isKindOfClass:NSString.class] || s.length < 2 || !gExact) return s;
    NSString *hit = gExact[s];
    if (hit) return hit;
    NSString *cached = [gCache objectForKey:s];
    if (cached) return cached == (id)NSNull.null ? s : cached;
    NSString *out = nil;
    for (NSDictionary *t in gTemplates) {
        NSRegularExpression *re = t[@"re"];
        NSTextCheckingResult *m = [re firstMatchInString:s options:NSMatchingAnchored range:NSMakeRange(0, s.length)];
        if (!m || m.range.length != s.length) continue;
        NSMutableString *r = [NSMutableString stringWithString:t[@"out"]];
        NSRegularExpression *spec = [NSRegularExpression regularExpressionWithPattern:@"%(?:\\.\\d+)?(?:ld|lu|lld|d|@|s|g|f)" options:0 error:nil];
        NSArray *ms = [spec matchesInString:r options:0 range:NSMakeRange(0, r.length)];
        for (NSInteger i = (NSInteger)ms.count - 1; i >= 0; i--) {
            NSInteger g = i + 1;
            NSString *cap = g < (NSInteger)m.numberOfRanges ? [s substringWithRange:[m rangeAtIndex:g]] : @"";
            [r replaceCharactersInRange:[ms[i] range] withString:[self translate:cap]];
        }
        out = r; break;
    }
    [gCache setObject:out ?: (id)NSNull.null forKey:s];
    return out ?: s;
}

+ (void)presentPickerFrom:(UIViewController *)vc source:(UIView *)source done:(void (^)(void))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Language" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *ch in self.choices) {
        NSString *name = [ch isEqualToString:@"auto"] ? [self translate:@"Auto (phone language)"] : [self nameForChoice:ch];
        if ([ch isEqualToString:self.choice]) name = [name stringByAppendingString:@" \u2713"];
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            if ([ch isEqualToString:self.choice]) return;
            [self setChoice:ch];
            [NSNotificationCenter.defaultCenter postNotificationName:VGThemeDidChangeNotification object:nil];
            if (done) done();
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = source;
    a.popoverPresentationController.sourceRect = source.bounds;
    [vc presentViewController:a animated:YES completion:nil];
}

+ (NSAttributedString *)translateAttributed:(NSAttributedString *)a {
    if (!a.length || !gExact) return a;
    NSString *t = [self translate:a.string];
    if ([t isEqualToString:a.string]) return a;
    NSMutableAttributedString *m = [a mutableCopy];
    [m replaceCharactersInRange:NSMakeRange(0, m.length) withString:t];
    return m;
}

static void swizzle(Class c, SEL orig, SEL repl, BOOL meta) {
    Class k = meta ? object_getClass(c) : c;
    Method a = class_getInstanceMethod(k, orig), b = class_getInstanceMethod(k, repl);
    if (a && b) method_exchangeImplementations(a, b);
}

+ (void)start {
    [self reload];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        swizzle(UILabel.class, @selector(setText:), @selector(vgl_setText:), NO);
        swizzle(UILabel.class, @selector(setAttributedText:), @selector(vgl_setAttributedText:), NO);
        swizzle(UIButton.class, @selector(setTitle:forState:), @selector(vgl_setTitle:forState:), NO);
        swizzle(UIButton.class, @selector(setAttributedTitle:forState:), @selector(vgl_setAttributedTitle:forState:), NO);
        swizzle(UIButton.class, @selector(setConfiguration:), @selector(vgl_setConfiguration:), NO);
        swizzle(UITextField.class, @selector(setPlaceholder:), @selector(vgl_setPlaceholder:), NO);
        swizzle(UISearchBar.class, @selector(setPlaceholder:), @selector(vgl_setPlaceholder:), NO);
        swizzle(UINavigationItem.class, @selector(setTitle:), @selector(vgl_setTitle:), NO);
        swizzle(UIViewController.class, @selector(setTitle:), @selector(vgl_setTitle:), NO);
        swizzle(UITabBarItem.class, @selector(setTitle:), @selector(vgl_setTitle:), NO);
        swizzle(UIBarButtonItem.class, @selector(setTitle:), @selector(vgl_setTitle:), NO);
        swizzle(UISegmentedControl.class, @selector(setTitle:forSegmentAtIndex:), @selector(vgl_setTitle:forSegmentAtIndex:), NO);
        swizzle(UIAlertController.class, @selector(alertControllerWithTitle:message:preferredStyle:), @selector(vgl_alertWithTitle:message:preferredStyle:), YES);
        swizzle(UIAlertAction.class, @selector(actionWithTitle:style:handler:), @selector(vgl_actionWithTitle:style:handler:), YES);
        swizzle(UIAction.class, @selector(actionWithTitle:image:identifier:handler:), @selector(vgl_actionWithTitle:image:identifier:handler:), YES);
        swizzle(UIMenu.class, @selector(menuWithTitle:image:identifier:options:children:), @selector(vgl_menuWithTitle:image:identifier:options:children:), YES);
    });
}

@end

@implementation UILabel (VGL)
- (void)vgl_setText:(NSString *)t { [self vgl_setText:[VGLocalize translate:t]]; }
- (void)vgl_setAttributedText:(NSAttributedString *)t { [self vgl_setAttributedText:[VGLocalize translateAttributed:t]]; }
@end

@implementation UIButton (VGL)
- (void)vgl_setTitle:(NSString *)t forState:(UIControlState)s { [self vgl_setTitle:[VGLocalize translate:t] forState:s]; }
- (void)vgl_setAttributedTitle:(NSAttributedString *)t forState:(UIControlState)s { [self vgl_setAttributedTitle:[VGLocalize translateAttributed:t] forState:s]; }
- (void)vgl_setConfiguration:(UIButtonConfiguration *)c {
    if (c) {
        if (c.title) c.title = [VGLocalize translate:c.title];
        if (c.attributedTitle) c.attributedTitle = [VGLocalize translateAttributed:c.attributedTitle];
        if (c.subtitle) c.subtitle = [VGLocalize translate:c.subtitle];
    }
    [self vgl_setConfiguration:c];
}
@end

@implementation UITextField (VGL)
- (void)vgl_setPlaceholder:(NSString *)t { [self vgl_setPlaceholder:[VGLocalize translate:t]]; }
@end
@implementation UISearchBar (VGL)
- (void)vgl_setPlaceholder:(NSString *)t { [self vgl_setPlaceholder:[VGLocalize translate:t]]; }
@end
@implementation UINavigationItem (VGL)
- (void)vgl_setTitle:(NSString *)t { [self vgl_setTitle:[VGLocalize translate:t]]; }
@end
@implementation UIViewController (VGL)
- (void)vgl_setTitle:(NSString *)t { [self vgl_setTitle:[VGLocalize translate:t]]; }
@end
@implementation UITabBarItem (VGL)
- (void)vgl_setTitle:(NSString *)t { [self vgl_setTitle:[VGLocalize translate:t]]; }
@end
@implementation UIBarButtonItem (VGL)
- (void)vgl_setTitle:(NSString *)t { [self vgl_setTitle:[VGLocalize translate:t]]; }
@end
@implementation UISegmentedControl (VGL)
- (void)vgl_setTitle:(NSString *)t forSegmentAtIndex:(NSUInteger)i { [self vgl_setTitle:[VGLocalize translate:t] forSegmentAtIndex:i]; }
@end
@implementation UIAlertController (VGL)
+ (instancetype)vgl_alertWithTitle:(NSString *)t message:(NSString *)m preferredStyle:(UIAlertControllerStyle)s {
    return [self vgl_alertWithTitle:[VGLocalize translate:t] message:[VGLocalize translate:m] preferredStyle:s];
}
@end
@implementation UIAlertAction (VGL)
+ (instancetype)vgl_actionWithTitle:(NSString *)t style:(UIAlertActionStyle)s handler:(void (^)(UIAlertAction *))h {
    return [self vgl_actionWithTitle:[VGLocalize translate:t] style:s handler:h];
}
@end
@implementation UIAction (VGL)
+ (instancetype)vgl_actionWithTitle:(NSString *)t image:(UIImage *)i identifier:(UIActionIdentifier)id handler:(UIActionHandler)h {
    return [self vgl_actionWithTitle:[VGLocalize translate:t] image:i identifier:id handler:h];
}
@end
@implementation UIMenu (VGL)
+ (instancetype)vgl_menuWithTitle:(NSString *)t image:(UIImage *)i identifier:(UIMenuIdentifier)id options:(UIMenuOptions)o children:(NSArray<UIMenuElement *> *)c {
    return [self vgl_menuWithTitle:[VGLocalize translate:t] image:i identifier:id options:o children:c];
}
@end

