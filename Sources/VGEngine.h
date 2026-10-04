#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VGOption : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *res;        // "1080p 60fps", "4K", "Audio"
@property (nonatomic, copy) NSString *sizeText;   // "83 MB"
@property (nonatomic, copy) NSString *format;     // "MP4", "M4A", "WEBM"
@property (nonatomic) BOOL photos;
@property (nonatomic) BOOL audio;
@property (nonatomic) BOOL convert;   // 1440p/4K VP9, converted to HEVC on device
@end

@interface VGVideo : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *uploader;
@property (nonatomic, copy, nullable) NSString *site;
@property (nonatomic, copy, nullable) NSString *thumbnail;
@property (nonatomic) double duration;
@property (nonatomic, copy) NSArray<VGOption *> *options;
@end

/// A finished download stored in the app's Documents folder.
@interface VGItem : NSObject
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *site;
@property (nonatomic, copy) NSString *res;
@property (nonatomic) double duration;
@property (nonatomic) long long bytes;
@property (nonatomic) BOOL audio;
@property (nonatomic) BOOL photos;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, readonly) NSURL *fileURL;
@property (nonatomic, readonly, nullable) UIImage *thumbnailImage;
@end

typedef void (^VGProgress)(double fraction, NSString *stage, NSString *detail);

typedef NS_ENUM(NSInteger, VGTaskState) { VGTaskQueued, VGTaskRunning, VGTaskFailed, VGTaskDone, VGTaskCancelled };

/// One download in the queue.
@interface VGTask : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, strong) VGVideo *video;
@property (nonatomic, readonly, strong) VGOption *option;
@property (nonatomic, readonly) VGTaskState state;
@property (nonatomic, readonly) double fraction;
@property (nonatomic, readonly, copy) NSString *stage;
@property (nonatomic, readonly, copy) NSString *detail;
@property (nonatomic, readonly, copy, nullable) NSString *error;
@property (nonatomic, readonly, strong, nullable) VGItem *item;
/// Optional callbacks for the screen that started the download.
@property (nonatomic, copy, nullable) VGProgress progressHandler;
@property (nonatomic, copy, nullable) void (^completionHandler)(VGItem *_Nullable item, NSString *_Nullable error);
@end

extern NSString *const VGLibraryDidChangeNotification;
/// Posted whenever the queue or a task's progress changes (object: the VGTask, or nil).
extern NSString *const VGTasksDidChangeNotification;
/// Posted when a task ends (object: the VGTask).
extern NSString *const VGTaskFinishedNotification;

@interface VGEngine : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<VGItem *> *items;
/// Queued, running and failed downloads, oldest first.
@property (nonatomic, readonly) NSArray<VGTask *> *tasks;
/// Downloads still to finish (queued + running).
@property (nonatomic, readonly) NSUInteger activeCount;
/// The first running download, for compact progress displays.
@property (nonatomic, readonly, nullable) VGTask *leadTask;

- (void)start;
- (void)fetch:(NSString *)url completion:(void (^)(VGVideo *_Nullable video, NSString *_Nullable error))completion;
/// Adds a download to the queue (2 run at a time) and returns it.
- (VGTask *)download:(VGVideo *)video
              option:(VGOption *)option
            progress:(nullable VGProgress)progress
          completion:(nullable void (^)(VGItem *_Nullable item, NSString *_Nullable error))completion;
- (void)cancelTask:(VGTask *)task;
- (void)retryTask:(VGTask *)task;
- (void)dismissTask:(VGTask *)task;
- (void)deleteItem:(VGItem *)item;
/// A plain-text report on a downloaded file (codecs, tracks, whether iPhone can play it, picture brightness).
- (void)diagnose:(VGItem *)item completion:(void (^)(NSString *report))completion;
/// Rebuilds a video with Apple's own encoder (slow) as a rescue for files that won't play right.
- (void)repairItem:(VGItem *)item progress:(void (^)(double fraction))progress completion:(void (^)(NSString *_Nullable error))completion;
- (void)copyErrorDetails:(void (^)(void))done;
- (void)updateEngine:(void (^)(NSString *title, NSString *message))completion;
- (NSString *)engineVersion;
- (long long)totalBytes;
@end

NS_ASSUME_NONNULL_END
