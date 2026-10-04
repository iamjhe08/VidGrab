#import "VGCache.h"
#import "VGEngine.h"
#import <WebKit/WebKit.h>

@implementation VGCache

+ (BOOL)autoClearOnLaunch { return [NSUserDefaults.standardUserDefaults boolForKey:@"vgAutoClearCache"]; }
+ (void)setAutoClearOnLaunch:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:@"vgAutoClearCache"]; }

/// Folders and files we own and may delete. WebKit's own folders are cleared through WebKit instead.
+ (NSArray<NSString *> *)paths {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *out = [NSMutableArray array];
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    for (NSString *n in [fm contentsOfDirectoryAtPath:caches error:nil]) {
        if ([n containsString:@"WebKit"] || [n hasPrefix:@"com.apple"] || [n isEqualToString:@"Snapshots"]) continue;
        [out addObject:[caches stringByAppendingPathComponent:n]];
    }
    NSString *tmp = NSTemporaryDirectory();
    BOOL busy = [VGEngine shared].activeCount > 0;
    for (NSString *n in [fm contentsOfDirectoryAtPath:tmp error:nil]) {
        if (busy && [n isEqualToString:@"work"]) continue;   // running downloads use this
        if ([n containsString:@"WebKit"]) continue;
        [out addObject:[tmp stringByAppendingPathComponent:n]];
    }
    return out;
}

static long long sizeOf(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL dir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&dir]) return 0;
    if (!dir) return [[fm attributesOfItemAtPath:path error:nil][NSFileSize] longLongValue];
    long long total = 0;
    NSDirectoryEnumerator *e = [fm enumeratorAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey]
                                           options:0 errorHandler:nil];
    for (NSURL *u in e) {
        NSDictionary *v = [u resourceValuesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey] error:nil];
        if ([v[NSURLIsRegularFileKey] boolValue]) total += [v[NSURLFileSizeKey] longLongValue];
    }
    return total;
}

+ (NSSet<NSString *> *)webCacheTypes {
    return [NSSet setWithArray:@[WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
                                 WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeFetchCache]];
}

+ (void)size:(void (^)(long long))completion {
    NSArray *paths = [self paths];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        long long total = NSURLCache.sharedURLCache.currentDiskUsage;
        for (NSString *p in paths) total += sizeOf(p);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(total); });
    });
}

+ (void)clear:(void (^)(long long))completion {
    NSArray *paths = [self paths];
    [NSURLCache.sharedURLCache removeAllCachedResponses];
    // Page cache only: cookies and sign-ins are left alone.
    [WKWebsiteDataStore.defaultDataStore removeDataOfTypes:[self webCacheTypes] modifiedSince:[NSDate distantPast] completionHandler:^{}];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        long long freed = 0;
        for (NSString *p in paths) {
            long long s = sizeOf(p);
            if ([NSFileManager.defaultManager removeItemAtPath:p error:nil]) freed += s;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(freed); });
    });
}

@end
