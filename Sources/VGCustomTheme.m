#import "VGCustomTheme.h"
#import "VGTheme.h"
#import <CoreImage/CoreImage.h>

#pragma mark Colors

NSString *VGHexString(unsigned hex) { return [NSString stringWithFormat:@"#%06X", hex & 0xFFFFFF]; }

BOOL VGParseHex(NSString *text, unsigned *out) {
    NSString *t = [[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([t hasPrefix:@"#"]) t = [t substringFromIndex:1];
    if (t.length == 3) t = [NSString stringWithFormat:@"%C%C%C%C%C%C", [t characterAtIndex:0], [t characterAtIndex:0], [t characterAtIndex:1], [t characterAtIndex:1], [t characterAtIndex:2], [t characterAtIndex:2]];
    if (t.length != 6) return NO;
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet];
    if ([t rangeOfCharacterFromSet:bad].location != NSNotFound) return NO;
    unsigned v = 0;
    if (![[NSScanner scannerWithString:t] scanHexInt:&v]) return NO;
    if (out) *out = v;
    return YES;
}

unsigned VGHexOf(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [c getRed:&r green:&g blue:&b alpha:&a];
    return ((unsigned)lround(r * 255) << 16) | ((unsigned)lround(g * 255) << 8) | (unsigned)lround(b * 255);
}

UIColor *VGMixColors(UIColor *a, UIColor *b, CGFloat t) {
    CGFloat r1 = 0, g1 = 0, b1 = 0, r2 = 0, g2 = 0, b2 = 0, al = 0;
    [a getRed:&r1 green:&g1 blue:&b1 alpha:&al]; [b getRed:&r2 green:&g2 blue:&b2 alpha:&al];
    return [UIColor colorWithRed:r1 + (r2 - r1) * t green:g1 + (g2 - g1) * t blue:b1 + (b2 - b1) * t alpha:1];
}

static NSString *const kThemesKey = @"vgCustomThemes";
static NSString *const kActiveKey = @"vgActiveCustomTheme";

static BOOL ValidMode(NSString *m) { return [@[@"color", @"gradient", @"photo", @"texture"] containsObject:m]; }
NSArray<NSString *> *VGTextureIDs(void) { return @[@"carbon", @"noise", @"grid", @"dots", @"lines"]; }
NSString *VGTextureTitle(NSString *i) {
    return @{@"carbon": @"Carbon fiber", @"noise": @"Subtle noise", @"grid": @"Grid", @"dots": @"Dots", @"lines": @"Diagonal lines"}[i] ?: @"Subtle noise";
}

#pragma mark Spec

@implementation VGThemeSpec

- (instancetype)init {
    if ((self = [super init])) {
        _identifier = NSUUID.UUID.UUIDString; _name = @"My Theme"; _base = 0;
        _accent = 0xFF3D68; _bgColor = 0x0A0A0D; _grad1 = 0x1B1033; _grad2 = 0x0A0A0D;
        _bgMode = @"color"; _gradDirection = 0; _texture = @"noise"; _dim = 0.35; _blur = 0;
        _overrides = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (instancetype)specFromPreset:(NSInteger)preset {
    NSArray<VGPalette *> *all = VGPalette.all;
    if (preset < 0 || preset >= (NSInteger)all.count || preset == VGCustomThemeSlot) preset = 0;
    VGPalette *p = all[preset];
    VGThemeSpec *s = [VGThemeSpec new];
    s.base = preset;
    s.accent = VGHexOf(p.accent);
    s.bgColor = VGHexOf(p.background);
    s.grad1 = VGHexOf(VGMixColors(p.background, p.accent, 0.22)); s.grad2 = VGHexOf(p.background);
    if (p.carbon) { s.bgMode = @"texture"; s.texture = @"carbon"; }
    return s;
}

static unsigned HexFrom(id v, unsigned fallback) {
    unsigned h = fallback;
    if ([v isKindOfClass:NSString.class] && VGParseHex(v, &h)) return h;
    return fallback;
}

+ (instancetype)specFromDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    VGThemeSpec *s = [VGThemeSpec new];
    if ([d[@"id"] isKindOfClass:NSString.class] && [d[@"id"] length]) s.identifier = d[@"id"];
    if ([d[@"name"] isKindOfClass:NSString.class] && [d[@"name"] length]) s.name = [d[@"name"] substringToIndex:MIN(40, [d[@"name"] length])];
    NSInteger base = [d[@"base"] isKindOfClass:NSNumber.class] ? [d[@"base"] integerValue] : 0;
    s.base = (base >= 0 && base < (NSInteger)VGPalette.all.count && base != VGCustomThemeSlot) ? base : 0;
    s.accent = HexFrom(d[@"accent"], s.accent);
    NSDictionary *bg = [d[@"background"] isKindOfClass:NSDictionary.class] ? d[@"background"] : @{};
    if ([bg[@"mode"] isKindOfClass:NSString.class] && ValidMode(bg[@"mode"])) s.bgMode = bg[@"mode"];
    s.bgColor = HexFrom(bg[@"color"], s.bgColor);
    NSDictionary *g = [bg[@"gradient"] isKindOfClass:NSDictionary.class] ? bg[@"gradient"] : @{};
    s.grad1 = HexFrom(g[@"c1"], s.grad1); s.grad2 = HexFrom(g[@"c2"], s.grad2);
    if ([g[@"direction"] isKindOfClass:NSNumber.class]) s.gradDirection = MAX(0, MIN(3, [g[@"direction"] integerValue]));
    if ([bg[@"texture"] isKindOfClass:NSString.class] && [VGTextureIDs() containsObject:bg[@"texture"]]) s.texture = bg[@"texture"];
    NSDictionary *ph = [bg[@"photo"] isKindOfClass:NSDictionary.class] ? bg[@"photo"] : @{};
    if ([ph[@"dim"] isKindOfClass:NSNumber.class]) s.dim = MAX(0, MIN(0.85, [ph[@"dim"] doubleValue]));
    if ([ph[@"blur"] isKindOfClass:NSNumber.class]) s.blur = MAX(0, MIN(1, [ph[@"blur"] doubleValue]));
    NSDictionary *ov = [d[@"overrides"] isKindOfClass:NSDictionary.class] ? d[@"overrides"] : @{};
    NSArray *allowed = @[@"text", @"secondary", @"surface", @"stroke", @"buttonBg", @"buttonFg", @"selected", @"bars"];
    for (NSString *k in ov) {
        unsigned h = 0;
        if ([allowed containsObject:k] && [ov[k] isKindOfClass:NSString.class] && VGParseHex(ov[k], &h)) s.overrides[k] = @(h);
    }
    return s;
}

- (NSDictionary *)dictionary {
    NSMutableDictionary *ov = [NSMutableDictionary dictionary];
    for (NSString *k in self.overrides) ov[k] = VGHexString(self.overrides[k].unsignedIntValue);
    return @{@"id": self.identifier, @"name": self.name, @"base": @(self.base), @"accent": VGHexString(self.accent),
             @"background": @{@"mode": self.bgMode, @"color": VGHexString(self.bgColor),
                              @"gradient": @{@"c1": VGHexString(self.grad1), @"c2": VGHexString(self.grad2), @"direction": @(self.gradDirection)},
                              @"texture": self.texture, @"photo": @{@"dim": @(self.dim), @"blur": @(self.blur)}},
             @"overrides": ov};
}

- (id)copyWithZone:(NSZone *)z {
    VGThemeSpec *c = [VGThemeSpec specFromDictionary:self.dictionary];
    return c;
}

- (BOOL)isEqualToSpec:(VGThemeSpec *)o { return o && [self.dictionary isEqualToDictionary:o.dictionary]; }

- (NSString *)photoPath { return [[VGThemeStore photoDirectory] stringByAppendingPathComponent:[self.identifier stringByAppendingString:@".jpg"]]; }
- (BOOL)hasPhoto { return self.assumePhoto || [NSFileManager.defaultManager fileExistsAtPath:self.photoPath]; }
- (NSString *)cacheKey {
    NSDate *m = [[NSFileManager.defaultManager attributesOfItemAtPath:self.photoPath error:nil] fileModificationDate];
    return [NSString stringWithFormat:@"%@|%@|%.0f", self.identifier, self.dictionary, m.timeIntervalSince1970];
}

@end

#pragma mark Store

static NSMutableArray<VGThemeSpec *> *sList;

@implementation VGThemeStore

+ (NSString *)photoDirectory {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"VidGrabThemes"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

+ (NSMutableArray<VGThemeSpec *> *)list {
    if (!sList) {
        sList = [NSMutableArray array];
        NSArray *raw = [NSUserDefaults.standardUserDefaults arrayForKey:kThemesKey];
        for (id d in raw) { VGThemeSpec *s = [VGThemeSpec specFromDictionary:d]; if (s) [sList addObject:s]; }
    }
    return sList;
}

+ (NSArray<VGThemeSpec *> *)all { return [self list].copy; }

+ (void)persist {
    NSMutableArray *raw = [NSMutableArray array];
    for (VGThemeSpec *s in [self list]) [raw addObject:s.dictionary];
    [NSUserDefaults.standardUserDefaults setObject:raw forKey:kThemesKey];
}

+ (VGThemeSpec *)specWithID:(NSString *)identifier {
    for (VGThemeSpec *s in [self list]) if ([s.identifier isEqual:identifier]) return s;
    return nil;
}

+ (VGThemeSpec *)active {
    return [self specWithID:[NSUserDefaults.standardUserDefaults stringForKey:kActiveKey]] ?: [self list].firstObject;
}

+ (void)saveSpec:(VGThemeSpec *)spec {
    NSMutableArray *l = [self list];
    VGThemeSpec *c = [spec copy];
    NSUInteger i = [l indexOfObjectPassingTest:^BOOL(VGThemeSpec *o, NSUInteger idx, BOOL *stop) { return [o.identifier isEqual:c.identifier]; }];
    if (i == NSNotFound) [l addObject:c]; else l[i] = c;
    [self persist];
    if ([self.active.identifier isEqual:c.identifier]) VGResetCustomThemeCache();
}

+ (void)deleteSpec:(VGThemeSpec *)spec {
    NSMutableArray *l = [self list];
    NSString *ident = spec.identifier;
    [l filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(VGThemeSpec *o, id b) { return ![o.identifier isEqual:ident]; }]];
    [NSFileManager.defaultManager removeItemAtPath:spec.photoPath error:nil];
    [self persist];
    if ([[NSUserDefaults.standardUserDefaults stringForKey:kActiveKey] isEqual:ident]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kActiveKey];
        if (VGPalette.selectedIndex == VGCustomThemeSlot) [VGPalette selectIndex:0];   // the theme in use is gone: back to Default
    }
    VGResetCustomThemeCache();
}

+ (NSString *)uniqueNameFor:(NSString *)name excluding:(NSString *)identifier {
    NSString *base = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!base.length) base = @"My Theme";
    NSString *cand = base; int n = 2;
    while (YES) {
        BOOL clash = NO;
        for (VGThemeSpec *s in [self list]) if (![s.identifier isEqual:identifier] && [s.name caseInsensitiveCompare:cand] == NSOrderedSame) { clash = YES; break; }
        if (!clash) return cand;
        cand = [NSString stringWithFormat:@"%@ %d", base, n++];
    }
}

