#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Plays a VP9 video (2K, 4K) that the iPhone can't play directly: the picture is decoded with FFmpeg,
/// re-encoded to HEVC by the iPhone's hardware encoder and handed to the player in small pieces (a local
/// HLS stream on 127.0.0.1) while it is still being made. Nothing is saved to Downloads.
@interface VGLiveStream : NSObject
/// `video` and `audio` are {url, headers}. `audio` may be nil.
- (instancetype)initWithVideo:(NSDictionary *)video audio:(nullable NSDictionary *)audio fps:(double)fps duration:(double)duration;
/// Seconds the viewer has reached. The conversion pauses when it is far enough ahead of this.
@property (atomic) double playhead;
@property (nonatomic, readonly) double duration;
/// Second of the video to begin from (0 = the start).
@property (nonatomic) double startAt;
/// Starts converting. `ready` gets the playlist address once the first pieces exist (on the main queue).
- (void)startWithReady:(void (^)(NSURL *playlist))ready failed:(void (^)(NSString *error))failed;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
