#import <UIKit/UIKit.h>
#import "VGEngine.h"

NS_ASSUME_NONNULL_BEGIN

/// Playlists the viewer saved in VidGrab (the list of videos only, nothing is downloaded).
@interface VGSavedPlaylist : NSObject
@property (nonatomic, copy) NSString *identifier, *title, *url;
@property (nonatomic, copy, nullable) NSString *site, *uploader, *thumbnail;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, copy) NSArray<NSDictionary *> *entries;   // url, title, duration, thumbnail
/// The same playlist as a VGVideo, ready for the playlist card on Home.
- (VGVideo *)asVideo;
@end

@interface VGPlaylistStore : NSObject
+ (NSArray<VGSavedPlaylist *> *)all;
+ (nullable VGSavedPlaylist *)withID:(NSString *)identifier;
+ (nullable VGSavedPlaylist *)forURL:(NSString *)url;
/// Saves (or refreshes) a playlist from the Home card.
+ (VGSavedPlaylist *)save:(VGVideo *)playlist;
+ (void)remove:(VGSavedPlaylist *)p;
+ (void)rename:(VGSavedPlaylist *)p to:(NSString *)title;
@end

extern NSString *const VGSavedPlaylistsChanged;

NS_ASSUME_NONNULL_END
