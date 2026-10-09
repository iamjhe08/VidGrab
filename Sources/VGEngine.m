#import "VGEngine.h"
#import "VGAudioTags.h"
#import "VGCoverSearch.h"
#import <objc/runtime.h>
#include <stdio.h>
#include <errno.h>
#include <sys/stdio.h>
#import "VGPython.h"
#import <AVFoundation/AVFoundation.h>
#import "VGTranscoder.h"
#import "VGConvert.h"
#import "VGCrash.h"
#import <WebKit/WebKit.h>

NSString *const VGLibraryDidChangeNotification = @"VGLibraryDidChangeNotification";
NSString *const VGTasksDidChangeNotification = @"VGTasksDidChangeNotification";
NSString *const VGTaskFinishedNotification = @"VGTaskFinishedNotification";

@implementation VGOption
@end

@implementation VGVideo
- (BOOL)isPlaylist { return self.entries != nil; }
@end

@interface VGTask ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, strong) VGVideo *video;
@property (nonatomic, readwrite, strong) VGOption *option;
@property (nonatomic, readwrite) VGTaskState state;
@property (nonatomic, readwrite) double fraction;
@property (nonatomic, readwrite, copy) NSString *stage;
@property (nonatomic, readwrite, copy) NSString *detail;
@property (nonatomic, readwrite, copy, nullable) NSString *error;
@property (nonatomic, readwrite, strong, nullable) VGItem *item;
@property (nonatomic, strong, nullable) AVAssetExportSession *export;
@property (nonatomic, strong, nullable) VGTranscoder *transcoder;
@property (nonatomic, strong, nullable) VGConvert *converter;
@property (nonatomic) CFAbsoluteTime lastPost;
@property (nonatomic, copy) NSString *resumeKey;
@property (nonatomic) BOOL pyRunning;      // the download engine is still working on this task
@property (nonatomic) BOOL wantsResume;    // Resume tapped while the engine was still stopping
@end

@implementation VGTask
@end

static NSString *documentsDir(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

static NSString *supportPath(NSString *name) {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"library"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:name];
}

/// Private Vault 2.0 files live outside Documents, so they don't show in the Files app.
static NSString *vaultDir(void) {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"vault"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey: NSFileProtectionComplete} error:nil];
    return dir;
}

static BOOL isAudioKind(NSString *k) {
    return [k isEqualToString:@"mp3"] || [k isEqualToString:@"audio"] || [k isEqualToString:@"wav"] || [k isEqualToString:@"flac"];
}

#pragma mark - Item

@implementation VGItem

- (NSURL *)fileURL {
    if (self.vault) return [NSURL fileURLWithPath:[vaultDir() stringByAppendingPathComponent:self.fileName]];
    return [NSURL fileURLWithPath:[documentsDir() stringByAppendingPathComponent:self.fileName]];
}

- (NSString *)thumbPath {
    return supportPath([[self.fileName stringByDeletingPathExtension] stringByAppendingString:@".thumb.jpg"]);
}

- (NSString *)artworkPath {
    return self.artworkName.length ? supportPath(self.artworkName) : nil;
}

- (UIImage *)thumbnailImage {
    if (self.artworkName.length) {
        UIImage *art = [UIImage imageWithContentsOfFile:self.artworkPath];
        if (art) return art;
    }
    return [UIImage imageWithContentsOfFile:[self thumbPath]];
}

- (NSDictionary *)dict {
    return @{@"file": self.fileName, @"title": self.title, @"site": self.site ?: @"", @"res": self.res ?: @"",
             @"duration": @(self.duration), @"bytes": @(self.bytes), @"audio": @(self.audio),
             @"photos": @(self.photos), @"date": @(self.date.timeIntervalSince1970), @"vault": @(self.vault),
             @"folder": self.folderID ?: @"", @"fav": @(self.favorite), @"artist": self.artist ?: @"", @"album": self.album ?: @"",
             @"art": self.artworkName ?: @""};
}

+ (instancetype)fromDict:(NSDictionary *)d {
    VGItem *i = [VGItem new];
    i.fileName = d[@"file"];
    i.title = d[@"title"] ?: i.fileName;
    i.site = [d[@"site"] length] ? d[@"site"] : nil;
    i.res = d[@"res"] ?: @"";
    i.duration = [d[@"duration"] doubleValue];
    i.bytes = [d[@"bytes"] longLongValue];
    i.audio = [d[@"audio"] boolValue];
    i.photos = [d[@"photos"] boolValue];
    i.date = [NSDate dateWithTimeIntervalSince1970:[d[@"date"] doubleValue]];
    i.vault = [d[@"vault"] boolValue];
    i.folderID = [d[@"folder"] length] ? d[@"folder"] : nil;
    i.favorite = [d[@"fav"] boolValue];
    i.artist = [d[@"artist"] length] ? d[@"artist"] : nil;
    i.album = [d[@"album"] length] ? d[@"album"] : nil;
    i.artworkName = [d[@"art"] length] ? d[@"art"] : nil;
    return i;
}

@end

@implementation VGFolder

- (UIColor *)color {
    unsigned int v = 0;
    [[NSScanner scannerWithString:self.colorHex ?: @"0A84FF"] scanHexInt:&v];
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

+ (NSString *)hexFromColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 0;
        if ([color getWhite:&w alpha:&a]) r = g = b = w;
    }
    return [NSString stringWithFormat:@"%02X%02X%02X", (int)lround(MIN(MAX(r, 0), 1) * 255), (int)lround(MIN(MAX(g, 0), 1) * 255), (int)lround(MIN(MAX(b, 0), 1) * 255)];
}

- (NSDictionary *)dict {
    return @{@"id": self.identifier, @"name": self.name, @"color": self.colorHex, @"date": @(self.date.timeIntervalSince1970), @"vault": @(self.vault)};
}

@end

#pragma mark - Engine

@interface VGEngine ()
@property (nonatomic, strong) NSMutableArray<VGItem *> *library;
@property (nonatomic, strong) NSMutableArray<VGFolder *> *folderList;
@property (nonatomic, strong) NSMutableArray<VGTask *> *queue;
@property (nonatomic) NSUInteger nextTaskID;
@property (nonatomic) BOOL nextStartsPaused;
@property (nonatomic, strong) NSMutableString *convLog;   // recent conversion steps, for Copy details
@property (nonatomic) NSUInteger heavyRunning;             // re-encodes in progress (they share the phone's video encoder)
@property (nonatomic, strong) NSMutableArray *heavyWaiting;
@end

@implementation VGEngine

+ (instancetype)shared {
    static VGEngine *e;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [VGEngine new]; });
    return e;
}

- (void)start {
    [self loadLibrary];
    [[VGPython shared] start];
    [self resumePending];
    // Clear temp work folders from earlier runs.
    NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:@"work"];
    [NSFileManager.defaultManager removeItemAtPath:work error:nil];
    // And any half-made MP4 (".partial-*.mp4") left behind by a crash or force quit: it was never a real download.
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *n in [fm contentsOfDirectoryAtPath:documentsDir() error:nil])
        if ([n hasPrefix:@".partial-"] && [n hasSuffix:@".mp4"]) [fm removeItemAtPath:[documentsDir() stringByAppendingPathComponent:n] error:nil];
}

- (NSString *)engineVersion { return [VGPython shared].engineVersion ?: @"starting…"; }

#pragma mark Library

- (NSArray<VGItem *> *)items { return [self.library copy]; }

- (void)loadLibrary {
    self.library = [NSMutableArray array];
    self.folderList = [NSMutableArray array];
    NSData *fd = [NSData dataWithContentsOfFile:supportPath(@"folders.json")];
    NSArray *farr = fd ? [NSJSONSerialization JSONObjectWithData:fd options:0 error:nil] : nil;
    for (NSDictionary *x in ([farr isKindOfClass:NSArray.class] ? farr : @[])) {
        if (![x isKindOfClass:NSDictionary.class] || ![x[@"id"] length]) continue;
        VGFolder *f = [VGFolder new];
        f.identifier = x[@"id"];
        f.name = [x[@"name"] length] ? x[@"name"] : @"Folder";
        f.colorHex = [x[@"color"] length] == 6 ? x[@"color"] : @"0A84FF";
        f.date = [NSDate dateWithTimeIntervalSince1970:[x[@"date"] doubleValue]];
        f.vault = [x[@"vault"] boolValue];
        [self.folderList addObject:f];
    }
    NSData *d = [NSData dataWithContentsOfFile:supportPath(@"library.json")];
    NSArray *arr = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSDictionary *x in ([arr isKindOfClass:NSArray.class] ? arr : @[])) {
        VGItem *i = [VGItem fromDict:x];
        // Drop entries whose files were removed in the Files app.
        if (i.fileName && [fm fileExistsAtPath:i.fileURL.path]) {
            VGFolder *fo = i.folderID ? [self folderWithID:i.folderID] : nil;
            if (i.folderID && (!fo || fo.vault != i.vault)) i.folderID = nil;   // its folder is gone, or it sits in the wrong place
            [self.library addObject:i];
        }
    }
}

#pragma mark Folders

- (NSArray<VGFolder *> *)folders {
    NSMutableArray *a = [NSMutableArray array];
    for (VGFolder *f in self.folderList) if (!f.vault) [a addObject:f];
    return a;
}

- (NSArray<VGFolder *> *)vaultFolders {
    NSMutableArray *a = [NSMutableArray array];
    for (VGFolder *f in self.folderList) if (f.vault) [a addObject:f];
    return a;
}

- (VGFolder *)folderWithID:(NSString *)identifier {
    if (!identifier.length) return nil;
    for (VGFolder *f in self.folderList) if ([f.identifier isEqualToString:identifier]) return f;
    return nil;
}

- (void)saveFolders {
    NSMutableArray *arr = [NSMutableArray array];
    for (VGFolder *f in self.folderList) [arr addObject:[f dict]];
    [[NSJSONSerialization dataWithJSONObject:arr options:0 error:nil] writeToFile:supportPath(@"folders.json") atomically:YES];
}

static NSString *cleanFolderName(NSString *name) {
    NSString *n = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (n.length > 60) n = [n substringToIndex:60];
    return n.length ? n : @"New Folder";
}

- (VGFolder *)createFolderNamed:(NSString *)name colorHex:(NSString *)hex {
    return [self createFolderNamed:name colorHex:hex vault:NO];
}

- (VGFolder *)createFolderNamed:(NSString *)name colorHex:(NSString *)hex vault:(BOOL)vault {
    VGFolder *f = [VGFolder new];
    f.vault = vault;
    f.identifier = [NSUUID UUID].UUIDString;
    f.name = cleanFolderName(name);
    f.colorHex = hex.length == 6 ? hex : @"0A84FF";
    f.date = [NSDate date];
    [self.folderList addObject:f];
    [self saveFolders];
    [NSNotificationCenter.defaultCenter postNotificationName:VGLibraryDidChangeNotification object:nil];
    return f;
}

- (void)updateFolder:(VGFolder *)folder name:(NSString *)name colorHex:(NSString *)hex {
    if (![self.folderList containsObject:folder]) return;
    folder.name = cleanFolderName(name);
    if (hex.length == 6) folder.colorHex = hex;
    [self saveFolders];
    [NSNotificationCenter.defaultCenter postNotificationName:VGLibraryDidChangeNotification object:nil];
}

