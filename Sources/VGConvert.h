#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C wrapper around the FFmpeg converter core (vgconvert.c).
/// Work runs in the background; progress and completion arrive on the main queue.
@interface VGConvert : NSObject
/// Returns @{@"video": codec, @"audio": codec, @"container": name, @"width", @"height", @"duration"} (empty strings if absent).
+ (NSDictionary<NSString *, NSString *> *)probe:(NSString *)path;
/// One line per stream in the file, for Video info.
+ (NSString *)describe:(NSString *)path;
/// Looks at the raw MPEG-TS packets: @{@"text": readable lines, @"scrambled": NSNumber (packets), @"isTS": NSNumber (BOOL)}.
+ (NSDictionary<NSString *, id> *)tsScan:(NSString *)path;
/// Strips junk (fake picture headers and the like) from between the packets of a transport stream. Blocking: call off the
/// main thread. Returns nil when the file needs no cleaning (or isn't a transport stream); otherwise
/// @{@"path": cleaned copy (or nil on failure), @"junk": NSNumber bytes removed, @"pieces": NSNumber, @"error": NSString or nil}.
+ (nullable NSDictionary<NSString *, id> *)tsClean:(NSString *)path to:(NSString *)output;
- (void)remux:(NSString *)input to:(NSString *)output
     progress:(nullable void (^)(double fraction))progress
   completion:(void (^)(NSString *_Nullable error))completion;
/// The safe route for downloads: puts the picture (and sound) into an MP4 at `output` without re-encoding the picture,
/// then checks the result natively (opens, picture size, codec setup, sound, length, starts on a keyframe, decodes at the
/// start and middle). `audio` may be nil (sound taken from `video`). The sources are never touched.
/// On any failure `output` is deleted and `error` says why. `info` always has: strategy, validation (OK summary or the
/// reason), expectedDuration, discontinuities, leadingDropped, videoIn, videoOut, videoLost, hadAudio.
- (void)mux:(NSString *)video audio:(nullable NSString *)audio to:(NSString *)output
   progress:(nullable void (^)(double fraction))progress
 completion:(void (^)(NSString *_Nullable error, NSDictionary<NSString *, id> *info))completion;
/// Joins a video file and a separate sound file into one MP4 (no re-encoding). No result check: see mux:audio:to:.
- (void)merge:(NSString *)video audio:(NSString *)audio to:(NSString *)output
     progress:(nullable void (^)(double fraction))progress
   completion:(void (^)(NSString *_Nullable error))completion;
- (void)audio:(NSString *)input to:(NSString *)output mp3:(BOOL)mp3
        title:(nullable NSString *)title artist:(nullable NSString *)artist
     progress:(nullable void (^)(double fraction))progress
   completion:(void (^)(NSString *_Nullable error))completion;
/// Decodes the sound of a file into a 16-bit PCM .wav.
- (void)wavFrom:(NSString *)input to:(NSString *)output
      progress:(nullable void (^)(double fraction))progress
    completion:(void (^)(NSString *_Nullable error))completion;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
