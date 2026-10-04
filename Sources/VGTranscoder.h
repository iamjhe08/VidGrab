#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Converts a VP9 video stream (WebM) plus an M4A audio file into an HEVC MP4
/// that Photos can open. VP9 is decoded with FFmpeg; encoding uses Apple's
/// hardware encoder through AVAssetWriter.
@interface VGTranscoder : NSObject
- (void)convertVideo:(NSURL *)video
               audio:(nullable NSURL *)audio
                  to:(NSURL *)output
            progress:(void (^)(double fraction))progress
          completion:(void (^)(NSString *_Nullable error))completion;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
