#import <Foundation/Foundation.h>
@class VGItem;

/// Song words from LRCLIB (free, no key). Synced lines come with times in seconds.
@interface VGLyrics : NSObject
@property (nonatomic, copy) NSArray<NSString *> *lines;
@property (nonatomic, copy) NSArray<NSNumber *> *times;   // empty when the words are not synced
@property (nonatomic, readonly) BOOL synced;
/// Seconds the words are pushed later (+) or earlier (-) to match this copy of the song. Saved with the song.
@property (nonatomic) double offset;
- (void)saveFor:(VGItem *)item;
+ (void)save:(VGLyrics *)lyrics for:(VGItem *)item;
/// Cached answer for this song, if any.
+ (VGLyrics *)cachedFor:(VGItem *)item;
/// Looks the song up. `query` (optional) replaces the guessed title. Calls back on the main thread; nil means nothing found.
+ (void)loadFor:(VGItem *)item query:(NSString *)query completion:(void (^)(VGLyrics *lyrics))done;
/// The text that will be searched for this song (used to pre-fill the Search again box).
+ (NSString *)guessFor:(VGItem *)item;
/// Index of the line that is playing at `t`, or -1.
- (NSInteger)lineAt:(double)t;
@end
