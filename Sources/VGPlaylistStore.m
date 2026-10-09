#import "VGPlaylistStore.h"

NSString *const VGSavedPlaylistsChanged = @"VGSavedPlaylistsChanged";

@implementation VGSavedPlaylist

- (VGVideo *)asVideo {
    VGVideo *v = [VGVideo new];
    v.url = self.url;
    v.title = self.title;
    v.site = self.site;
    v.uploader = self.uploader;
    v.thumbnail = self.thumbnail;
    v.options = @[];
    NSMutableArray *list = [NSMutableArray array];
    double total = 0;
    for (NSDictionary *e in self.entries) {
        VGVideo *x = [VGVideo new];
        x.url = e[@"url"];
        x.title = e[@"title"] ?: @"Untitled video";
        x.duration = [e[@"duration"] doubleValue];
        x.thumbnail = [e[@"thumbnail"] isKindOfClass:NSString.class] ? e[@"thumbnail"] : nil;
        x.site = self.site;
        x.uploader = self.uploader;
        x.options = @[];
        total += x.duration;
        [list addObject:x];
    }
    v.entries = list;
    v.duration = total;
    return v;
}

- (NSDictionary *)dict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"id"] = self.identifier; d[@"title"] = self.title ?: @"Playlist"; d[@"url"] = self.url ?: @"";
    if (self.site) d[@"site"] = self.site;
    if (self.uploader) d[@"uploader"] = self.uploader;
    if (self.thumbnail) d[@"thumb"] = self.thumbnail;
    d[@"date"] = @(self.date.timeIntervalSince1970);
    d[@"entries"] = self.entries ?: @[];
    return d;
}

+ (instancetype)fromDict:(NSDictionary *)d {
    if (![d[@"id"] isKindOfClass:NSString.class] || ![d[@"url"] isKindOfClass:NSString.class]) return nil;
    VGSavedPlaylist *p = [VGSavedPlaylist new];
    p.identifier = d[@"id"];
    p.title = [d[@"title"] isKindOfClass:NSString.class] ? d[@"title"] : @"Playlist";
    p.url = d[@"url"];
    p.site = [d[@"site"] isKindOfClass:NSString.class] ? d[@"site"] : nil;
    p.uploader = [d[@"uploader"] isKindOfClass:NSString.class] ? d[@"uploader"] : nil;
    p.thumbnail = [d[@"thumb"] isKindOfClass:NSString.class] ? d[@"thumb"] : nil;
    p.date = [NSDate dateWithTimeIntervalSince1970:[d[@"date"] doubleValue]];
    p.entries = [d[@"entries"] isKindOfClass:NSArray.class] ? d[@"entries"] : @[];
    return p;
}

@end

static NSMutableArray<VGSavedPlaylist *> *gList;

static NSString *storePath(void) {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"library"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"saved-playlists.json"];
}

@implementation VGPlaylistStore

+ (NSMutableArray<VGSavedPlaylist *> *)list {
    if (!gList) {
        gList = [NSMutableArray array];
        NSData *data = [NSData dataWithContentsOfFile:storePath()];
        NSArray *arr = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        for (NSDictionary *d in [arr isKindOfClass:NSArray.class] ? arr : @[]) {
            VGSavedPlaylist *p = [d isKindOfClass:NSDictionary.class] ? [VGSavedPlaylist fromDict:d] : nil;
            if (p) [gList addObject:p];
        }
    }
    return gList;
}

+ (void)persist {
    NSMutableArray *arr = [NSMutableArray array];
    for (VGSavedPlaylist *p in gList) [arr addObject:[p dict]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:arr options:0 error:nil];
    [data writeToFile:storePath() atomically:YES];
    [NSNotificationCenter.defaultCenter postNotificationName:VGSavedPlaylistsChanged object:nil];
}

+ (NSArray<VGSavedPlaylist *> *)all { return [[self list] copy]; }

+ (VGSavedPlaylist *)withID:(NSString *)identifier {
    for (VGSavedPlaylist *p in [self list]) if ([p.identifier isEqualToString:identifier]) return p;
    return nil;
}

+ (VGSavedPlaylist *)forURL:(NSString *)url {
    for (VGSavedPlaylist *p in [self list]) if ([p.url isEqualToString:url]) return p;
    return nil;
}

+ (VGSavedPlaylist *)save:(VGVideo *)v {
    VGSavedPlaylist *p = [self forURL:v.url];
    if (!p) { p = [VGSavedPlaylist new]; p.identifier = NSUUID.UUID.UUIDString; [[self list] insertObject:p atIndex:0]; }
    p.title = v.title.length ? v.title : @"Playlist";
    p.url = v.url;
    p.site = v.site;
    p.uploader = v.uploader;
    p.thumbnail = v.thumbnail;
    p.date = NSDate.date;
    NSMutableArray *es = [NSMutableArray array];
    for (VGVideo *e in v.entries) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"url"] = e.url ?: @""; d[@"title"] = e.title ?: @"Untitled video"; d[@"duration"] = @(e.duration);
        if (e.thumbnail) d[@"thumbnail"] = e.thumbnail;
        [es addObject:d];
    }
    p.entries = es;
    [self persist];
    return p;
}

+ (void)remove:(VGSavedPlaylist *)p { [[self list] removeObject:p]; [self persist]; }

+ (void)rename:(VGSavedPlaylist *)p to:(NSString *)title {
    NSString *t = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!t.length) return;
    p.title = t;
    [self persist];
}

@end
