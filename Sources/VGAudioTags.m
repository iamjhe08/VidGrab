#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CMMetadata.h>
#import "VGAudioTags.h"

@implementation VGAudioTags

+ (NSDictionary<NSString *, id> *)readFromPath:(NSString *)path {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    for (AVMetadataItem *m in a.commonMetadata) {
        NSString *k = m.commonKey;
        if ([k isEqualToString:AVMetadataCommonKeyTitle] && m.stringValue.length) out[@"title"] = m.stringValue;
        else if ([k isEqualToString:AVMetadataCommonKeyArtist] && m.stringValue.length) out[@"artist"] = m.stringValue;
        else if ([k isEqualToString:AVMetadataCommonKeyAlbumName] && m.stringValue.length) out[@"album"] = m.stringValue;
        else if ([k isEqualToString:AVMetadataCommonKeyArtwork]) {
            NSData *d = m.dataValue;
            if (!d && [m.value isKindOfClass:NSData.class]) d = (NSData *)m.value;
            if (d.length) out[@"artwork"] = d;
        }
    }
    return out;
}

+ (NSData *)squareJPEGFrom:(UIImage *)image side:(CGFloat)side {
    if (!image) return nil;
    CGFloat w = image.size.width, h = image.size.height;
    if (w <= 0 || h <= 0) return nil;
    CGFloat s = MIN(w, h);
    CGFloat target = MIN(side, s);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(target, target) format:fmt];
    UIImage *sq = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat k = target / s;
        [image drawInRect:CGRectMake(-(w - s) / 2 * k, -(h - s) / 2 * k, w * k, h * k)];
    }];
    return UIImageJPEGRepresentation(sq, 0.88);
}

// ---- MP3 (ID3v2.3 at the start of the file)

static void putSynchsafe(NSMutableData *d, uint32_t v) {
    uint8_t b[4] = {(uint8_t)((v >> 21) & 0x7F), (uint8_t)((v >> 14) & 0x7F), (uint8_t)((v >> 7) & 0x7F), (uint8_t)(v & 0x7F)};
    [d appendBytes:b length:4];
}

static void putBE32(NSMutableData *d, uint32_t v) {
    uint8_t b[4] = {(uint8_t)(v >> 24), (uint8_t)(v >> 16), (uint8_t)(v >> 8), (uint8_t)v};
    [d appendBytes:b length:4];
}