+ (void)apply:(VGThemeSpec *)spec {
    [NSUserDefaults.standardUserDefaults setObject:spec.identifier forKey:kActiveKey];
    [VGPalette selectIndex:VGCustomThemeSlot];
    VGResetCustomThemeCache();
    [NSNotificationCenter.defaultCenter postNotificationName:VGThemeDidChangeNotification object:nil];
}

+ (void)reload { sList = nil; [self migrateIfNeeded]; VGResetCustomThemeCache(); }

+ (void)migrateIfNeeded {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ([d objectForKey:kThemesKey]) return;
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *legacyPhoto = [dir stringByAppendingPathComponent:@"custom-theme-background.jpg"];
    BOOL legacy = [d objectForKey:@"vgCustomAccent"] || [d objectForKey:@"vgCustomBgMode"] || [d objectForKey:@"vgCustomBgColor"]
                  || [NSFileManager.defaultManager fileExistsAtPath:legacyPhoto];
    if (!legacy) { [d setObject:@[] forKey:kThemesKey]; return; }
    VGThemeSpec *s = [VGThemeSpec new];
    s.name = @"Custom Theme";
    if ([d objectForKey:@"vgCustomAccent"]) s.accent = [d integerForKey:@"vgCustomAccent"] & 0xFFFFFF;
    if ([d objectForKey:@"vgCustomBgColor"]) s.bgColor = [d integerForKey:@"vgCustomBgColor"] & 0xFFFFFF;
    if ([d objectForKey:@"vgCustomBgDim"]) s.dim = MAX(0, MIN(0.85, [d doubleForKey:@"vgCustomBgDim"]));
    BOOL photo = [d integerForKey:@"vgCustomBgMode"] == 1 && [NSFileManager.defaultManager fileExistsAtPath:legacyPhoto];
    if (photo) {
        s.bgMode = @"photo";
        [NSFileManager.defaultManager moveItemAtPath:legacyPhoto toPath:s.photoPath error:nil];
    }
    sList = [NSMutableArray arrayWithObject:s];
    [self persist];
    [d setObject:s.identifier forKey:kActiveKey];
}

