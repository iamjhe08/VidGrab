#import "VGDownloadDefaults.h"

static NSString *const kQ = @"vgDefQuality", *const kK = @"vgDefKind";

/// Height of an option's picture: "1080p 60fps" is 1080, "4K" is 2160, "2K" is 1440.
static NSInteger HeightOf(VGOption *o) {
    NSString *r = o.res.lowercaseString ?: @"";
    if ([r hasPrefix:@"4k"] || [r hasPrefix:@"8k"]) return [r hasPrefix:@"8k"] ? 4320 : 2160;
    if ([r hasPrefix:@"2k"]) return 1440;
    NSScanner *sc = [NSScanner scannerWithString:r];
    NSInteger n = 0;
    return [sc scanInteger:&n] ? n : 0;
}

@implementation VGDownloadDefaults

+ (NSInteger)threads { NSInteger v = [NSUserDefaults.standardUserDefaults integerForKey:@"vgThreads"]; return v >= 1 ? MIN(v, 10) : 8; }
+ (void)setThreads:(NSInteger)n { [NSUserDefaults.standardUserDefaults setInteger:n forKey:@"vgThreads"]; }
+ (BOOL)filesOnly { return [NSUserDefaults.standardUserDefaults boolForKey:@"vgFilesOnly"]; }
+ (void)setFilesOnly:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:@"vgFilesOnly"]; }
+ (NSArray<NSNumber *> *)threadChoices { return @[@1, @2, @3, @4, @5, @6, @7, @8, @9, @10]; }

+ (NSString *)extraWithThreads:(NSString *)extra {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (extra.length) {
        id j = [NSJSONSerialization JSONObjectWithData:[extra dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil];
        if ([j isKindOfClass:NSDictionary.class]) [d addEntriesFromDictionary:j];
    }
    d[@"threads"] = @(self.threads);
    NSData *out = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    return out ? ([[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] ?: extra ?: @"") : (extra ?: @"");
}

+ (NSInteger)quality { id v = [NSUserDefaults.standardUserDefaults objectForKey:kQ]; return v ? [v integerValue] : -1; }
+ (void)setQuality:(NSInteger)q { [NSUserDefaults.standardUserDefaults setInteger:q forKey:kQ]; }
+ (NSInteger)kind { id v = [NSUserDefaults.standardUserDefaults objectForKey:kK]; return v ? [v integerValue] : -1; }
+ (void)setKind:(NSInteger)k { [NSUserDefaults.standardUserDefaults setInteger:k forKey:kK]; }
+ (BOOL)skipSheet { return self.kind == 1 || (self.kind == 0 && self.quality >= 0); }

+ (NSArray<NSNumber *> *)qualityChoices { return @[@-1, @0, @2160, @1440, @1080, @720, @480, @360]; }

+ (NSString *)nameForQuality:(NSInteger)q {
    if (q < 0) return @"Always ask";
    if (q == 0) return @"Best available";
    if (q == 2160) return @"4K";
    if (q == 1440) return @"2K";
    return [NSString stringWithFormat:@"%ldp", (long)q];
}

+ (NSString *)kindName { return self.kind < 0 ? @"Always ask" : (self.kind == 1 ? @"Audio only" : @"Video"); }

+ (NSInteger)indexIn:(NSArray<VGOption *> *)options current:(NSInteger)current {
    if (!options.count) return current;
    if (self.kind == 1) {
        for (NSUInteger i = 0; i < options.count; i++) if (options[i].audio) return (NSInteger)i;
        return current;   // no audio option for this one: fall back to the usual choice
    }
    NSInteger want = self.quality;
    if (want <= 0) return current;   // always ask, or best
    NSInteger best = -1, bestH = -1, lowest = -1, lowestH = NSIntegerMax;
    for (NSUInteger i = 0; i < options.count; i++) {
        VGOption *o = options[i];
        if (o.audio) continue;
        NSInteger h = HeightOf(o);
        if (h <= 0) continue;
        if (h <= want && h > bestH) { best = (NSInteger)i; bestH = h; }
        if (h < lowestH) { lowest = (NSInteger)i; lowestH = h; }
    }
    if (best >= 0) {
        // Several options can share a height (formats): keep the first, the list is already best-first.
        return best;
    }
    return lowest >= 0 ? lowest : current;   // nothing that small: the smallest there is
}

+ (nullable VGOption *)autoPickFrom:(NSArray<VGOption *> *)options {
    if (!self.skipSheet || !options.count) return nil;
    NSInteger first = 0;
    for (NSUInteger i = 0; i < options.count; i++) if (!options[i].audio) { first = (NSInteger)i; break; }
    NSInteger i = [self indexIn:options current:first];
    return (i >= 0 && i < (NSInteger)options.count) ? options[i] : nil;
}

@end