static NSData *textFrame(const char *id4, NSString *text) {
    NSMutableData *body = [NSMutableData data];
    uint8_t enc = 1;   // UTF-16 with a byte order mark
    [body appendBytes:&enc length:1];
    uint8_t bom[2] = {0xFF, 0xFE};
    [body appendBytes:bom length:2];
    [body appendData:[text dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
    uint8_t z[2] = {0, 0};
    [body appendBytes:z length:2];
    NSMutableData *f = [NSMutableData dataWithBytes:id4 length:4];
    putBE32(f, (uint32_t)body.length);
    uint8_t flags[2] = {0, 0};
    [f appendBytes:flags length:2];
    [f appendData:body];
    return f;
}

static NSData *pictureFrame(NSData *jpeg) {
    NSMutableData *body = [NSMutableData data];
    uint8_t enc = 0;
    [body appendBytes:&enc length:1];
    const char *mime = "image/jpeg";
    [body appendBytes:mime length:strlen(mime) + 1];
    uint8_t type = 3;   // front cover
    [body appendBytes:&type length:1];
    uint8_t z = 0;      // empty description
    [body appendBytes:&z length:1];
    [body appendData:jpeg];
    NSMutableData *f = [NSMutableData dataWithBytes:"APIC" length:4];
    putBE32(f, (uint32_t)body.length);
    uint8_t flags[2] = {0, 0};
    [f appendBytes:flags length:2];
    [f appendData:body];
    return f;
}

+ (NSString *)writeMP3Tags:(NSString *)path title:(NSString *)title artist:(NSString *)artist album:(NSString *)album artwork:(NSData *)jpeg {
    NSData *file = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!file) return @"Couldn't open the file to save the tags.";
    NSUInteger skip = 0;
    const uint8_t *p = file.bytes;
    if (file.length >= 10 && memcmp(p, "ID3", 3) == 0) {
        uint32_t size = ((p[6] & 0x7F) << 21) | ((p[7] & 0x7F) << 14) | ((p[8] & 0x7F) << 7) | (p[9] & 0x7F);
        skip = 10 + size + ((p[5] & 0x10) ? 10 : 0);
        if (skip > file.length) skip = 0;
    }
    NSMutableData *frames = [NSMutableData data];
    if (title.length) [frames appendData:textFrame("TIT2", title)];
    if (artist.length) [frames appendData:textFrame("TPE1", artist)];
    if (album.length) [frames appendData:textFrame("TALB", album)];
    if (jpeg.length) [frames appendData:pictureFrame(jpeg)];
    NSMutableData *out = [NSMutableData dataWithCapacity:file.length + frames.length + 64];
    if (frames.length) {
        [out appendBytes:"ID3" length:3];
        uint8_t ver[3] = {3, 0, 0};
        [out appendBytes:ver length:3];
        putSynchsafe(out, (uint32_t)frames.length);
        [out appendData:frames];
    }
    [out appendData:[file subdataWithRange:NSMakeRange(skip, file.length - skip)]];
    NSString *tmp = [path stringByAppendingString:@".tagging"];
    if (![out writeToFile:tmp atomically:NO]) return @"Couldn't save the tags (not enough space?).";
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *e = nil;
    if (![fm replaceItemAtURL:[NSURL fileURLWithPath:path] withItemAtURL:[NSURL fileURLWithPath:tmp] backupItemName:nil options:0 resultingItemURL:nil error:&e]) {
        [fm removeItemAtPath:tmp error:nil];
        return e.localizedDescription ?: @"Couldn't replace the file.";
    }
    return nil;
}

// ---- M4A (rewritten without re-encoding, with the tags added)

+ (void)writeM4ATags:(NSString *)path title:(NSString *)title artist:(NSString *)artist album:(NSString *)album artwork:(NSData *)jpeg
          completion:(void (^)(NSString *))completion {
    NSMutableArray *meta = [NSMutableArray array];
    void (^add)(NSString *, id, NSString *) = ^(NSString *key, id value, NSString *type) {
        if (!value) return;
        AVMutableMetadataItem *m = [AVMutableMetadataItem new];
        m.keySpace = AVMetadataKeySpaceCommon;
        m.key = key;
        m.value = value;
        if (type) m.dataType = type;
        [meta addObject:m];
    };
    if (title.length) add(AVMetadataCommonKeyTitle, title, nil);
    if (artist.length) add(AVMetadataCommonKeyArtist, artist, nil);
    if (album.length) add(AVMetadataCommonKeyAlbumName, album, nil);
    if (jpeg.length) add(AVMetadataCommonKeyArtwork, jpeg, (__bridge NSString *)kCMMetadataBaseDataType_JPEG);
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    AVAssetExportSession *ex = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetPassthrough];
    if (!ex) { completion(@"This file can't be tagged."); return; }
    NSString *tmp = [path stringByAppendingString:@".tagging.m4a"];
    [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
    ex.outputURL = [NSURL fileURLWithPath:tmp];
    ex.outputFileType = AVFileTypeAppleM4A;
    ex.metadata = meta;
    [ex exportAsynchronouslyWithCompletionHandler:^{
        NSString *err = nil;
        if (ex.status != AVAssetExportSessionStatusCompleted) {
            err = ex.error.localizedDescription ?: @"Couldn't save the tags.";
            [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
        } else {
            NSError *e = nil;
            if (![NSFileManager.defaultManager replaceItemAtURL:[NSURL fileURLWithPath:path] withItemAtURL:[NSURL fileURLWithPath:tmp]
                                                 backupItemName:nil options:0 resultingItemURL:nil error:&e]) {
                err = e.localizedDescription ?: @"Couldn't replace the file.";
                [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
    }];
}

+ (void)writeTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album artwork:(NSData *)jpeg
            toPath:(NSString *)path completion:(void (^)(NSString *))completion {
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"mp3"]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *err = [self writeMP3Tags:path title:title artist:artist album:album artwork:jpeg];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
        });
    } else if ([ext isEqualToString:@"m4a"] || [ext isEqualToString:@"aac"]) {
        [self writeM4ATags:path title:title artist:artist album:album artwork:jpeg completion:completion];
    } else {
        completion(nil);   // WAV and FLAC keep their details in VidGrab only
    }
}

@end
