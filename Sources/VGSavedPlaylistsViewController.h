#import <UIKit/UIKit.h>

/// The playlists saved in VidGrab. Tap one to open it on Home (checklist, stream, download).
@interface VGSavedPlaylistsViewController : UITableViewController
@end

/// Posted to open a saved playlist on Home. userInfo: @{@"id": identifier}
extern NSString *const VGOpenSavedPlaylist;