#pragma mark Sharing

+ (NSData *)exportDataForSpec:(VGThemeSpec *)spec {
    NSMutableDictionary *theme = [spec.dictionary mutableCopy];
    [theme removeObjectForKey:@"id"];
    NSMutableDictionary *file = [@{@"app": @"VidGrab", @"kind": @"theme", @"format": @1, @"theme": theme} mutableCopy];
    if ([spec.bgMode isEqual:@"photo"] && spec.hasPhoto) {
        NSData *img = [NSData dataWithContentsOfFile:spec.photoPath];
        if (img.length && img.length <= 2 * 1024 * 1024) file[@"photo"] = [img base64EncodedStringWithOptions:0];
    }
    return [NSJSONSerialization dataWithJSONObject:file options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
}

+ (VGThemeSpec *)importData:(NSData *)data message:(NSString **)message needsPhoto:(BOOL *)needsPhoto {
    if (needsPhoto) *needsPhoto = NO;
    NSDictionary *file = (data.length && data.length < 4 * 1024 * 1024) ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![file isKindOfClass:NSDictionary.class] || ![file[@"app"] isEqual:@"VidGrab"] || ![file[@"kind"] isEqual:@"theme"] || ![file[@"theme"] isKindOfClass:NSDictionary.class]) {
        if (message) *message = @"That's not a VidGrab theme file.";
        return nil;
    }
    if (![file[@"format"] isKindOfClass:NSNumber.class] || [file[@"format"] integerValue] > 1) {
        if (message) *message = @"This theme was made with a newer version of VidGrab. Update the app and try again.";
        return nil;
    }
    VGThemeSpec *s = [VGThemeSpec specFromDictionary:file[@"theme"]];
    if (!s) { if (message) *message = @"The theme file is damaged."; return nil; }
    s.identifier = NSUUID.UUID.UUIDString;                       // never overwrite an existing theme
    s.name = [self uniqueNameFor:s.name excluding:s.identifier];
    BOOL gotPhoto = NO;
    if ([file[@"photo"] isKindOfClass:NSString.class]) {
        NSData *img = [[NSData alloc] initWithBase64EncodedString:file[@"photo"] options:0];
        UIImage *ui = (img.length && img.length <= 4 * 1024 * 1024) ? [UIImage imageWithData:img] : nil;
        if (ui) gotPhoto = [img writeToFile:s.photoPath atomically:YES];
    }
    if ([s.bgMode isEqual:@"photo"] && !gotPhoto && needsPhoto) *needsPhoto = YES;
    [[self list] addObject:s];
    [self persist];
    return s;
}

