#import "VGLyrics.h"
#import "VGEngine.h"

@implementation VGLyrics

- (BOOL)synced { return self.times.count > 0 && self.times.count == self.lines.count; }

- (NSInteger)lineAt:(double)t {
    if (!self.synced) return -1;
    NSInteger r = -1;
    for (NSInteger i = 0; i < (NSInteger)self.times.count; i++) { if (self.times[i].doubleValue + self.offset <= t + 0.15) r = i; else break; }
    return r;
}

+ (NSString *)dir {
    NSString *d = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"lyrics"] copy];
    [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

+ (NSString *)pathFor:(VGItem *)it {
    NSString *n = it.fileName.length ? it.fileName : it.title;
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < n.length; i++) { unichar c = [n characterAtIndex:i]; [s appendFormat:(isalnum(c) && c < 128) ? @"%C" : @"_", c]; }
    return [[self dir] stringByAppendingPathComponent:[s stringByAppendingString:@".json"]];
}

+ (VGLyrics *)cachedFor:(VGItem *)it {
    NSData *d = [NSData dataWithContentsOfFile:[self pathFor:it]];
    if (!d) return nil;
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![j isKindOfClass:NSDictionary.class] || ![j[@"lines"] isKindOfClass:NSArray.class]) return nil;
    VGLyrics *l = [VGLyrics new];
    l.offset = [j[@"offset"] doubleValue];
    l.lines = j[@"lines"]; l.times = [j[@"times"] isKindOfClass:NSArray.class] ? j[@"times"] : @[];
    return l.lines.count ? l : nil;
}

- (void)saveFor:(VGItem *)it { [VGLyrics save:self for:it]; }

+ (void)save:(VGLyrics *)l for:(VGItem *)it {
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"lines": l.lines ?: @[], @"times": l.times ?: @[], @"offset": @(l.offset)} options:0 error:nil];
    [d writeToFile:[self pathFor:it] atomically:YES];
}

// ---- guessing the title and artist

