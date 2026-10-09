#import "VGCoverSearch.h"

@implementation VGCoverResult
@end

@implementation VGCoverSearch

+ (BOOL)autoEnabled { return [NSUserDefaults.standardUserDefaults boolForKey:@"vgAutoCover"]; }
+ (void)setAutoEnabled:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:@"vgAutoCover"]; }

+ (NSString *)cleanedTerms:(NSString *)s {
    NSString *t = s ?: @"";
    t = [t stringByReplacingOccurrencesOfString:@"\\s*[\\(\\[][^\\)\\]]*[\\)\\]]" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, t.length)];
    t = [t stringByReplacingOccurrencesOfString:@"(?i)\\b(official|video|audio|lyrics?|lyric video|hd|hq|4k|music video|mv)\\b" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, t.length)];
    t = [t stringByReplacingOccurrencesOfString:@"[-–—|_]+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, t.length)];
    t = [t stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, t.length)];
    return [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (void)search:(NSString *)terms completion:(void (^)(NSArray<VGCoverResult *> *, NSString *))completion {
    NSString *q = [self cleanedTerms:terms];
    if (!q.length) { completion(@[], @"Type a song or artist first."); return; }
    NSURLComponents *c = [NSURLComponents componentsWithString:@"https://itunes.apple.com/search"];
    c.queryItems = @[[NSURLQueryItem queryItemWithName:@"term" value:q], [NSURLQueryItem queryItemWithName:@"media" value:@"music"],
                     [NSURLQueryItem queryItemWithName:@"entity" value:@"song"], [NSURLQueryItem queryItemWithName:@"limit" value:@"25"]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:c.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSMutableArray *out = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        NSString *msg = nil;
        if (err || !data) msg = @"Couldn't reach the internet. Check your connection and try again.";
        else {
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            for (NSDictionary *r in [j[@"results"] isKindOfClass:NSArray.class] ? j[@"results"] : @[]) {
                NSString *small = r[@"artworkUrl100"];
                if (![small isKindOfClass:NSString.class] || !small.length) continue;
                if ([seen containsObject:small]) continue;   // many songs share one album cover
                [seen addObject:small];
                VGCoverResult *x = [VGCoverResult new];
                x.title = r[@"trackName"] ?: @"";
                x.artist = r[@"artistName"] ?: @"";
                x.album = r[@"collectionName"] ?: @"";
                x.smallURL = [NSURL URLWithString:small];
                x.bigURL = [NSURL URLWithString:[small stringByReplacingOccurrencesOfString:@"100x100bb" withString:@"1000x1000bb"]];
                if (x.smallURL && x.bigURL) [out addObject:x];
                if (out.count >= 12) break;
            }
            if (!out.count) msg = @"No pictures found. Try fewer words, like just the song name.";
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(out, msg); });
    }] resume];
}

+ (void)loadImage:(NSURL *)url completion:(void (^)(UIImage *))completion {
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(img); });
    }] resume];
}

@end