+ (NSDictionary *)backupPayload {
    NSMutableDictionary *photos = [NSMutableDictionary dictionary];
    NSUInteger total = 0;
    for (VGThemeSpec *s in [self list]) {
        NSData *img = [NSData dataWithContentsOfFile:s.photoPath];
        if (img.length && total + img.length < 8 * 1024 * 1024) { photos[s.identifier] = [img base64EncodedStringWithOptions:0]; total += img.length; }
    }
    NSMutableArray *themes = [NSMutableArray array];
    for (VGThemeSpec *s in [self list]) [themes addObject:s.dictionary];
    return @{@"themes": themes, @"active": [NSUserDefaults.standardUserDefaults stringForKey:kActiveKey] ?: @"", @"photos": photos};
}

+ (void)restoreFromPayload:(NSDictionary *)payload {
    if (![payload isKindOfClass:NSDictionary.class]) return;
    NSMutableArray *list = [NSMutableArray array];
    for (id d in ([payload[@"themes"] isKindOfClass:NSArray.class] ? payload[@"themes"] : @[])) {
        VGThemeSpec *s = [VGThemeSpec specFromDictionary:d];
        if (s) [list addObject:s];
    }
    NSDictionary *photos = [payload[@"photos"] isKindOfClass:NSDictionary.class] ? payload[@"photos"] : @{};
    for (VGThemeSpec *s in list) {
        if (![photos[s.identifier] isKindOfClass:NSString.class]) continue;
        NSData *img = [[NSData alloc] initWithBase64EncodedString:photos[s.identifier] options:0];
        if (img.length && [UIImage imageWithData:img]) [img writeToFile:s.photoPath atomically:YES];
    }
    sList = list;
    [self persist];
    if ([payload[@"active"] isKindOfClass:NSString.class] && [payload[@"active"] length]) [NSUserDefaults.standardUserDefaults setObject:payload[@"active"] forKey:kActiveKey];
}