- (void)deleteFolder:(VGFolder *)folder {
    for (VGItem *i in self.library) if ([i.folderID isEqualToString:folder.identifier]) i.folderID = nil;
    [self.folderList removeObject:folder];
    [self saveFolders];
    [self saveLibrary];
}

- (void)setItems:(NSArray<VGItem *> *)items folder:(VGFolder *)folder {
    if (folder && ![self.folderList containsObject:folder]) return;
    for (VGItem *i in items) {
        if (folder && i.vault != folder.vault) continue;   // vault videos only go in vault folders, and the other way round
        i.folderID = folder.identifier;
    }
    [self saveLibrary];
}

- (NSArray<VGItem *> *)itemsInFolder:(VGFolder *)folder {
    NSMutableArray *out = [NSMutableArray array];
    for (VGItem *i in self.library) if (i.vault == folder.vault && [i.folderID isEqualToString:folder.identifier]) [out addObject:i];
    return out;
}

- (void)saveLibrary {
    NSMutableArray *arr = [NSMutableArray array];
    for (VGItem *i in self.library) [arr addObject:[i dict]];
    [[NSJSONSerialization dataWithJSONObject:arr options:0 error:nil] writeToFile:supportPath(@"library.json") atomically:YES];
    [NSNotificationCenter.defaultCenter postNotificationName:VGLibraryDidChangeNotification object:nil];
}

- (void)deleteItem:(VGItem *)item {
    [NSFileManager.defaultManager removeItemAtURL:item.fileURL error:nil];
    [NSFileManager.defaultManager removeItemAtPath:[item thumbPath] error:nil];
    if (item.artworkName.length) [NSFileManager.defaultManager removeItemAtPath:item.artworkPath error:nil];
    [self.library removeObject:item];
    [self saveLibrary];
}

- (void)setItem:(VGItem *)item inVault:(BOOL)vault {
    if (item.vault == vault) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *from = item.fileURL;
    NSString *dir = vault ? vaultDir() : documentsDir();
    NSString *name = item.fileName;
    // Avoid clashing with a file of the same name in the other place.
    for (int n = 2; [fm fileExistsAtPath:[dir stringByAppendingPathComponent:name]]; n++)
        name = [NSString stringWithFormat:@"%@ (%d).%@", [item.fileName stringByDeletingPathExtension], n, item.fileName.pathExtension];
    NSString *oldThumb = [item thumbPath];
    NSError *e = nil;
    if (![fm moveItemAtURL:from toURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]] error:&e]) return;
    item.fileName = name;
    item.vault = vault;
    item.folderID = nil;   // folders belong to one place; it starts loose in the new one
    if (![oldThumb isEqualToString:[item thumbPath]]) [fm moveItemAtPath:oldThumb toPath:[item thumbPath] error:nil];
    [self saveLibrary];
}


#pragma mark Favorites, audio details and formats

- (void)setFavorite:(BOOL)favorite forItem:(VGItem *)item {
    item.favorite = favorite;
    [self saveLibrary];
}

- (void)updateItem:(VGItem *)item title:(NSString *)title artist:(NSString *)artist album:(NSString *)album
           artwork:(NSData *)artwork clearArtwork:(BOOL)clearArtwork completion:(void (^)(NSString *))completion {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *t = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (t.length) item.title = t;
    NSString *a = [artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *al = [album stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    item.artist = a.length ? a : nil;
    item.album = al.length ? al : nil;
    if (artwork.length || clearArtwork) {
        if (item.artworkName.length) [fm removeItemAtPath:item.artworkPath error:nil];
        item.artworkName = nil;
        if (artwork.length) {
            NSString *name = [NSString stringWithFormat:@"art-%@.jpg", NSUUID.UUID.UUIDString];
            if ([artwork writeToFile:supportPath(name) atomically:YES]) item.artworkName = name;
        }
    }
    [self saveLibrary];
    NSData *art = item.artworkName.length ? [NSData dataWithContentsOfFile:item.artworkPath] : nil;
    __weak typeof(self) ws = self;
    [VGAudioTags writeTitle:item.title artist:item.artist album:item.album artwork:art toPath:item.fileURL.path completion:^(NSString *err) {
        item.bytes = [[[NSFileManager defaultManager] attributesOfItemAtPath:item.fileURL.path error:nil][NSFileSize] longLongValue];
        [ws saveLibrary];
        if (completion) completion(err);
    }];
}

/// Settings > Audio > Find cover art online: after an audio download, look the song up and use its album picture.
- (void)autoCoverFor:(VGItem *)item {
    NSString *terms = [NSString stringWithFormat:@"%@ %@", item.artist ?: @"", item.title ?: @""];
    __weak typeof(self) ws = self;
    [VGCoverSearch search:terms completion:^(NSArray<VGCoverResult *> *results, NSString *error) {
        VGCoverResult *r = results.firstObject;
        if (!r) return;
        [VGCoverSearch loadImage:r.bigURL completion:^(UIImage *img) {
            NSData *jpeg = img ? [VGAudioTags squareJPEGFrom:img side:1000] : nil;
            if (!jpeg || ![ws.library containsObject:item]) return;
            [ws updateItem:item title:item.title artist:item.artist.length ? item.artist : r.artist album:item.album.length ? item.album : r.album
                   artwork:jpeg clearArtwork:NO completion:nil];
        }];
    }];
}

- (void)copyItemToDownloads:(VGItem *)item completion:(void (^)(NSString *))completion {
    NSString *ext = item.fileName.pathExtension.length ? item.fileName.pathExtension : @"mp4";
    NSString *dest = [documentsDir() stringByAppendingPathComponent:[self uniqueName:item.title ext:ext]];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        BOOL ok = [[NSFileManager defaultManager] copyItemAtURL:item.fileURL toURL:[NSURL fileURLWithPath:dest] error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) { completion(err.localizedDescription ?: @"Not enough space?"); return; }
            VGItem *n = [VGItem fromDict:[item dict]];
            n.fileName = dest.lastPathComponent;
            n.vault = NO;
            n.folderID = nil;
            n.favorite = NO;
            n.date = [NSDate date];
            if (item.artworkName.length) {
                NSString *name = [NSString stringWithFormat:@"art-%@.jpg", NSUUID.UUID.UUIDString];
                if ([[NSFileManager defaultManager] copyItemAtPath:item.artworkPath toPath:supportPath(name) error:nil]) n.artworkName = name;
            }
            [[NSFileManager defaultManager] copyItemAtPath:[item thumbPath] toPath:[n thumbPath] error:nil];
            [ws.library insertObject:n atIndex:0];
            [ws saveLibrary];
            completion(nil);
        });
    });
}

+ (BOOL)itemIsLossless:(VGItem *)item {
    NSString *codec = [VGConvert probe:item.fileURL.path][@"audio"] ?: @"";
    return [codec isEqualToString:@"flac"] || [codec isEqualToString:@"alac"] || [codec hasPrefix:@"pcm_"] || [codec isEqualToString:@"wavpack"];
}

/// Converts a sound file on disk to MP3, M4A, WAV or FLAC. `done` gets nil on success. Runs in the background.
+ (void)convertAudioFile:(NSString *)src to:(NSString *)dest format:(NSString *)format title:(NSString *)title artist:(NSString *)artist
                converter:(VGConvert *)converter progress:(void (^)(double))progress done:(void (^)(NSString *))done {
    if ([format isEqualToString:@"flac"]) {
        NSString *wav = [dest stringByAppendingString:@".tmp.wav"];
        [converter wavFrom:src to:wav progress:^(double f) { if (progress) progress(f * 0.7); } completion:^(NSString *err) {
            if (err) { done(err); return; }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSString *msg = nil;
                @try {
                    NSError *e = nil;
                    AVAudioFile *in = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:wav] error:&e];
                    if (!in) { msg = e.localizedDescription ?: @"Couldn't read the sound."; }
                    else {
                        NSDictionary *settings = @{AVFormatIDKey: @(kAudioFormatFLAC), AVSampleRateKey: @(in.fileFormat.sampleRate),
                                                   AVNumberOfChannelsKey: @(in.fileFormat.channelCount), AVLinearPCMBitDepthKey: @16};
                        AVAudioFile *out = [[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:dest] settings:settings
                                                                  commonFormat:in.processingFormat.commonFormat interleaved:in.processingFormat.interleaved error:&e];
                        if (!out) msg = e.localizedDescription ?: @"This iPhone can't make FLAC files.";
                        else {
                            AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:in.processingFormat frameCapacity:32768];
                            while (in.framePosition < in.length) {
                                if (![in readIntoBuffer:buf error:&e] || buf.frameLength == 0) break;
                                if (![out writeFromBuffer:buf error:&e]) { msg = e.localizedDescription ?: @"Couldn't write the FLAC file."; break; }
                                if (progress) progress(0.7 + 0.3 * ((double)in.framePosition / MAX(1.0, (double)in.length)));
                            }
                            out = nil;   // closing the file finishes it
                        }
                    }
                } @catch (NSException *ex) { msg = @"This iPhone can't make FLAC files."; }
                [[NSFileManager defaultManager] removeItemAtPath:wav error:nil];
                if (msg) [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{ done(msg); });
            });
        }];
    } else if ([format isEqualToString:@"wav"]) {
        [converter wavFrom:src to:dest progress:progress completion:done];
    } else {
        [converter audio:src to:dest mp3:[format isEqualToString:@"mp3"] title:title artist:artist progress:progress completion:done];
    }
}

- (void)convertAudioItem:(VGItem *)item toFormat:(NSString *)format progress:(void (^)(double))progress
              completion:(void (^)(VGItem *, NSString *))completion {
    NSString *ext = [format isEqualToString:@"m4a"] ? @"m4a" : format;
    NSString *dest = [documentsDir() stringByAppendingPathComponent:[self uniqueName:item.title ext:ext]];
    if (item.vault) dest = [vaultDir() stringByAppendingPathComponent:[self uniqueName:item.title ext:ext]];
    VGConvert *c = [VGConvert new];
    __weak typeof(self) ws = self;
    [VGEngine convertAudioFile:item.fileURL.path to:dest format:format title:item.title artist:item.artist converter:c progress:progress done:^(NSString *err) {
        if (err) { if (completion) completion(nil, err); return; }
        VGItem *n = [VGItem new];
        n.fileName = dest.lastPathComponent;
        n.title = item.title;
        n.artist = item.artist;
        n.album = item.album;
        n.site = item.site;
        n.audio = YES;
        n.res = [format uppercaseString];
        n.duration = item.duration;
        n.vault = item.vault;
        n.folderID = item.folderID;
        n.date = [NSDate date];
        n.bytes = [[[NSFileManager defaultManager] attributesOfItemAtPath:dest error:nil][NSFileSize] longLongValue];
        if (item.artworkName.length) {
            NSString *name = [NSString stringWithFormat:@"art-%@.jpg", NSUUID.UUID.UUIDString];
            if ([[NSFileManager defaultManager] copyItemAtPath:item.artworkPath toPath:supportPath(name) error:nil]) n.artworkName = name;
        }
        [ws.library insertObject:n atIndex:0];
        [ws saveLibrary];
        NSData *art = n.artworkName.length ? [NSData dataWithContentsOfFile:n.artworkPath] : nil;
        [VGAudioTags writeTitle:n.title artist:n.artist album:n.album artwork:art toPath:dest completion:^(NSString *tagErr) {
            n.bytes = [[[NSFileManager defaultManager] attributesOfItemAtPath:dest error:nil][NSFileSize] longLongValue];
            [ws saveLibrary];
            if (completion) completion(n, nil);
        }];
    }];
}

