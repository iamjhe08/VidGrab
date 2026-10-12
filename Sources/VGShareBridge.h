#import <Foundation/Foundation.h>

/// Lets the Share > VidGrab extension hand a link to VidGrab without opening it, when VidGrab is still awake in the
/// background (downloads or music running). The extension talks to a tiny listener on this phone only (127.0.0.1).
/// If nothing answers, the extension opens the app as before.
@interface VGShareBridge : NSObject
+ (void)start;
/// A link that needs a choice (a playlist, or no default quality set) waits here until VidGrab is opened.
+ (nullable NSString *)takePendingLink;
/// YES the first time a link is claimed for auto-download within a minute; NO for a repeat (so it never downloads twice).
+ (BOOL)claimLink:(nonnull NSString *)link;

@end
