#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^VGPyProgress)(int part, int parts, double fraction, NSString *stage, double speed, double eta);

/// Runs the embedded Python interpreter on its own queue.
@interface VGPython : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly, nullable) NSString *engineVersion;

- (void)start;
/// Per-download progress and cancel, keyed by a task id passed to the engine.
- (void)setProgressHandler:(nullable VGPyProgress)handler forTask:(NSString *)task;
- (void)cancelTask:(NSString *)task;
- (BOOL)isTaskCancelled:(NSString *)task;
- (void)forgetTask:(NSString *)task;
/// Calls module.function(*args) and returns the JSON result, parsed, on the main queue.
- (void)call:(NSString *)module
    function:(NSString *)function
        args:(NSArray<NSString *> *)args
  completion:(void (^)(NSDictionary *_Nullable result, NSString *_Nullable error))completion;

- (NSString *)engineDir;
- (NSString *)cacheDir;
@end

NS_ASSUME_NONNULL_END