@end

#pragma mark Background pictures

static void DrawTexture(CGContextRef c, NSString *tex, CGSize s, BOOL lightBase) {
    CGFloat w = lightBase ? 0 : 1;
    if ([tex isEqual:@"noise"]) {
        unsigned seed = 12345;
        for (int i = 0; i < (int)(s.width * s.height / 7); i++) {
            seed = seed * 1664525u + 1013904223u;
            CGFloat x = (seed >> 8) % (unsigned)s.width, a = 0.02 + ((seed >> 4) & 15) / 15.0 * 0.07;
            seed = seed * 1664525u + 1013904223u;
            CGFloat y = (seed >> 8) % (unsigned)s.height;
            CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:w alpha:a].CGColor);
            CGContextFillRect(c, CGRectMake(x, y, 1, 1));
        }
    } else if ([tex isEqual:@"grid"]) {
        CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:w alpha:0.06].CGColor);
        CGContextSetLineWidth(c, 1);
        for (CGFloat x = 0; x < s.width; x += 28) { CGContextMoveToPoint(c, x + 0.5, 0); CGContextAddLineToPoint(c, x + 0.5, s.height); }
        for (CGFloat y = 0; y < s.height; y += 28) { CGContextMoveToPoint(c, 0, y + 0.5); CGContextAddLineToPoint(c, s.width, y + 0.5); }
        CGContextStrokePath(c);
    } else if ([tex isEqual:@"dots"]) {
        CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:w alpha:0.10].CGColor);
        int row = 0;
        for (CGFloat y = 10; y < s.height; y += 22, row++)
            for (CGFloat x = (row % 2) ? 21 : 10; x < s.width; x += 22) CGContextFillEllipseInRect(c, CGRectMake(x - 1.3, y - 1.3, 2.6, 2.6));
    } else if ([tex isEqual:@"lines"]) {
        CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:w alpha:0.06].CGColor);
        CGContextSetLineWidth(c, 1);
        for (CGFloat x = -s.height; x < s.width; x += 18) { CGContextMoveToPoint(c, x, s.height); CGContextAddLineToPoint(c, x + s.height, 0); }
        CGContextStrokePath(c);
    }
}

