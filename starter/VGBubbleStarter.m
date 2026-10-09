#import <Foundation/Foundation.h>
#import <notify.h>
#import <spawn.h>

extern char **environ;
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *attr, uid_t persona_id, uint32_t flags);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *attr, uid_t uid);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *attr, uid_t gid);

#define N_RESULT "com.t4mag0.vidgrab.starter.result"

static void Report(uint64_t v) {
    int t = 0;
    notify_register_check(N_RESULT, &t);
    notify_set_state(t, v);
    notify_post(N_RESULT);
}

/// Runs inside VidGrab's hidden starter extension. It carries the special permissions, so VidGrab itself doesn't need them.
@interface VGBubbleStarter : NSObject
@end

static BOOL gRan;

static void StartHUD(void) {
    if (gRan) return;
    gRan = YES;
    Report(3);   // the extension process started
    // .../VidGrab.app/PlugIns/VGBubbleStarter.appex -> .../VidGrab.app/VidGrabHUD
    NSString *app = [[NSBundle.mainBundle.bundlePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString *path = [app stringByAppendingPathComponent:@"VidGrabHUD"];
    char *args[] = {(char *)path.fileSystemRepresentation, "-daemon", NULL};
    uint64_t result = 0;   // 1 = started as root, 2 = started as app, 100+code = failed
    for (int root = 1; root >= 0 && !result; root--) {
        posix_spawnattr_t attr;
        posix_spawnattr_init(&attr);
        if (root) {
            posix_spawnattr_set_persona_np(&attr, 99, 1);
            posix_spawnattr_set_persona_uid_np(&attr, 0);
            posix_spawnattr_set_persona_gid_np(&attr, 0);
        }
        pid_t pid = 0;
        int rc = posix_spawn(&pid, args[0], NULL, &attr, args, environ);
        posix_spawnattr_destroy(&attr);
        if (rc == 0) result = root ? 1 : 2;
        else if (!root) result = 100 + rc;
    }
    Report(result);
}

// Runs as soon as the extension process loads, even if iOS never hands it a request.
__attribute__((constructor)) static void StarterLoaded(void) { StartHUD(); }

@implementation VGBubbleStarter

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    StartHUD();
    [context completeRequestReturningItems:@[] completionHandler:nil];
}

@end