+ (VGOption *)presetOption:(NSString *)quality {
    VGOption *o = [VGOption new];
    BOOL mp3 = [quality isEqualToString:@"mp3"];
    o.identifier = [@"q:" stringByAppendingString:quality];
    o.res = mp3 ? @"MP3" : ([quality isEqualToString:@"best"] ? @"Best" : [quality stringByAppendingString:@"p"]);
    o.sizeText = @"";
    o.format = mp3 ? @"MP3" : @"MP4";
    o.photos = !mp3;
    o.audio = mp3;
    o.convert = NO;
    return o;
}

- (long long)totalBytes {
    long long t = 0;
    for (VGItem *i in self.library) t += i.bytes;
    return t;
}

#pragma mark Cookies

static NSString *baseDomain(NSString *host) {
    host = host.lowercaseString;
    if ([host isEqualToString:@"youtu.be"] || [host hasSuffix:@".youtu.be"]) return @"youtube.com";
    NSArray *parts = [host componentsSeparatedByString:@"."];
    if (parts.count <= 2) return host;
    NSString *last2 = [[parts subarrayWithRange:NSMakeRange(parts.count - 2, 2)] componentsJoinedByString:@"."];
    // Handle two-part country suffixes like co.uk, com.ph.
    NSSet *second = [NSSet setWithArray:@[@"co", @"com", @"net", @"org", @"gov", @"edu", @"ac"]];
    if ([second containsObject:parts[parts.count - 2]] && parts.count >= 3) {
        return [[parts subarrayWithRange:NSMakeRange(parts.count - 3, 3)] componentsJoinedByString:@"."];
    }
    return last2;
}

/// Writes the browser's cookies for this link's site to a Netscape cookie file for the engine.
- (void)cookiesFor:(NSString *)url completion:(void (^)(NSString *path))completion {
    NSString *host = [NSURL URLWithString:url].host;
    if (!host) { completion(@""); return; }
    NSString *domain = baseDomain(host);
    dispatch_async(dispatch_get_main_queue(), ^{
        [WKWebsiteDataStore.defaultDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
            NSMutableString *out = [NSMutableString stringWithString:@"# Netscape HTTP Cookie File\n"];
            NSUInteger n = 0;
            for (NSHTTPCookie *c in cookies) {
                NSString *d = c.domain.lowercaseString;
                NSString *bare = [d hasPrefix:@"."] ? [d substringFromIndex:1] : d;
                if (!([bare isEqualToString:domain] || [bare hasSuffix:[@"." stringByAppendingString:domain]])) continue;
                long long exp = c.expiresDate ? (long long)c.expiresDate.timeIntervalSince1970 : 0;
                [out appendFormat:@"%@\t%@\t%@\t%@\t%lld\t%@\t%@\n", d, [d hasPrefix:@"."] ? @"TRUE" : @"FALSE",
                    c.path ?: @"/", c.isSecure ? @"TRUE" : @"FALSE", exp, c.name, c.value];
                n++;
            }
            if (!n) { completion(@""); return; }
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"cookies.txt"];
            [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            completion(path);
        }];
    });
}

#pragma mark Fetch

- (void)fetch:(NSString *)url completion:(void (^)(VGVideo *, NSString *))completion {
    [self fetch:url extra:nil completion:completion];
}

- (void)directLinkFor:(VGVideo *)video option:(VGOption *)option completion:(void (^)(NSDictionary *, NSString *))completion {
    NSString *oid = option.identifier ?: @"best";
    NSString *extraJSON = video.extra ?: @"";
    [self cookiesFor:video.url completion:^(NSString *cookies) {
        [[VGPython shared] call:@"vgbridge" function:@"link"
                           args:@[video.url, oid, [VGPython shared].cacheDir, cookies ?: @"", extraJSON]
                     completion:^(NSDictionary *r, NSString *error) {
            if (!r) { completion(nil, error ?: @"Couldn't get the link."); return; }
            completion(r, nil);
        }];
    }];
}

- (void)linkListFor:(VGVideo *)video option:(VGOption *)option completion:(void (^)(NSDictionary *, NSString *))completion {
    NSString *oid = option.identifier ?: @"best";
    NSString *extraJSON = video.extra ?: @"";
    [self cookiesFor:video.url completion:^(NSString *cookies) {
        [[VGPython shared] call:@"vgbridge" function:@"links"
                           args:@[video.url, oid, [VGPython shared].cacheDir, cookies ?: @"", extraJSON]
                     completion:^(NSDictionary *r, NSString *error) {
            if (!r) { completion(nil, error ?: @"Couldn't get the links."); return; }
            completion(r, nil);
        }];
    }];
}

- (void)streamLinkFor:(VGVideo *)video option:(VGOption *)option completion:(void (^)(NSDictionary *, NSString *))completion {
    NSInteger maxH = 0;
    if (option && !option.audio) {
        NSString *r = option.res ?: @"";
        if ([r hasPrefix:@"4K"]) maxH = 2160;
        else if ([r hasPrefix:@"2K"]) maxH = 1440;
        else maxH = r.integerValue;
    }
    BOOL audio = option.audio;
    NSString *extraJSON = video.extra ?: @"";
    [self cookiesFor:video.url completion:^(NSString *cookies) {
        [[VGPython shared] call:@"vgbridge" function:@"stream"
                           args:@[video.url, [VGPython shared].cacheDir, cookies ?: @"", extraJSON, [NSString stringWithFormat:@"%ld", (long)maxH], audio ? @"1" : @"0"]
                     completion:^(NSDictionary *r, NSString *error) {
            if (!r) { completion(nil, error ?: @"Couldn't start the stream."); return; }
            completion(r, nil);
        }];
    }];
}

- (void)fetch:(NSString *)url extra:(NSDictionary *)extra completion:(void (^)(VGVideo *, NSString *))completion {
    NSString *extraJSON = @"";
    if ([extra isKindOfClass:NSDictionary.class] && extra.count && [NSJSONSerialization isValidJSONObject:extra]) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:extra options:0 error:nil];
        if (d) extraJSON = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
    }
    [self cookiesFor:url completion:^(NSString *cookies) {
    [[VGPython shared] call:@"vgbridge" function:@"fetch" args:@[url, [VGPython shared].cacheDir, cookies, extraJSON]
                 completion:^(NSDictionary *r, NSString *error) {
        if (!r) { completion(nil, error); return; }
        VGVideo *v = [VGVideo new];
        v.url = url;
        v.extra = extraJSON.length ? extraJSON : nil;
        if ([r[@"playlist"] boolValue]) {
            v.title = [r[@"title"] isKindOfClass:NSString.class] ? r[@"title"] : @"Playlist";
            v.uploader = [r[@"uploader"] isKindOfClass:NSString.class] && [r[@"uploader"] length] ? r[@"uploader"] : nil;
            v.site = [r[@"site"] isKindOfClass:NSString.class] ? r[@"site"] : nil;
            v.thumbnail = [r[@"thumbnail"] isKindOfClass:NSString.class] ? r[@"thumbnail"] : nil;
            v.options = @[];
            NSMutableArray *list = [NSMutableArray array];
            double total = 0;
            for (NSDictionary *e in [r[@"entries"] isKindOfClass:NSArray.class] ? r[@"entries"] : @[]) {
                if (![e isKindOfClass:NSDictionary.class] || ![e[@"url"] isKindOfClass:NSString.class]) continue;
                VGVideo *x = [VGVideo new];
                x.url = e[@"url"];
                x.title = [e[@"title"] isKindOfClass:NSString.class] ? e[@"title"] : @"Untitled video";
                x.duration = [e[@"duration"] isKindOfClass:NSNumber.class] ? [e[@"duration"] doubleValue] : 0;
                x.thumbnail = [e[@"thumbnail"] isKindOfClass:NSString.class] ? e[@"thumbnail"] : nil;
                x.site = v.site;
                x.uploader = v.uploader;
                x.options = @[];
                total += x.duration;
                [list addObject:x];
            }
            v.entries = list;
            v.duration = total;
            completion(v, nil);
            return;
        }
        v.title = r[@"title"] ?: @"Untitled video";
        v.uploader = [r[@"uploader"] isKindOfClass:NSString.class] ? r[@"uploader"] : nil;
        v.site = [r[@"site"] isKindOfClass:NSString.class] ? r[@"site"] : nil;
        v.thumbnail = [r[@"thumbnail"] isKindOfClass:NSString.class] ? r[@"thumbnail"] : nil;
        v.duration = [r[@"duration"] isKindOfClass:NSNumber.class] ? [r[@"duration"] doubleValue] : 0;
        NSMutableArray *opts = [NSMutableArray array];
        for (NSDictionary *o in r[@"options"]) {
            VGOption *x = [VGOption new];
            x.identifier = o[@"id"];
            x.res = o[@"res"] ?: @"";
            x.sizeText = o[@"size_text"] ?: @"";
            x.format = o[@"fmt"] ?: @"";
            x.photos = [o[@"photos"] boolValue];
            x.audio = [o[@"audio"] boolValue];
            x.convert = [o[@"convert"] boolValue];
            [opts addObject:x];
        }
        v.options = opts;
        completion(v, nil);
    }];
    }];
}

#pragma mark Download queue

static const NSUInteger kMaxRunning = 10;   // downloads at the same time
static const NSUInteger kMaxHeavy = 2;      // re-encodes at the same time

static NSString *formatSpeed(double bps) {
    if (bps <= 0) return nil;
    return [[NSByteCountFormatter stringFromByteCount:(long long)bps countStyle:NSByteCountFormatterCountStyleFile]
            stringByAppendingString:@"/s"];
}

static NSString *formatETA(double s) {
    if (s < 0) return nil;
    int t = (int)s;
    if (t >= 3600) return [NSString stringWithFormat:@"%d:%02d:%02d left", t / 3600, t / 60 % 60, t % 60];
    return [NSString stringWithFormat:@"%d:%02d left", t / 60, t % 60];
}

- (NSArray<VGTask *> *)tasks { return [self.queue copy] ?: @[]; }

- (NSUInteger)activeCount {
    NSUInteger n = 0;
    for (VGTask *t in self.queue) if (t.state == VGTaskQueued || t.state == VGTaskRunning) n++;
    return n;
}

- (VGTask *)leadTask {
    for (VGTask *t in self.queue) if (t.state == VGTaskRunning) return t;
    for (VGTask *t in self.queue) if (t.state == VGTaskQueued) return t;
    return nil;
}

- (void)post:(VGTask *)task force:(BOOL)force {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!force && task && now - task.lastPost < 0.2) return;  // keep the UI smooth
    task.lastPost = now;
    [NSNotificationCenter.defaultCenter postNotificationName:VGTasksDidChangeNotification object:task];
}

