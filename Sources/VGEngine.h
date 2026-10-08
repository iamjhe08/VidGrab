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
/// For a stream the in-app browser caught while a page played: the request details (Referer, browser name, kind) as JSON.
@property (nonatomic, copy, nullable) NSString *extra;
/// Set when the link is a playlist or channel: its videos (url, title, duration, thumbnail only).
@property (nonatomic, copy, nullable) NSArray<VGVideo *> *entries;
@property (nonatomic, readonly) BOOL isPlaylist;
@end

/// A folder the user made in Downloads to sort videos. Folders only live inside VidGrab (the files themselves stay put).
@interface VGFolder : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
/// "RRGGBB"
@property (nonatomic, copy) NSString *colorHex;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, readonly) UIColor *color;
+ (NSString *)hexFromColor:(UIColor *)color;
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
/// In the Private Vault: hidden from the main list and kept out of the Files app.
@property (nonatomic) BOOL vault;
/// The identifier of the folder this video was sorted into, nil when it sits loose in Downloads.
@property (nonatomic, copy, nullable) NSString *folderID;
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
+ (BOOL)hasUnfinishedDownloads;
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<VGItem *> *items;
/// Queued, running and failed downloads, oldest first.
@property (nonatomic, readonly) NSArray<VGTask *> *tasks;
/// Downloads still to finish (queued + running).
@property (nonatomic, readonly) NSUInteger activeCount;
/// YES when downloads were cut off and are waiting to resume (saved on disk).
+ (BOOL)hasUnfinished;
/// The first running download, for compact progress displays.
@property (nonatomic, readonly, nullable) VGTask *leadTask;

- (void)start;
- (void)fetch:(NSString *)url completion:(void (^)(VGVideo *_Nullable video, NSString *_Nullable error))completion;
/// Same, for a stream link the browser caught: `extra` carries "headers", "kind" (hls, dash or file), "title" and "page".
- (void)fetch:(NSString *)url extra:(nullable NSDictionary *)extra completion:(void (^)(VGVideo *_Nullable video, NSString *_Nullable error))completion;
/// Finds links the built-in player can play right away. Result: items (url + headers), hls, audio, height.
- (void)streamLinkFor:(VGVideo *)video option:(nullable VGOption *)option completion:(void (^)(NSDictionary *_Nullable info, NSString *_Nullable error))completion;
/// The link(s) a download of this option fetches (same lookup and same pick as the download). Result: items (url + headers), hls.
- (void)linkListFor:(VGVideo *)video option:(nullable VGOption *)option completion:(void (^)(NSDictionary *_Nullable info, NSString *_Nullable error))completion;
- (void)directLinkFor:(VGVideo *)video option:(VGOption *)option completion:(void (^)(NSDictionary *_Nullable info, NSString *_Nullable error))completion;
/// Adds a download to the queue (2 run at a time) and returns it.
- (VGTask *)download:(VGVideo *)video
              option:(VGOption *)option
            progress:(nullable VGProgress)progress
          completion:(nullable void (^)(VGItem *_Nullable item, NSString *_Nullable error))completion;
- (void)cancelTask:(VGTask *)task;
- (void)retryTask:(VGTask *)task;
- (void)dismissTask:(VGTask *)task;
- (void)deleteItem:(VGItem *)item;
/// Adds a video or audio file picked from Photos or Files to the library (it is copied, or moved when `move` is YES).
/// Does its work on the calling thread, so call it off the main queue. The completion runs on the main queue.
- (void)importFileAtURL:(NSURL *)url title:(nullable NSString *)title source:(NSString *)source move:(BOOL)move
             completion:(void (^)(VGItem *_Nullable item, NSString *_Nullable error))completion;
/// Folders, newest last.
@property (nonatomic, readonly) NSArray<VGFolder *> *folders;
- (nullable VGFolder *)folderWithID:(nullable NSString *)identifier;
- (VGFolder *)createFolderNamed:(NSString *)name colorHex:(NSString *)hex;
- (void)updateFolder:(VGFolder *)folder name:(NSString *)name colorHex:(NSString *)hex;
/// Removes the folder only. Its videos go back to the main Downloads list.
- (void)deleteFolder:(VGFolder *)folder;
/// Puts videos in a folder, or back in the main list when `folder` is nil. Videos in the Private Vault are skipped.
- (void)setItems:(NSArray<VGItem *> *)items folder:(nullable VGFolder *)folder;
- (NSArray<VGItem *> *)itemsInFolder:(VGFolder *)folder;
/// Moves a download into or out of the Private Vault.
- (void)setItem:(VGItem *)item inVault:(BOOL)vault;
/// A queue-ready option for playlist downloads: the engine picks each video's own best match.
/// quality: @"best", @"1080", @"720", @"480" or @"mp3".
+ (VGOption *)presetOption:(NSString *)quality;
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
