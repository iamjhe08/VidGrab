#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads and writes the title, artist, album and cover picture stored inside audio files (MP3 and M4A).
@interface VGAudioTags : NSObject
/// @{@"title", @"artist", @"album": NSString (may be missing), @"artwork": NSData (JPEG or PNG, may be missing)}.
+ (NSDictionary<NSString *, id> *)readFromPath:(NSString *)path;
/// Writes the tags into the file itself (MP3 and M4A; other types are left alone and succeed quietly).
/// The completion runs on the main queue with nil on success.
+ (void)writeTitle:(nullable NSString *)title artist:(nullable NSString *)artist album:(nullable NSString *)album
           artwork:(nullable NSData *)jpeg toPath:(NSString *)path completion:(void (^)(NSString *_Nullable error))completion;
/// A square JPEG (at most `side` points on each edge) cut from the middle of any picture.
+ (nullable NSData *)squareJPEGFrom:(UIImage *)image side:(CGFloat)side;
@end

NS_ASSUME_NONNULL_END