- (void)update:(VGTask *)task fraction:(double)f stage:(NSString *)stage detail:(NSString *)detail {
    if (task.state == VGTaskPaused || task.state == VGTaskCancelled) return;
    task.fraction = MAX(0, MIN(1, f));
    if (stage) task.stage = stage;
    if (detail) task.detail = detail;
    if (task.progressHandler) task.progressHandler(task.fraction, task.stage, task.detail);
    [self post:task force:NO];
}

// ---- Resume after the app closes or crashes ----
static NSString *resumeRoot(void) {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *d = [base stringByAppendingPathComponent:@"VidGrabResume"];
    [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
static NSString *resumeFile(void) { return [resumeRoot() stringByAppendingPathComponent:@"pending.json"]; }

/// True when downloads are running or were cut off and are waiting to resume. Cache clearing leaves the engine's cache alone then.
+ (BOOL)hasUnfinishedDownloads {
    if ([VGEngine shared].activeCount > 0) return YES;
    NSData *d = [NSData dataWithContentsOfFile:resumeFile()];
    NSArray *list = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [list isKindOfClass:NSArray.class] && list.count > 0;
}

+ (BOOL)hasUnfinished {
    NSData *d = [NSData dataWithContentsOfFile:resumeFile()];
    NSArray *l = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [l isKindOfClass:NSArray.class] && l.count > 0;
}

- (void)savePending {
    NSMutableArray *out = [NSMutableArray array];
    for (VGTask *t in self.queue) {
        if (t.state != VGTaskQueued && t.state != VGTaskRunning && t.state != VGTaskPaused) continue;
        if (!t.resumeKey || !t.video.url) continue;
        VGOption *o = t.option;
        [out addObject:@{@"key": t.resumeKey, @"paused": @(t.state == VGTaskPaused), @"url": t.video.url, @"title": t.video.title ?: @"",
                         @"uploader": t.video.uploader ?: @"", @"site": t.video.site ?: @"",
                         @"thumb": t.video.thumbnail ?: @"", @"duration": @(isfinite(t.video.duration) ? t.video.duration : 0), @"extra": t.video.extra ?: @"",
                         @"opt": @{@"id": o.identifier ?: @"", @"res": o.res ?: @"", @"size": o.sizeText ?: @"", @"fmt": o.format ?: @"",
                                   @"photos": @(o.photos), @"audio": @(o.audio), @"convert": @(o.convert)}}];
    }
    NSData *d = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
    if (d) [d writeToFile:resumeFile() atomically:YES];
}

/// Called once at launch: puts back every download that was still going when the app closed.
- (void)resumePending {
    NSData *d = [NSData dataWithContentsOfFile:resumeFile()];
    NSArray *list = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    if (![list isKindOfClass:NSArray.class]) return;
    NSMutableSet *keep = [NSMutableSet set];
    for (NSDictionary *e in list) {
        if (![e isKindOfClass:NSDictionary.class] || ![e[@"url"] length] || ![e[@"key"] length]) continue;
        VGVideo *v = [VGVideo new];
        v.url = e[@"url"]; v.title = e[@"title"];
        v.uploader = [e[@"uploader"] length] ? e[@"uploader"] : nil;
        v.site = [e[@"site"] length] ? e[@"site"] : nil;
        v.thumbnail = [e[@"thumb"] length] ? e[@"thumb"] : nil;
        v.duration = [e[@"duration"] doubleValue];
        v.extra = [e[@"extra"] length] ? e[@"extra"] : nil;
        NSDictionary *od = e[@"opt"];
        VGOption *o = [VGOption new];
        o.identifier = od[@"id"]; o.res = od[@"res"]; o.sizeText = od[@"size"]; o.format = od[@"fmt"];
        o.photos = [od[@"photos"] boolValue]; o.audio = [od[@"audio"] boolValue]; o.convert = [od[@"convert"] boolValue];
        v.options = @[o];
        [keep addObject:e[@"key"]];
        BOOL wasPaused = [e[@"paused"] boolValue];
        self.nextStartsPaused = wasPaused;
        VGTask *t = [self download:v option:o progress:nil completion:nil key:e[@"key"]];
        self.nextStartsPaused = NO;
        if (!wasPaused) t.stage = @"Resuming…";
    }
    // Throw away partial files that no longer belong to any download.
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *n in [fm contentsOfDirectoryAtPath:resumeRoot() error:nil])
        if (![n isEqualToString:@"pending.json"] && ![keep containsObject:n])
            [fm removeItemAtPath:[resumeRoot() stringByAppendingPathComponent:n] error:nil];
}

- (VGTask *)download:(VGVideo *)video option:(VGOption *)option progress:(VGProgress)progress
          completion:(void (^)(VGItem *, NSString *))completion {
    return [self download:video option:option progress:progress completion:completion key:nil];
}

- (VGTask *)download:(VGVideo *)video option:(VGOption *)option progress:(VGProgress)progress
          completion:(void (^)(VGItem *, NSString *))completion key:(NSString *)key {
    if (!self.queue) self.queue = [NSMutableArray array];
    VGTask *t = [VGTask new];
    t.identifier = [NSString stringWithFormat:@"t%lu", (unsigned long)++self.nextTaskID];
    t.video = video;
    t.option = option;
    t.resumeKey = key ?: NSUUID.UUID.UUIDString;
    t.state = self.nextStartsPaused ? VGTaskPaused : VGTaskQueued;
    t.stage = self.nextStartsPaused ? @"Paused" : @"Waiting…";
    t.detail = [NSString stringWithFormat:@"%@ · %@", option.res, option.sizeText.length ? option.sizeText : option.format];
    t.progressHandler = progress;
    t.completionHandler = completion;
    [self.queue addObject:t];
    [self savePending];
    [self post:t force:YES];
    [self pump];
    return t;
}

- (void)pump {
    NSUInteger running = 0;
    for (VGTask *t in self.queue) if (t.state == VGTaskRunning) running++;
    for (VGTask *t in self.queue) {
        if (running >= kMaxRunning) break;
        if (t.state != VGTaskQueued) continue;
        running++;
        [self run:t];
    }
    UIApplication.sharedApplication.idleTimerDisabled = self.activeCount > 0;
}

- (void)cancelTask:(VGTask *)task {
    if (task.state == VGTaskQueued || task.state == VGTaskPaused) {
        [self finish:task item:nil error:@"Cancelled." work:nil];
        return;
    }
    if (task.state != VGTaskRunning) return;
    // Stop everything at once, and show it straight away: the engine may take a moment to notice, but the download
    // is already gone from the list and anything it finishes later is ignored.
    [[VGPython shared] cancelTask:task.identifier];
    [self dropWaitingHeavy:task];
    [task.export cancelExport];
    [task.transcoder cancel];
    [task.converter cancel];
    [self finish:task item:nil error:@"Cancelled." work:nil];
}

- (void)pauseTask:(VGTask *)task {
    if (task.state != VGTaskRunning || !task.pyRunning) return;   // only while the file is being downloaded
    task.state = VGTaskPaused;
    task.stage = @"Paused";
    task.detail = @"";
    [[VGPython shared] cancelTask:task.identifier];   // stops the transfer; the half-finished file is kept
    [self savePending];
    [self post:task force:YES];
    [self pump];
}

- (void)resumeTask:(VGTask *)task {
    if (task.state != VGTaskPaused) return;
    if (task.pyRunning) {   // still winding down: start as soon as it has stopped
        task.wantsResume = YES;
        task.stage = @"Resuming…";
        [self post:task force:YES];
        return;
    }
    task.state = VGTaskQueued;
    task.stage = @"Waiting…";
    [self savePending];
    [self post:task force:YES];
    [self pump];
}

- (void)retryTask:(VGTask *)task {
    if (task.state != VGTaskFailed) return;
    task.state = VGTaskQueued;
    task.error = nil;
    task.fraction = 0;
    task.stage = @"Waiting…";
    [self savePending];
    [self post:task force:YES];
    [self pump];
}

- (void)dismissTask:(VGTask *)task {
    if (task.state == VGTaskQueued || task.state == VGTaskRunning) return;
    [self.queue removeObject:task];
    [self post:nil force:YES];
}

- (void)finish:(VGTask *)task item:(VGItem *)item error:(NSString *)err work:(NSString *)work {
    if (task.state == VGTaskCancelled || task.state == VGTaskDone) return;   // already finished (e.g. cancelled a moment ago)
    if (!task.pyRunning) [[VGPython shared] forgetTask:task.identifier];   // otherwise the engine still needs to see the cancel
    BOOL keepPartial = !item && err.length && ![err isEqualToString:@"Cancelled."];  // a failed one keeps its partial files for Retry
    if (work && !keepPartial) [NSFileManager.defaultManager removeItemAtPath:work error:nil];
    task.export = nil;
    task.transcoder = nil;
    task.converter = nil;
    task.item = item;
    task.error = err;
    if (item) task.state = VGTaskDone;
    else if ([err isEqualToString:@"Cancelled."]) task.state = VGTaskCancelled;
    else task.state = VGTaskFailed;
    if (task.state != VGTaskFailed) [self.queue removeObject:task];  // failed ones stay so they can be retried
    if (task.resumeKey && !keepPartial) [NSFileManager.defaultManager removeItemAtPath:[resumeRoot() stringByAppendingPathComponent:task.resumeKey] error:nil];
    [self savePending];
    if (task.completionHandler) task.completionHandler(item, err);
    [NSNotificationCenter.defaultCenter postNotificationName:VGTaskFinishedNotification object:task];
    [self post:task force:YES];
    [self pump];
}

- (void)run:(VGTask *)task {
    task.state = VGTaskRunning;
    task.stage = @"Starting…";
    [self post:task force:YES];
    VGPython *py = [VGPython shared];
    VGVideo *video = task.video;
    VGOption *option = task.option;
    BOOL heavy = option.convert;
    double share = heavy ? 0.45 : (option.audio ? 0.7 : 0.9);  // part of the bar used by the download itself

    // Kept between launches (not wiped) so a download that was cut off carries on from its partial files.
    NSString *work = [resumeRoot() stringByAppendingPathComponent:task.resumeKey];
    [NSFileManager.defaultManager createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];

    __weak typeof(self) ws = self;
    [py setProgressHandler:^(int part, int parts, double frac, NSString *stage, double speed, double eta) {
        if ([stage isEqualToString:@"retry"]) {
            [ws update:task fraction:0 stage:@"YouTube blocked it, trying another way…" detail:@"This can take a few extra seconds"];
            return;
        }
        double overall = parts > 1 ? (part + frac) / parts : frac;
        NSString *what = [stage isEqualToString:@"audio"] ? @"Downloading audio" : @"Downloading video";
        if (parts > 1) what = [what stringByAppendingFormat:@" (%d of %d)", part + 1, parts];
        NSMutableArray *bits = [NSMutableArray array];
        if (formatSpeed(speed)) [bits addObject:formatSpeed(speed)];
        if (formatETA(eta)) [bits addObject:formatETA(eta)];
        [ws update:task fraction:overall * share stage:what detail:[bits componentsJoinedByString:@" · "]];
    } forTask:task.identifier];

    task.pyRunning = YES;
    [self cookiesFor:video.url completion:^(NSString *cookies) {
        [py call:@"vgbridge" function:@"download" args:@[task.identifier, video.url, option.identifier, work, py.cacheDir, cookies, video.extra ?: @""]
      completion:^(NSDictionary *r, NSString *error) {
            task.pyRunning = NO;
            if (task.state != VGTaskRunning) {   // paused or cancelled while it was working
                [py forgetTask:task.identifier];
                if (task.state == VGTaskPaused && task.wantsResume) {
                    task.wantsResume = NO;
                    task.state = VGTaskQueued;
                    task.stage = @"Waiting…";
                    [ws savePending];
                    [ws post:task force:YES];
                    [ws pump];
                }
                return;
            }
            if (!r) { [ws finish:task item:nil error:error work:work]; return; }
            [ws postProcess:task result:r work:work share:share];
        }];
    }];
}

/// Re-encoding uses the phone's video encoder, which only handles a couple of jobs well at once.
/// Extra jobs wait their turn; call heavyDone when finished.
- (void)heavy:(VGTask *)task work:(void (^)(void))work {
    if (!self.heavyWaiting) self.heavyWaiting = [NSMutableArray array];
    if (self.heavyRunning < kMaxHeavy) { self.heavyRunning++; work(); }
    else [self.heavyWaiting addObject:@[task, [work copy]]];
}

- (void)heavyDone {
    if (self.heavyRunning) self.heavyRunning--;
    if (self.heavyWaiting.count && self.heavyRunning < kMaxHeavy) {
        void (^next)(void) = self.heavyWaiting.firstObject[1];
        [self.heavyWaiting removeObjectAtIndex:0];
        self.heavyRunning++;
        next();
    }
}

/// A cancelled task that is still waiting for its turn to convert: let it finish right away.
- (void)dropWaitingHeavy:(VGTask *)task {
    for (NSArray *e in [self.heavyWaiting copy]) {
        if (e[0] != task) continue;
        [self.heavyWaiting removeObject:e];
        self.heavyRunning++;          // the block calls heavyDone itself
        ((void (^)(void))e[1])();
    }
}

- (NSString *)uniqueName:(NSString *)base ext:(NSString *)ext {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *name = [NSString stringWithFormat:@"%@.%@", base, ext];
    for (int n = 2; [fm fileExistsAtPath:[documentsDir() stringByAppendingPathComponent:name]]; n++) {
        name = [NSString stringWithFormat:@"%@ (%d).%@", base, n, ext];
    }
    return name;
}


#pragma mark Checking converted videos

- (void)note:(NSString *)line {
    if (!self.convLog) self.convLog = [NSMutableString string];
    [self.convLog appendFormat:@"%@ %@\n", [NSDate date], line];
    if (self.convLog.length > 6000) [self.convLog deleteCharactersInRange:NSMakeRange(0, self.convLog.length - 6000)];
    [VGCrash breadcrumb:[@"convert: " stringByAppendingString:line]];
}

/// Average brightness (0-255) of an image, from a tiny downscaled copy.
static double brightness(CGImageRef img) {
    uint8_t px[16 * 16 * 4] = {0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(px, 16, 16, 8, 16 * 4, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!c) return 255;
    CGContextDrawImage(c, CGRectMake(0, 0, 16, 16), img);
    CGContextRelease(c);
    double sum = 0;
    for (int i = 0; i < 16 * 16; i++) sum += (px[i * 4] + px[i * 4 + 1] + px[i * 4 + 2]) / 3.0;
    return sum / (16 * 16);
}

/// Returns nil if the file plays as a real video on this iPhone, otherwise what's wrong.
- (NSString *)problemWithVideo:(NSString *)path checkBlack:(BOOL)checkBlack {
    AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetTrack *vt = [a tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!vt) return @"no video track";
    double secs = CMTimeGetSeconds(a.duration);
    if (!(secs > 0)) return @"zero length";
    if (!vt.isPlayable && !a.isPlayable) return @"iPhone can't play it";
    AVAssetImageGenerator *g = [AVAssetImageGenerator assetImageGeneratorWithAsset:a];
    g.appliesPreferredTrackTransform = YES;
    g.maximumSize = CGSizeMake(160, 160);
    g.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(2, 600);
    g.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(2, 600);
    int got = 0;
    double maxBright = 0;
    for (NSNumber *f in @[@0.15, @0.5, @0.85]) {
        NSError *e = nil;
        CGImageRef img = [g copyCGImageAtTime:CMTimeMakeWithSeconds(secs * f.doubleValue, 600) actualTime:NULL error:&e];
        if (!img) continue;
        got++;
        maxBright = MAX(maxBright, brightness(img));
        CGImageRelease(img);
    }
    if (!got) return @"no picture could be read";
    if (checkBlack && maxBright < 6) return [NSString stringWithFormat:@"picture is black (brightness %.1f)", maxBright];
    return nil;
}

- (void)verify:(NSString *)path black:(BOOL)black completion:(void (^)(NSString *problem))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *p = [self problemWithVideo:path checkBlack:black];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(p); });
    });
}