static UIImage *ScaledPhoto(UIImage *img, CGSize px, double blur) {
    // Fill the target size, centred, then blur at that small size (cheap).
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat]; f.scale = 1;
    UIImage *fit = [[[UIGraphicsImageRenderer alloc] initWithSize:px format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        CGFloat k = MAX(px.width / img.size.width, px.height / img.size.height);
        CGSize d = CGSizeMake(img.size.width * k, img.size.height * k);
        [img drawInRect:CGRectMake((px.width - d.width) / 2, (px.height - d.height) / 2, d.width, d.height)];
    }];
    if (blur <= 0.01) return fit;
    static CIContext *ctx; static dispatch_once_t once; dispatch_once(&once, ^{ ctx = [CIContext contextWithOptions:nil]; });
    CIImage *in = [CIImage imageWithCGImage:fit.CGImage];
    CIFilter *g = [CIFilter filterWithName:@"CIGaussianBlur"];
    [g setValue:[in imageByClampingToExtent] forKey:kCIInputImageKey];
    [g setValue:@(blur * 22.0 * (px.width / 390.0)) forKey:kCIInputRadiusKey];
    CIImage *out = [g.outputImage imageByCroppingToRect:in.extent];
    CGImageRef cg = out ? [ctx createCGImage:out fromRect:in.extent] : NULL;
    if (!cg) return fit;
    UIImage *r = [UIImage imageWithCGImage:cg scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return r;
}

UIImage *VGRenderThemeBackground(VGThemeSpec *spec, CGSize size, CGFloat scale, UIImage *photoOverride) {
    if (size.width < 1 || size.height < 1) return nil;
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat]; f.scale = scale; f.opaque = YES;
    UIColor *base = VGHex(spec.bgColor);
    BOOL lightBase = ({ CGFloat r, g, b, a; [base getRed:&r green:&g blue:&b alpha:&a]; (0.299 * r + 0.587 * g + 0.114 * b) > 0.6; });
    NSString *mode = spec.bgMode;
    UIImage *photo = nil;
    if ([mode isEqual:@"photo"]) {
        UIImage *src = photoOverride ?: [UIImage imageWithContentsOfFile:spec.photoPath];
        if (src) photo = ScaledPhoto(src, CGSizeMake(size.width * scale, size.height * scale), spec.blur);
    }
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:f] imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef c = rc.CGContext;
        CGRect full = CGRectMake(0, 0, size.width, size.height);
        if ([mode isEqual:@"gradient"]) {
            CGPoint a[4] = {{0.5, 0}, {0, 0}, {0, 0.5}, {0, 1}}, b[4] = {{0.5, 1}, {1, 1}, {1, 0.5}, {1, 0}};
            NSInteger d = MAX(0, MIN(3, spec.gradDirection));
            NSArray *cols = @[(id)VGHex(spec.grad1).CGColor, (id)VGHex(spec.grad2).CGColor];
            CGGradientRef g = CGGradientCreateWithColors(CGColorSpaceCreateDeviceRGB(), (__bridge CFArrayRef)cols, NULL);
            CGContextDrawLinearGradient(c, g, CGPointMake(a[d].x * size.width, a[d].y * size.height), CGPointMake(b[d].x * size.width, b[d].y * size.height), kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
            CGGradientRelease(g);
        } else if ([mode isEqual:@"texture"]) {
            if ([spec.texture isEqual:@"carbon"]) {
                UIImage *img = [UIImage imageWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"carbon" ofType:@"jpg"]];
                [VGHex(0x131415) setFill]; CGContextFillRect(c, full);
                if (img) {
                    CGFloat k = MAX(size.width / img.size.width, size.height / img.size.height);
                    CGSize d = CGSizeMake(img.size.width * k, img.size.height * k);
                    [img drawInRect:CGRectMake((size.width - d.width) / 2, 0, d.width, d.height)];
                }
            } else {
                [base setFill]; CGContextFillRect(c, full);
                DrawTexture(c, spec.texture, size, lightBase);
            }
        } else if (photo) {
            [photo drawInRect:full];
            if (spec.dim > 0) { [[UIColor colorWithWhite:0 alpha:spec.dim] setFill]; CGContextFillRect(c, full); }
        } else {
            [base setFill]; CGContextFillRect(c, full);
        }
    }];
}

void VGRenderThemeBackgroundAsync(VGThemeSpec *spec, CGSize size, CGFloat scale, UIImage *photoOverride, void (^done)(UIImage *)) {
    VGThemeSpec *c = [spec copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *img = VGRenderThemeBackground(c, size, scale, photoOverride);
        dispatch_async(dispatch_get_main_queue(), ^{ done(img); });
    });
}
