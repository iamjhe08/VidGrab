#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted (on the main queue) when the subtitle model download starts, moves along, finishes or fails,
/// and when the model is deleted.
extern NSString *const VGSubtitleModelDidChange;

typedef NS_ENUM(NSInteger, VGSubtitleQuality) { VGSubtitleFast, VGSubtitleBalanced, VGSubtitleBest };

/// Auto English subtitles made on the phone itself (no account, nothing uploaded).
/// Off until switched on in Settings; the speech model is downloaded once, only when asked for.
@interface VGSubtitles : NSObject

/// The Settings switch. Off by default so old phones are never asked to do the work.
@property (class, nonatomic) BOOL enabled;
@property (class, nonatomic) VGSubtitleQuality quality;
/// Whether subtitles were left on in the last video (so the next one starts the same way).
@property (class, nonatomic) BOOL startOn;

+ (NSString *)nameFor:(VGSubtitleQuality)quality;          // "Balanced"
+ (NSString *)detailFor:(VGSubtitleQuality)quality;        // "About 60 MB. Good mix of speed and accuracy."
+ (NSInteger)megabytesFor:(VGSubtitleQuality)quality;

+ (BOOL)modelReady:(VGSubtitleQuality)quality;
+ (BOOL)currentModelReady;
+ (BOOL)downloading;
+ (double)downloadProgress;                                // 0 to 1
+ (nullable NSString *)lastError;

+ (void)downloadModel:(VGSubtitleQuality)quality;
+ (void)cancelDownload;
+ (void)deleteModel:(VGSubtitleQuality)quality;
+ (NSString *)pathFor:(VGSubtitleQuality)quality;

@end

/// Listens to a video's sound ahead of the playhead, in 30 second pieces, and turns whatever language
/// is spoken into English text with times, so the lines show up in step with the picture.
@interface VGSubtitleEngine : NSObject

/// Something to show in place of subtitles while it works ("Making subtitles…"), or nil.
@property (atomic, copy, readonly, nullable) NSString *status;
/// Called on the main queue when new lines or a new status are ready.
@property (nonatomic, copy, nullable) void (^onChange)(void);

- (instancetype)initWithURL:(NSURL *)url key:(NSString *)key quality:(VGSubtitleQuality)quality;
- (void)start;
- (void)stop;
/// Where the video is now, in seconds. Work always stays a little ahead of this.
- (void)setPlayhead:(double)seconds;
/// The line to show at this time, if any.
- (nullable NSString *)textAt:(double)seconds;

@end

NS_ASSUME_NONNULL_END