// A hidden temporary file in Documents: same volume as the final folder (so the last step is one atomic rename),
// a dot name (kept out of the Files app) and an .mp4 ending (AVFoundation decides what a file is by its ending).
static NSString *partialPath(void) {
    return [documentsDir() stringByAppendingPathComponent:[NSString stringWithFormat:@".partial-%@.mp4", NSUUID.UUID.UUIDString]];
}

static NSString *noDot(NSString *s) {
    NSString *t = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([t hasSuffix:@"."]) t = [t substringToIndex:t.length - 1];
    return t;
}

/// Puts a finished, checked file into Documents under a name nobody else has, in one step. renamex_np with
/// RENAME_EXCL never overwrites, so two downloads with the same title can't clobber each other.
- (NSString *)installPartial:(NSString *)partial base:(NSString *)base error:(NSString **)error {
    for (int attempt = 0; attempt < 25; attempt++) {
        NSString *dest = [documentsDir() stringByAppendingPathComponent:[self uniqueName:base ext:@"mp4"]];
        if (renamex_np(partial.fileSystemRepresentation, dest.fileSystemRepresentation, RENAME_EXCL) == 0) return dest;
        if (errno != EEXIST) {
            if (error) *error = [NSString stringWithFormat:@"couldn't save the finished video (%s)", strerror(errno)];
            return nil;
        }
    }
    if (error) *error = @"couldn't find a free name for the finished video";
    return nil;
}

/// A download that couldn't become an MP4 is never thrown away: the originals move out of the temporary work folder
/// (which is wiped when the task ends) into Downloads. Returns the name of the first one kept, or nil if none could be.
- (NSString *)keepOriginals:(NSArray<NSString *> *)paths labels:(NSArray<NSString *> *)labels base:(NSString *)base task:(VGTask *)task {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *firstName = nil;
    for (NSUInteger i = 0; i < paths.count; i++) {
        NSString *path = paths[i];
        if (![fm fileExistsAtPath:path]) continue;
        NSDictionary *p = [VGConvert probe:path];
        NSString *c = p[@"container"] ?: @"";
        NSString *ext = path.pathExtension.lowercaseString.length ? path.pathExtension.lowercaseString : @"mp4";
        if ([c isEqualToString:@"mpegts"]) ext = @"ts";
        else if ([c hasPrefix:@"matroska"]) ext = [ext isEqualToString:@"webm"] ? @"webm" : @"mkv";
        else if ([c isEqualToString:@"flv"]) ext = @"flv";
        NSString *label = labels.count > i ? labels[i] : @"";
        NSString *name = label.length ? [NSString stringWithFormat:@"%@ (%@)", base, label] : base;
        NSString *dest = [documentsDir() stringByAppendingPathComponent:[self uniqueName:name ext:ext]];
        NSError *e = nil;
        if (![fm moveItemAtPath:path toPath:dest error:&e] && ![fm copyItemAtPath:path toPath:dest error:&e]) continue;
        VGItem *item = [VGItem new];
        item.fileName = dest.lastPathComponent;
        item.title = label.length ? [NSString stringWithFormat:@"%@ (%@)", task.video.title, label] : task.video.title;
        item.site = task.video.site;
        item.res = task.option.res;
        item.duration = task.video.duration;
        item.audio = c.length && ![p[@"video"] length];
        item.photos = NO;
        item.date = [NSDate date];
        item.bytes = [[fm attributesOfItemAtPath:dest error:nil][NSFileSize] longLongValue];
        [self makeThumbnailFor:item fallbackURL:task.video.thumbnail];
        [self.library insertObject:item atIndex:0];
        if (!firstName) firstName = dest.lastPathComponent;
    }
    if (firstName) [self saveLibrary];
    return firstName;
}

