#import <Foundation/Foundation.h>

/// Keeps downloads going after you leave the app (iOS would pause it within seconds),
/// then sends a notification when they're done. Your music keeps playing.
@interface VGKeepAlive : NSObject
@property (class, nonatomic) BOOL enabled;   // Settings > Keep downloading in background (on by default)
+ (void)start;
/// The video player changed the sound settings; put ours back if we're still working.
+ (void)playerClosed;
/// The "downloads finished" sound (Settings > Sound when done).
+ (void)playFinishSound;
/// Settings > Test sound: plays the sound like a notification, then like music, and reports what happened.
/// With later, it waits 5 seconds first so you can leave the app.
+ (void)testSoundLater:(BOOL)later completion:(void (^)(NSString *report))done;
@end