static NSString *Clean(NSString *s) {
    NSString *r = s ?: @"";
    NSRegularExpression *br = [NSRegularExpression regularExpressionWithPattern:@"[\\(\\[\\{][^\\)\\]\\}]*(official|lyric|audio|video|visuali[sz]er|hd|hq|4k|remaster|mv|m/v|music)[^\\)\\]\\}]*[\\)\\]\\}]" options:NSRegularExpressionCaseInsensitive error:nil];
    r = [br stringByReplacingMatchesInString:r options:0 range:NSMakeRange(0, r.length) withTemplate:@""];
    NSRange bar = [r rangeOfString:@" | "];
    if (bar.location != NSNotFound) r = [r substringToIndex:bar.location];
    return [r stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *CleanArtist(NSString *a) {
    NSString *r = a ?: @"";
    for (NSString *suf in @[@" - Topic", @"VEVO", @"Vevo", @" Official"]) r = [r stringByReplacingOccurrencesOfString:suf withString:@""];
    return [r stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

/// Returns @[title, artist].
+ (NSArray<NSString *> *)titleArtistFor:(VGItem *)it {
    NSString *t = Clean(it.title), *a = CleanArtist(it.artist);
    for (NSString *sep in @[@" - ", @" – ", @" — "]) {
        NSRange r = [t rangeOfString:sep];
        if (r.location != NSNotFound && r.location > 0) {
            NSString *left = [t substringToIndex:r.location], *right = [t substringFromIndex:NSMaxRange(r)];
            if (!a.length || [left.lowercaseString containsString:a.lowercaseString] || [a.lowercaseString containsString:left.lowercaseString]) { a = left; }
            else if ([right.lowercaseString containsString:a.lowercaseString]) { a = right; right = left; }
            else { a = left; }
            t = right; break;
        }
    }
    return @[t, a];
}

+ (NSString *)guessFor:(VGItem *)it {
    NSArray *ta = [self titleArtistFor:it];
    return [ta[1] length] ? [NSString stringWithFormat:@"%@ - %@", ta[1], ta[0]] : ta[0];
}

// ---- parsing

+ (VGLyrics *)parseSynced:(NSString *)lrc {
    NSMutableArray *pairs = [NSMutableArray array];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d+):(\\d+(?:\\.\\d+)?)\\]" options:0 error:nil];
    for (NSString *line in [lrc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray *ms = [re matchesInString:line options:0 range:NSMakeRange(0, line.length)];
        if (!ms.count) continue;
        NSTextCheckingResult *last = ms.lastObject;
        NSString *text = [[line substringFromIndex:NSMaxRange(last.range)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        for (NSTextCheckingResult *m in ms) {
            double t = [[line substringWithRange:[m rangeAtIndex:1]] doubleValue] * 60 + [[line substringWithRange:[m rangeAtIndex:2]] doubleValue];
            [pairs addObject:@[@(t), text]];
        }
    }
    [pairs sortUsingComparator:^NSComparisonResult(NSArray *x, NSArray *y) { return [x[0] compare:y[0]]; }];
    NSMutableArray *ts = [NSMutableArray array], *ls = [NSMutableArray array];
    for (NSArray *p in pairs) {
        if ([p[1] length] == 0 && (ls.count == 0 || [ls.lastObject length] == 0)) continue;   // no runs of blank lines
        [ts addObject:p[0]]; [ls addObject:p[1]];
    }
    if (!ls.count) return nil;
    VGLyrics *l = [VGLyrics new]; l.lines = ls; l.times = ts; return l;
}

+ (VGLyrics *)parsePlain:(NSString *)txt {
    NSMutableArray *ls = [NSMutableArray array];
    for (NSString *line in [txt componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])
        [ls addObject:[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    while (ls.count && [ls.firstObject length] == 0) [ls removeObjectAtIndex:0];
    if (!ls.count) return nil;
    VGLyrics *l = [VGLyrics new]; l.lines = ls; l.times = @[]; return l;
}

+ (VGLyrics *)fromRecord:(NSDictionary *)r {
    if (![r isKindOfClass:NSDictionary.class]) return nil;
    id syn = r[@"syncedLyrics"], pl = r[@"plainLyrics"];
    VGLyrics *l = [syn isKindOfClass:NSString.class] ? [self parseSynced:syn] : nil;
    if (!l && [pl isKindOfClass:NSString.class]) l = [self parsePlain:pl];
    return l;
}

// ---- network

+ (void)getJSON:(NSString *)url done:(void (^)(id json))done {
    NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
    [rq setValue:@"VidGrab 1.3.4a (https://github.com/iamjhe08/VidGrab)" forHTTPHeaderField:@"User-Agent"];
    [[NSURLSession.sharedSession dataTaskWithRequest:rq completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        id j = nil;
        if (d && !e && [(NSHTTPURLResponse *)resp statusCode] == 200) j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        done(j);
    }] resume];
}

static NSString *Enc(NSString *s) {
    return [s stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
}

/// The best of the search results: lyrics that are synced and about the right length first.
+ (VGLyrics *)best:(NSArray *)arr duration:(double)dur {
    if (![arr isKindOfClass:NSArray.class]) return nil;
    NSDictionary *pick = nil; double bestScore = -1;
    for (NSDictionary *r in arr) {
        if (![r isKindOfClass:NSDictionary.class]) continue;
        BOOL syn = [r[@"syncedLyrics"] isKindOfClass:NSString.class] && [r[@"syncedLyrics"] length];
        BOOL pl = [r[@"plainLyrics"] isKindOfClass:NSString.class] && [r[@"plainLyrics"] length];
        if (!syn && !pl) continue;
        double rd = [r[@"duration"] respondsToSelector:@selector(doubleValue)] ? [r[@"duration"] doubleValue] : 0;
        BOOL close = dur <= 0 || rd <= 0 || fabs(rd - dur) <= 6;
        double sc = (close ? 10 : 0) + (syn ? 5 : 0) + (pl ? 1 : 0) + (close && dur > 0 && rd > 0 ? (6 - fabs(rd - dur)) * 0.5 : 0);   // the closest length wins
        if (sc > bestScore) { bestScore = sc; pick = r; }
    }
    return bestScore >= 10 || (bestScore >= 0 && dur <= 0) ? [self fromRecord:pick] : nil;
}

+ (void)loadFor:(VGItem *)it query:(NSString *)query completion:(void (^)(VGLyrics *))done {
    double dur = it.duration;
    NSArray *ta = [self titleArtistFor:it];
    NSString *title = ta[0], *artist = ta[1];
    void (^finish)(VGLyrics *) = ^(VGLyrics *l) {
        if (l) [self save:l for:it];
        dispatch_async(dispatch_get_main_queue(), ^{ done(l); });
    };
    NSString *q = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (q.length) {
        [self getJSON:[@"https://lrclib.net/api/search?q=" stringByAppendingString:Enc(q)] done:^(id j) { finish([self best:j duration:dur]); }];
        return;
    }
    NSString *exact = [NSString stringWithFormat:@"https://lrclib.net/api/get?track_name=%@&artist_name=%@%@", Enc(title), Enc(artist), dur > 0 ? [NSString stringWithFormat:@"&duration=%d", (int)round(dur)] : @""];
    void (^search)(void) = ^{
        NSString *u = artist.length
            ? [NSString stringWithFormat:@"https://lrclib.net/api/search?track_name=%@&artist_name=%@", Enc(title), Enc(artist)]
            : [@"https://lrclib.net/api/search?track_name=" stringByAppendingString:Enc(title)];
        [self getJSON:u done:^(id j) {
            VGLyrics *l = [self best:j duration:dur];
            if (l) { finish(l); return; }
            NSString *free = artist.length ? [NSString stringWithFormat:@"%@ %@", artist, title] : title;
            [self getJSON:[@"https://lrclib.net/api/search?q=" stringByAppendingString:Enc(free)] done:^(id j2) { finish([self best:j2 duration:dur]); }];
        }];
    };
    if (!artist.length) { search(); return; }
    [self getJSON:exact done:^(id j) {
        VGLyrics *l = [j isKindOfClass:NSDictionary.class] ? [self fromRecord:j] : nil;
        if (l) finish(l); else search();
    }];
}

@end