/// Turns the downloaded file(s) into the final MP4 / M4A / MP3 in Documents.
///
/// Video never gets written over anything: the MP4 is built as a hidden partial file, checked natively
/// (vg_validate_mp4), checked again with AVFoundation, and only then renamed into place. If anything fails the
/// partial is deleted and the downloaded originals are kept in Downloads (keepOriginals), with an explanation.
- (void)postProcess:(VGTask *)task result:(NSDictionary *)r work:(NSString *)work share:(double)share {
    // Some sites glue a fake picture header in front of every piece of a stream. Strip it first (once), so everything
    // below sees a normal transport stream.
    if (!r[@"_cleaned"] && !isAudioKind(r[@"kind"]) && [r[@"files"] count]) {
        NSArray<NSString *> *orig = r[@"files"];
        __weak typeof(self) wsc = self;
        [self update:task fraction:share stage:@"Checking the file" detail:@""];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray<NSString *> *now = [NSMutableArray new];
            NSMutableArray<NSString *> *lines = [NSMutableArray new];
            for (NSUInteger i = 0; i < orig.count; i++) {
                NSString *f = orig[i];
                NSString *out = [work stringByAppendingPathComponent:[NSString stringWithFormat:@"clean%lu.ts", (unsigned long)i]];
                NSDictionary *c = [VGConvert tsClean:f to:out];   // decided by what is inside, never by the file name
                if (c[@"path"]) {
                    [now addObject:c[@"path"]];
                    [lines addObject:[NSString stringWithFormat:@"[Media] cleaned %@: removed %.1f KB of junk between %@ pieces", f.lastPathComponent, [c[@"junk"] doubleValue] / 1024.0, c[@"pieces"]]];
                } else {
                    [now addObject:f];
                    if (c[@"error"]) [lines addObject:[NSString stringWithFormat:@"[Media] clean skipped for %@: %@", f.lastPathComponent, c[@"error"]]];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                for (NSString *l in lines) [wsc note:l];
                NSMutableDictionary *r2 = [r mutableCopy];
                r2[@"files"] = now;
                r2[@"_cleaned"] = @YES;
                [wsc postProcess:task result:r2 work:work share:share];
            });
        });
        return;
    }
    NSArray<NSString *> *files = r[@"files"];
    NSString *kind = r[@"kind"];
    NSString *base = r[@"name"] ?: @"video";
    NSString *first = files.firstObject;
    VGVideo *video = task.video;
    VGOption *option = task.option;
    __weak typeof(self) ws = self;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *labels = files.count > 1 ? @[@"video part", @"sound part"] : nil;

    void (^store)(NSString *, BOOL) = ^(NSString *path, BOOL photos) {
        if ([[VGPython shared] isTaskCancelled:task.identifier]) {
            [fm removeItemAtPath:path error:nil];
            [ws finish:task item:nil error:@"Cancelled." work:work];
            return;
        }
        VGItem *item = [VGItem new];
        item.fileName = path.lastPathComponent;
        item.title = video.title;
        item.site = video.site;
        item.res = option.res;
        item.duration = video.duration;
        item.audio = option.audio;
        if (option.audio && video.uploader.length && ![video.uploader isEqualToString:video.site]) item.artist = video.uploader;
        item.photos = photos && !option.audio;
        item.date = [NSDate date];
        item.bytes = [[fm attributesOfItemAtPath:path error:nil][NSFileSize] longLongValue];
        [ws makeThumbnailFor:item fallbackURL:video.thumbnail];
        [ws.library insertObject:item atIndex:0];
        [ws saveLibrary];
        [ws finish:task item:item error:nil work:work];
        if (item.audio && VGCoverSearch.autoEnabled) [ws autoCoverFor:item];
    };
    void (^fail)(NSString *) = ^(NSString *err) { [ws finish:task item:nil error:err work:work]; };

    NSString *partial = partialPath();
    void (^media)(NSString *) = ^(NSString *line) { [ws note:[@"[Media] " stringByAppendingString:line]]; };
    void (^dropPartial)(void) = ^{ [fm removeItemAtPath:partial error:nil]; };
    NSString *(^cant)(NSString *) = ^NSString *(NSString *reason) {
        return [NSString stringWithFormat:@"Couldn't turn this into an MP4 (%@)", noDot(reason)];
    };
    // Conversion didn't work out: drop the half-made file, keep what was downloaded, and say so.
    void (^keepAndFail)(NSString *, NSArray<NSString *> *, NSArray<NSString *> *) = ^(NSString *why, NSArray<NSString *> *paths, NSArray<NSString *> *names) {
        dropPartial();
        for (NSString *kf in paths) {   // a raw TS that couldn't be converted: record what its packets really hold
            if ([[VGConvert probe:kf][@"container"] isEqualToString:@"mpegts"]) {
                [ws note:[NSString stringWithFormat:@"[Media] ts scan of %@:\n%@", kf.lastPathComponent, [VGConvert tsScan:kf][@"text"]]];
                break;
            }
        }
        NSString *kept = [ws keepOriginals:paths labels:names base:base task:task];
        media([NSString stringWithFormat:@"fallback: %@ | %@", noDot(why), kept ? [@"original kept as " stringByAppendingString:kept] : @"original could not be moved"]);
        fail(kept ? [NSString stringWithFormat:@"%@. The original download was kept in your Downloads as \u201C%@\u201D.", noDot(why), kept]
                  : [NSString stringWithFormat:@"%@.", noDot(why)]);
    };
    // The checked partial file becomes the final MP4 in one step. Only after that is the task finished,
    // which is what wipes the work folder holding the originals.
    void (^install)(void) = ^{
        NSString *e = nil;
        NSString *dest = [ws installPartial:partial base:base error:&e];
        if (!dest) { keepAndFail(cant(e ?: @"couldn't save the finished file"), files, labels); return; }
        media([@"output: " stringByAppendingString:dest]);
        store(dest, YES);
    };
    void (^stageP)(NSString *) = ^(NSString *what) { [ws update:task fraction:share stage:what detail:@""]; };
    void (^(^convertProgress)(NSString *))(double) = ^(NSString *what) {
        return ^(double f) { [ws update:task fraction:share + f * (0.99 - share) stage:what detail:[NSString stringWithFormat:@"%d%% done", (int)(f * 100)]]; };
    };
    // Second check, with Apple's own reader: it must open, play and show a real picture. Then install.
    void (^checkAndInstall)(BOOL, void (^)(NSString *)) = ^(BOOL black, void (^onProblem)(NSString *)) {
        stageP(@"Checking the video");
        [ws verify:partial black:black completion:^(NSString *problem) {
            if (problem) { media([@"validation: AVFoundation failed: " stringByAppendingString:problem]); onProblem(problem); return; }
            media(@"validation: AVFoundation OK");
            install();
        }];
    };
    void (^logSource)(void) = ^{
        for (NSString *f in files) {
            NSDictionary *pr = [VGConvert probe:f];
            media([NSString stringWithFormat:@"source: %@ | container %@ | video %@ %@x%@ | audio %@ | %@ s | route %@", f.lastPathComponent,
                   pr[@"container"], pr[@"video"], pr[@"width"], pr[@"height"], pr[@"audio"], pr[@"duration"], kind]);
        }
    };
    void (^logMux)(NSDictionary *, NSString *) = ^(NSDictionary *info, NSString *err) {
        media([NSString stringWithFormat:@"strategy: %@", info[@"strategy"] ?: @"?"]);
        media([NSString stringWithFormat:@"result: %@ | timestamp jumps smoothed: %@ | leading packets skipped: %@ | video packets %@ in, %@ out, %@ lost",
               err ? [@"failed: " stringByAppendingString:noDot(err)] : @"ok", info[@"discontinuities"], info[@"leadingDropped"],
               info[@"videoIn"], info[@"videoOut"], info[@"videoLost"]]);
        if ([info[@"gapSeconds"] doubleValue] > 1.0) media([NSString stringWithFormat:@"note: the timeline has %.1f s of gaps (a missing piece of the original)", [info[@"gapSeconds"] doubleValue]]);
        media([@"validation: native " stringByAppendingString:info[@"validation"] ?: @"?"]);
    };
    if (!isAudioKind(kind)) logSource();

    // VP9/VP8 -> HEVC (needs an AAC track to copy; make one from the file's own sound if needed).
    void (^reencode)(NSString *, NSString *) = ^(NSString *videoPath, NSString *audioPath) {
        void (^go)(NSString *) = ^(NSString *aac) {
          if (ws.heavyRunning >= kMaxHeavy) [ws update:task fraction:share stage:@"Waiting to convert" detail:@"Other videos are converting"];
          [ws heavy:task work:^{
            if ([[VGPython shared] isTaskCancelled:task.identifier]) { [ws heavyDone]; dropPartial(); fail(@"Cancelled."); return; }
            stageP(@"Converting for iPhone");
            media(@"strategy: full video re-encode on the phone's encoder (HEVC, or H.264 on older phones)");
            task.transcoder = [VGTranscoder new];
            [task.transcoder convertVideo:[NSURL fileURLWithPath:videoPath] audio:aac ? [NSURL fileURLWithPath:aac] : nil to:[NSURL fileURLWithPath:partial]
                                 progress:convertProgress(@"Converting for iPhone \u00B7 keep the app open")
                               completion:^(NSString *err) {
                [ws heavyDone];
                if ([err isEqualToString:@"Cancelled."]) { dropPartial(); fail(err); return; }
                if (err) { media([@"result: failed: " stringByAppendingString:noDot(err)]); keepAndFail(cant(err), files, labels); return; }
                checkAndInstall(YES, ^(NSString *problem) {
                    keepAndFail(@"This quality couldn't be converted on your iPhone (the picture came out blank). Please pick 1080p or lower, and tap Copy details to send the developer what happened", files, labels);
                });
            }];
          }];
        };
        NSDictionary *pa = audioPath ? [VGConvert probe:audioPath] : [VGConvert probe:videoPath];
        NSString *src = audioPath ?: videoPath;
        if (![pa[@"audio"] length]) { go(nil); return; }
        if ([pa[@"audio"] isEqualToString:@"aac"] && audioPath) { go(audioPath); return; }
        NSString *aac = [work stringByAppendingPathComponent:@"sound.m4a"];
        stageP(@"Preparing sound");
        task.converter = [VGConvert new];
        [task.converter audio:src to:aac mp3:NO title:nil artist:nil progress:nil completion:^(NSString *err) {
            if (err) { keepAndFail(cant(err), files, labels); return; }
            go(aac);
        }];
    };

    // A video download that came out with no picture at all: say so (the sound is kept) instead of saving a black file.
    if (!option.audio && ![kind isEqualToString:@"mp3"] && ![kind isEqualToString:@"audio"] && first) {
        NSString *vfile = first;
        NSDictionary *vp = [VGConvert probe:vfile];
        if ([vp[@"container"] length] && ![vp[@"video"] length]) {   // only when FFmpeg could read the file
            [self note:[NSString stringWithFormat:@"no picture in %@ (%@):\n%@", vfile.lastPathComponent, vp[@"container"], [VGConvert describe:vfile]]];
            NSDictionary *scan = [vp[@"container"] isEqualToString:@"mpegts"] ? [VGConvert tsScan:vfile] : nil;
            NSString *why = @"This video came through with sound only, no picture. The site may lock its video so it can't be saved, or it sends picture and sound separately in a way VidGrab can't read yet. Try another quality, and tap Copy details to send the developer the link";
            if ([scan[@"scrambled"] longValue] > 0) {
                why = @"This video is encrypted by the site (its data is scrambled), so only some of it can be read and no picture came out. It can't be played or converted";
            } else if ([scan[@"text"] containsString:@"SAMPLE-AES"]) {
                why = @"This video is locked with the site's own encryption, so the picture can't be read. It can't be played or converted";
            }
            keepAndFail(why, files, labels);
            return;
        }
    }

    if ([kind isEqualToString:@"merge"] && files.count >= 2) {
        stageP(@"Joining video and sound");
        NSString *vPath = files[0], *aPath = files[1];
        void (^appleBackup)(NSString *) = ^(NSString *why) {
            media([@"fallback: FFmpeg route failed (" stringByAppendingString:[noDot(why) stringByAppendingString:@"), trying Apple's join"]]);
            dropPartial();
            [ws mergeVideo:[NSURL fileURLWithPath:vPath] audio:[NSURL fileURLWithPath:aPath] to:[NSURL fileURLWithPath:partial] task:task completion:^(NSString *err) {
                if ([err isEqualToString:@"Cancelled."]) { dropPartial(); fail(err); return; }
                if (err) { keepAndFail(cant(err), files, labels); return; }
                checkAndInstall(NO, ^(NSString *problem) {
                    keepAndFail(@"The video and sound couldn't be joined into a playable file. Tap Copy details and send them to the developer", files, labels);
                });
            }];
        };
        task.converter = [VGConvert new];
        [task.converter mux:vPath audio:aPath to:partial progress:convertProgress(@"Joining video and sound")
                 completion:^(NSString *err, NSDictionary *info) {
            logMux(info, err);
            if ([err isEqualToString:@"Cancelled."]) { dropPartial(); fail(err); return; }
            if (err) { appleBackup(err); return; }
            checkAndInstall(NO, appleBackup);
        }];
    } else if ([kind isEqualToString:@"convert"]) {
        reencode(files[0], files.count >= 2 ? files[1] : nil);
    } else if (isAudioKind(kind)) {
        NSString *fmt = [kind isEqualToString:@"audio"] ? @"m4a" : kind;   // mp3, wav, flac or m4a
        BOOL mp3 = [fmt isEqualToString:@"mp3"];
        NSDictionary *p = [VGConvert probe:first];
        BOOL alreadyM4A = [fmt isEqualToString:@"m4a"] && [p[@"audio"] isEqualToString:@"aac"] && [p[@"container"] hasPrefix:@"mov"];
        if (alreadyM4A) {
            NSString *dest = [documentsDir() stringByAppendingPathComponent:[self uniqueName:base ext:@"m4a"]];
            NSError *e = nil;
            [fm moveItemAtPath:first toPath:dest error:&e];
            if (e) fail(e.localizedDescription); else store(dest, NO);
            return;
        }
        NSString *dest = [documentsDir() stringByAppendingPathComponent:[self uniqueName:base ext:fmt]];
        NSString *what = [NSString stringWithFormat:@"Making %@", fmt.uppercaseString];
        (void)mp3;
        stageP(what);
        task.converter = [VGConvert new];
        [VGEngine convertAudioFile:first to:dest format:fmt title:r[@"title"] artist:r[@"uploader"] converter:task.converter
                          progress:convertProgress(what) done:^(NSString *err) { if (err) fail(err); else store(dest, NO); }];
    } else {
        // A single video file: make it an MP4 that Photos accepts, whatever it arrived as.
        NSDictionary *p = [VGConvert probe:first];
        NSString *vc = p[@"video"], *container = p[@"container"];
        BOOL appleCodec = [vc isEqualToString:@"h264"] || [vc isEqualToString:@"hevc"];
        if (appleCodec) {
            BOOL isMP4 = [container hasPrefix:@"mov"];
            NSString *what = isMP4 ? @"Finishing up" : [NSString stringWithFormat:@"Converting %@ to MP4", [first.pathExtension uppercaseString] ?: @"video"];
            stageP(what);
            // An MP4 that already is a playable MP4 can simply stay as it is if rebuilding it doesn't work out.
            void (^useOriginal)(NSString *) = ^(NSString *why) {
                [ws verify:first black:NO completion:^(NSString *problem) {
                    if (problem) { keepAndFail(cant(why), files, labels); return; }
                    media(@"fallback: keeping the original MP4 as it is (it plays fine)");
                    NSString *ext = first.pathExtension.lowercaseString.length ? first.pathExtension.lowercaseString : @"mp4";
                    NSString *dest = [documentsDir() stringByAppendingPathComponent:[ws uniqueName:base ext:ext]];
                    NSError *e = nil;
                    [fm moveItemAtPath:first toPath:dest error:&e];
                    if (e) keepAndFail(cant(e.localizedDescription), files, labels); else store(dest, NO);
                }];
            };
            void (^backup)(NSString *) = ^(NSString *why) {
                dropPartial();
                if (!isMP4) { keepAndFail(cant(why), files, labels); return; }   // Apple's exporter can't read TS, MKV or FLV
                media(@"fallback: trying Apple's repackager");
                [ws remux:[NSURL fileURLWithPath:first] to:[NSURL fileURLWithPath:partial] task:task completion:^(NSString *err) {
                    if (err) { dropPartial(); useOriginal(err); return; }
                    checkAndInstall(NO, ^(NSString *problem) { dropPartial(); useOriginal(problem); });
                }];
            };
            task.converter = [VGConvert new];
            [task.converter mux:first audio:nil to:partial progress:convertProgress(what) completion:^(NSString *err, NSDictionary *info) {
                logMux(info, err);
                if ([err isEqualToString:@"Cancelled."]) { dropPartial(); fail(err); return; }
                if (err) { backup(err); return; }
                checkAndInstall(NO, backup);
            }];
        } else if ([vc isEqualToString:@"vp9"] || [vc isEqualToString:@"vp8"]) {
            reencode(first, nil);
        } else {
            // A picture VidGrab can't put in an MP4 (MPEG-2 and others): keep the file, say what it was.
            keepAndFail(vc.length ? [NSString stringWithFormat:@"VidGrab can't convert %@ video yet", vc] : @"VidGrab can't read this kind of file", files, labels);
        }
    }
}


#pragma mark Diagnostics and repair

static NSString *fourCC(FourCharCode c) {
    char s[5] = {(char)(c >> 24), (char)(c >> 16), (char)(c >> 8), (char)c, 0};
    for (int i = 0; i < 4; i++) if (s[i] < 32 || s[i] > 126) s[i] = '?';
    return @(s);
}

- (void)diagnose:(VGItem *)item completion:(void (^)(NSString *))completion {
    NSString *path = item.fileURL.path;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableString *r = [NSMutableString string];
        NSString *v = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        [r appendFormat:@"VidGrab %@ · iOS %@\n", v, UIDevice.currentDevice.systemVersion];
        [r appendFormat:@"File: %@ (%@)\nQuality: %@ · site: %@\n", item.fileName,
            [NSByteCountFormatter stringFromByteCount:item.bytes countStyle:NSByteCountFormatterCountStyleFile], item.res, item.site ?: @"?"];
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path];
        [r appendFormat:@"Exists: %@\n", exists ? @"yes" : @"NO"];
        NSDictionary *p = [VGConvert probe:path];
        [r appendFormat:@"FFmpeg sees: container=%@ video=%@ audio=%@\n", p[@"container"], p[@"video"], p[@"audio"]];
        if (exists) [r appendString:[VGConvert describe:path]];

        AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
        [r appendFormat:@"Apple sees: playable=%@ duration=%.2fs tracks=%lu\n", a.isPlayable ? @"yes" : @"NO",
            CMTimeGetSeconds(a.duration), (unsigned long)a.tracks.count];
        for (AVAssetTrack *t in a.tracks) {
            CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)t.formatDescriptions.firstObject;
            NSString *codec = fd ? fourCC(CMFormatDescriptionGetMediaSubType(fd)) : @"none";
            if ([t.mediaType isEqualToString:AVMediaTypeVideo]) {
                CGAffineTransform x = t.preferredTransform;
                [r appendFormat:@"  video %@ %.0fx%.0f %.2ffps %.0fkbps decodable=%@ playable=%@ start=%.3fs len=%.2fs transform=[%.0f %.0f %.0f %.0f]\n",
                    codec, t.naturalSize.width, t.naturalSize.height, t.nominalFrameRate, t.estimatedDataRate / 1000,
                    t.isDecodable ? @"yes" : @"NO", t.isPlayable ? @"yes" : @"NO",
                    CMTimeGetSeconds(t.timeRange.start), CMTimeGetSeconds(t.timeRange.duration), x.a, x.b, x.c, x.d];
            } else {
                [r appendFormat:@"  %@ %@ start=%.3fs len=%.2fs\n", t.mediaType, codec,
                    CMTimeGetSeconds(t.timeRange.start), CMTimeGetSeconds(t.timeRange.duration)];
            }
        }
        double secs = CMTimeGetSeconds(a.duration);
        if (secs > 0) {
            AVAssetImageGenerator *g = [AVAssetImageGenerator assetImageGeneratorWithAsset:a];
            g.appliesPreferredTrackTransform = YES;
            g.maximumSize = CGSizeMake(160, 160);
            for (NSNumber *f in @[@0.05, @0.25, @0.5, @0.75, @0.95]) {
                NSError *e = nil;
                CMTime got;
                CGImageRef img = [g copyCGImageAtTime:CMTimeMakeWithSeconds(secs * f.doubleValue, 600) actualTime:&got error:&e];
                if (img) {
                    [r appendFormat:@"  frame @%.1fs: brightness %.1f\n", CMTimeGetSeconds(got), brightness(img)];
                    CGImageRelease(img);
                } else {
                    [r appendFormat:@"  frame @%.1fs: unreadable (%@)\n", secs * f.doubleValue, e.localizedDescription ?: @"?"];
                }
            }
        }
        NSString *pr = [self problemWithVideo:path checkBlack:YES];
        [r appendFormat:@"Check: %@\n", pr ?: @"looks fine"];
        if (self.convLog.length) [r appendFormat:@"\nConversion notes:\n%@", self.convLog];
        NSString *out = [r copy];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(out); });
    });
}

- (void)repairItem:(VGItem *)item progress:(void (^)(double))progress completion:(void (^)(NSString *))completion {
    NSString *path = item.fileURL.path;
    NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:@"repair"];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:work error:nil];
    [fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *out = [work stringByAppendingPathComponent:@"fixed.mp4"];
    NSMutableArray<NSString *> *tried = [NSMutableArray array];
    NSDictionary *probe = [VGConvert probe:path];
    NSString *vc = probe[@"video"] ?: @"", *ac = probe[@"audio"] ?: @"";
    [self note:[NSString stringWithFormat:@"repair %@: container=%@ video=%@ audio=%@", item.fileName, probe[@"container"], vc, ac]];
    __weak typeof(self) ws = self;

    // Puts the fixed file in place of the original once it passes the picture check.
    void (^accept)(NSString *) = ^(NSString *how) {
        NSError *err = nil;
        [fm replaceItemAtURL:item.fileURL withItemAtURL:[NSURL fileURLWithPath:out] backupItemName:nil options:0 resultingItemURL:nil error:&err];
        [fm removeItemAtPath:work error:nil];
        if (err) { completion(err.localizedDescription); return; }
        item.bytes = [[fm attributesOfItemAtPath:path error:nil][NSFileSize] longLongValue];
        item.photos = YES;
        [ws makeThumbnailFor:item fallbackURL:nil];
        [ws saveLibrary];
        [ws note:[@"repair ok via " stringByAppendingString:how]];
        completion(nil);
    };
    void (^giveUp)(void) = ^{
        [fm removeItemAtPath:work error:nil];
        completion([NSString stringWithFormat:@"None of the repair methods worked.\n\nFile: video %@, sound %@\n%@",
                    vc.length ? vc : @"none", ac.length ? ac : @"none", [tried componentsJoinedByString:@"\n"]]);
    };

    // Method 3: FFmpeg decodes the picture, Apple's hardware encoder rebuilds it.
    void (^method3)(void) = ^{
        BOOL canDecode = [@[@"h264", @"hevc", @"vp9", @"vp8"] containsObject:vc];
        if (!canDecode) { [tried addObject:[NSString stringWithFormat:@"3. Rebuild picture: skipped (%@ not supported)", vc.length ? vc : @"no video"]]; giveUp(); return; }
        void (^encode)(NSString *) = ^(NSString *sound) {
            VGTranscoder *tx = [VGTranscoder new];
            objc_setAssociatedObject(item, "vg.repair", tx, OBJC_ASSOCIATION_RETAIN);
            [tx convertVideo:[NSURL fileURLWithPath:path] audio:sound ? [NSURL fileURLWithPath:sound] : nil to:[NSURL fileURLWithPath:out]
                    progress:^(double f) { if (progress) progress(0.5 + f * 0.5); }
                  completion:^(NSString *err) {
                objc_setAssociatedObject(item, "vg.repair", nil, OBJC_ASSOCIATION_RETAIN);
                if (err) { [tried addObject:[@"3. Rebuild picture: " stringByAppendingString:err]]; giveUp(); return; }
                [ws verify:out black:YES completion:^(NSString *problem) {
                    if (!problem) { accept(@"FFmpeg decode + Apple encode"); return; }
                    [tried addObject:[@"3. Rebuild picture: result " stringByAppendingString:problem]];
                    giveUp();
                }];
            }];
        };
        if (!ac.length) { encode(nil); return; }
        // Sound goes in as AAC: copy it out (or convert it) with FFmpeg first.
        NSString *sound = [work stringByAppendingPathComponent:@"sound.m4a"];
        VGConvert *c = [VGConvert new];
        objc_setAssociatedObject(item, "vg.repair", c, OBJC_ASSOCIATION_RETAIN);
        [c audio:path to:sound mp3:NO title:nil artist:nil progress:nil completion:^(NSString *err) {
            if (err) [tried addObject:[@"3. (sound could not be copied, continuing without it: " stringByAppendingFormat:@"%@)", err]];
            encode(err ? nil : sound);
        }];
    };

    // Method 2: FFmpeg repackages H.264/HEVC into a fresh MP4 (fast, no quality loss).
    void (^method2)(void) = ^{
        if (![vc isEqualToString:@"h264"] && ![vc isEqualToString:@"hevc"]) { [tried addObject:@"2. Repackage: skipped (not H.264/HEVC)"]; method3(); return; }
        [fm removeItemAtPath:out error:nil];
        VGConvert *c = [VGConvert new];
        objc_setAssociatedObject(item, "vg.repair", c, OBJC_ASSOCIATION_RETAIN);
        [c remux:path to:out progress:^(double f) { if (progress) progress(0.3 + f * 0.2); } completion:^(NSString *err) {
            if (err) { [tried addObject:[@"2. Repackage: " stringByAppendingString:err]]; method3(); return; }
            [ws verify:out black:YES completion:^(NSString *problem) {
                if (!problem) { accept(@"FFmpeg repackage"); return; }
                [tried addObject:[@"2. Repackage: result " stringByAppendingString:problem]];
                method3();
            }];
        }];
    };

    // Method 1: Apple re-encodes it (works when Apple can read the file).
    AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetExportSession *ex = [[AVAssetExportSession alloc] initWithAsset:a presetName:AVAssetExportPresetHighestQuality];
    if (!ex) { [tried addObject:@"1. Apple re-encode: iPhone can't open this file"]; method2(); return; }
    ex.outputURL = [NSURL fileURLWithPath:out];
    ex.outputFileType = AVFileTypeMPEG4;
    ex.shouldOptimizeForNetworkUse = YES;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { if (progress) progress(ex.progress * 0.3); }];
    [ex exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [timer invalidate];
            if (ex.status != AVAssetExportSessionStatusCompleted) {
                [tried addObject:[@"1. Apple re-encode: " stringByAppendingString:ex.error.localizedDescription ?: @"failed"]];
                method2();
                return;
            }
            [ws verify:out black:YES completion:^(NSString *problem) {
                if (!problem) { accept(@"Apple re-encode"); return; }
                [tried addObject:[@"1. Apple re-encode: result " stringByAppendingString:problem]];
                method2();
            }];
        });
    }];
}

#pragma mark AVFoundation

- (void)export:(AVAsset *)asset to:(NSURL *)dest preset:(NSString *)preset task:(VGTask *)task completion:(void (^)(NSString *))completion {
    [NSFileManager.defaultManager removeItemAtURL:dest error:nil];
    AVAssetExportSession *ex = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!ex) { completion(@"This video format can't be processed on iPhone."); return; }
    ex.outputURL = dest;
    ex.outputFileType = AVFileTypeMPEG4;
    ex.shouldOptimizeForNetworkUse = YES;
    task.export = ex;
    [ex exportAsynchronouslyWithCompletionHandler:^{
        NSString *err = nil;
        if (ex.status == AVAssetExportSessionStatusCancelled) err = @"Cancelled.";
        else if (ex.status != AVAssetExportSessionStatusCompleted) err = ex.error.localizedDescription ?: @"Couldn't finish the video.";
        dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
    }];
}

- (void)remux:(NSURL *)src to:(NSURL *)dest task:(VGTask *)task completion:(void (^)(NSString *))completion {
    AVURLAsset *a = [AVURLAsset URLAssetWithURL:src options:nil];
    [self export:a to:dest preset:AVAssetExportPresetPassthrough task:task completion:completion];
}

- (void)mergeVideo:(NSURL *)v audio:(NSURL *)a to:(NSURL *)dest task:(VGTask *)task completion:(void (^)(NSString *))completion {
    AVURLAsset *va = [AVURLAsset URLAssetWithURL:v options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVURLAsset *aa = [AVURLAsset URLAssetWithURL:a options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetTrack *vt = [va tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVAssetTrack *at = [aa tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!vt) { completion(@"The downloaded video stream couldn't be read."); return; }

    AVMutableComposition *comp = [AVMutableComposition composition];
    NSError *e = nil;
    CMTime dur = va.duration;
    AVMutableCompositionTrack *cv = [comp addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    [cv insertTimeRange:CMTimeRangeMake(kCMTimeZero, dur) ofTrack:vt atTime:kCMTimeZero error:&e];
    cv.preferredTransform = vt.preferredTransform;
    if (at) {
        AVMutableCompositionTrack *ca = [comp addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        CMTime ad = CMTimeMinimum(aa.duration, dur);
        [ca insertTimeRange:CMTimeRangeMake(kCMTimeZero, ad) ofTrack:at atTime:kCMTimeZero error:nil];
    }
    if (e) { completion(e.localizedDescription); return; }

    [self export:comp to:dest preset:AVAssetExportPresetPassthrough task:task completion:^(NSString *err) {
        if (!err || [err isEqualToString:@"Cancelled."]) { completion(err); return; }
        // Passthrough can fail on unusual files; re-encode as a fallback (slower).
        [self export:comp to:dest preset:AVAssetExportPresetHighestQuality task:task completion:completion];
    }];
}

#pragma mark Importing

/// A short "1080p" / "4K" label (with "60fps" when it is fast), like the ones on downloads.
static NSString *resolutionLabel(AVAssetTrack *track) {
    CGSize sz = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
    int side = (int)round(MIN(fabs(sz.width), fabs(sz.height)));   // the short side, so tall phone videos read the same way
    NSString *r = side >= 2000 ? @"4K" : side >= 1300 ? @"1440p" : side >= 900 ? @"1080p" : side >= 600 ? @"720p"
                : side >= 420 ? @"480p" : side >= 300 ? @"360p" : [NSString stringWithFormat:@"%dp", side];
    if (track.nominalFrameRate >= 50) r = [r stringByAppendingFormat:@" %dfps", (int)round(track.nominalFrameRate)];
    return r;
}

- (void)importFileAtURL:(NSURL *)url title:(NSString *)title source:(NSString *)source move:(BOOL)move
             completion:(void (^)(VGItem *, NSString *))completion {
    NSFileManager *fm = NSFileManager.defaultManager;
    void (^finish)(VGItem *, NSString *) = ^(VGItem *item, NSString *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (item) { [self.library insertObject:item atIndex:0]; [self saveLibrary]; }
            if (completion) completion(item, err);
        });
    };

    NSString *ext = url.pathExtension.lowercaseString;
    NSString *base = title.length ? title : [url.lastPathComponent stringByDeletingPathExtension];
    for (NSString *bad in @[@"/", @":", @"\\"]) base = [base stringByReplacingOccurrencesOfString:bad withString:@"-"];
    base = [base stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (base.length > 120) base = [base substringToIndex:120];
    if (!base.length) base = @"Imported video";
    NSString *shownName = [NSString stringWithFormat:@"\u201C%@\u201D", base];

    // Only what the iPhone can play: the player has to be able to open it.
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetTrack *video = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    BOOL hasAudio = [asset tracksWithMediaType:AVMediaTypeAudio].count > 0;
    if (!asset.isPlayable || (!video && !hasAudio)) {
        finish(nil, [NSString stringWithFormat:@"%@ can't be played on iPhone%@.", shownName, ext.length ? [NSString stringWithFormat:@" (%@ files aren't supported)", ext.uppercaseString] : @""]);
        return;
    }
    if (!ext.length) ext = video ? @"mp4" : @"m4a";

    NSString *dest = [documentsDir() stringByAppendingPathComponent:[self uniqueName:base ext:ext]];
    NSError *err = nil;
    BOOL ok = move ? [fm moveItemAtURL:url toURL:[NSURL fileURLWithPath:dest] error:&err] : NO;
    if (!ok) { err = nil; ok = [fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:dest] error:&err]; }
    if (!ok) {
        finish(nil, [NSString stringWithFormat:@"Couldn't add %@: %@", shownName, err.localizedDescription ?: @"not enough space?"]);
        return;
    }

    VGItem *item = [VGItem new];
    item.fileName = dest.lastPathComponent;
    item.title = base;
    item.site = source;
    item.audio = video == nil;
    item.res = video ? resolutionLabel(video) : @"Audio";
    double d = CMTimeGetSeconds(asset.duration);
    item.duration = isfinite(d) && d > 0 ? d : 0;
    item.photos = video != nil && UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(dest);
    item.date = [NSDate date];
    item.bytes = [[fm attributesOfItemAtPath:dest error:nil][NSFileSize] longLongValue];
    [self makeThumbnailFor:item fallbackURL:nil];
    finish(item, nil);
}

- (void)makeThumbnailFor:(VGItem *)item fallbackURL:(NSString *)remote {
    if (!item.audio) {
        AVAssetImageGenerator *g = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:item.fileURL options:nil]];
        g.appliesPreferredTrackTransform = YES;
        g.maximumSize = CGSizeMake(480, 480);
        CMTime t = CMTimeMakeWithSeconds(MIN(2.0, MAX(item.duration / 4, 0)), 600);
        CGImageRef img = [g copyCGImageAtTime:t actualTime:NULL error:nil];
        if (img) {
            [UIImageJPEGRepresentation([UIImage imageWithCGImage:img], 0.8) writeToFile:[item thumbPath] atomically:YES];
            CGImageRelease(img);
            return;
        }
    }
    if (remote.length) {
        NSString *path = [item thumbPath];
        [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:remote] completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            UIImage *img = d ? [UIImage imageWithData:d] : nil;
            if (!img) return;
            [UIImageJPEGRepresentation(img, 0.8) writeToFile:path atomically:YES];
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:VGLibraryDidChangeNotification object:nil];
            });
        }] resume];
    }
}

- (void)copyErrorDetails:(void (^)(void))done {
    [[VGPython shared] call:@"vgbridge" function:@"last_error" args:@[] completion:^(NSDictionary *r, NSString *error) {
        NSString *v = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"VidGrab %@ · engine %@ · iOS %@\n%@\n\nConversion notes:\n%@",
            v, self.engineVersion, UIDevice.currentDevice.systemVersion, r[@"details"] ?: error ?: @"(none)", self.convLog ?: @"(none)"];
        done();
    }];
}

#pragma mark Engine update

- (void)updateEngine:(void (^)(NSString *, NSString *))completion {
    if (self.activeCount) { completion(@"Downloads in progress", @"Wait for your downloads to finish, then update the engine."); return; }
    VGPython *py = [VGPython shared];
    [py call:@"vgboot" function:@"update_engine" args:@[py.engineDir, py.engineVersion ?: @"0"]
  completion:^(NSDictionary *r, NSString *error) {
        if (!r) { completion(@"Update failed", error ?: @"Unknown error."); return; }
        NSString *status = r[@"status"];
        if ([status isEqualToString:@"current"]) completion(@"You're up to date", [NSString stringWithFormat:@"Engine version %@ is the newest.", r[@"version"]]);
        else if ([status isEqualToString:@"updated"]) completion(@"Engine updated", [NSString stringWithFormat:@"Version %@ is ready. Close and reopen VidGrab to start using it.", r[@"version"]]);
        else completion(@"Update failed", r[@"error"] ?: @"Unknown error.");
    }];
}

@end
