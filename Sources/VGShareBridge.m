#import "VGShareBridge.h"
#import "VGEngine.h"
#import "VGDownloadDefaults.h"
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>

static const uint16_t kPort = 47631;
static NSString *const kPendingKey = @"vgPendingShareLink";
static int gListenFD = -1;

@implementation VGShareBridge

+ (NSString *)takePendingLink {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *s = [d stringForKey:kPendingKey];
    if (s) [d removeObjectForKey:kPendingKey];
    return s;
}

+ (void)start {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    // The phone may close the listener while VidGrab sleeps; open it again every time the app wakes.
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [self listen]; }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [self listen]; }];
    [self listen];
}

+ (void)listen {
    if (gListenFD >= 0) { close(gListenFD); gListenFD = -1; }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return;
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    struct sockaddr_in a = {0};
    a.sin_len = sizeof a; a.sin_family = AF_INET; a.sin_port = htons(kPort);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);   // this phone only
    if (bind(fd, (struct sockaddr *)&a, sizeof a) != 0 || listen(fd, 4) != 0) { close(fd); return; }
    gListenFD = fd;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        while (gListenFD == fd) {
            int c = accept(fd, NULL, NULL);
            if (c < 0) break;
            [self serve:c];
        }
    });
}

+ (void)serve:(int)c {
    struct timeval tv = {2, 0};
    setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    char buf[4096] = {0};
    ssize_t n = recv(c, buf, sizeof buf - 1, 0);
    NSString *reply = @"no";
    if (n > 0) {
        NSString *req = [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding];
        NSString *link = nil;
        NSRange r = [req rangeOfString:@"GET /add?url="];
        if (r.location != NSNotFound) {
            NSString *rest = [req substringFromIndex:NSMaxRange(r)];
            NSRange sp = [rest rangeOfString:@" "];
            if (sp.location != NSNotFound) rest = [rest substringToIndex:sp.location];
            link = rest.stringByRemovingPercentEncoding;
        }
        if ([link hasPrefix:@"http"]) reply = [self accept:link];
    }
    NSString *http = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n%@", (unsigned long)reply.length, reply];
    send(c, http.UTF8String, strlen(http.UTF8String), 0);
    close(c);
}

static NSString *gLast; static NSDate *gWhen;

+ (BOOL)claimLink:(NSString *)link {
    @synchronized (self) {
        NSString *last = gLast; NSDate *when = gWhen;
        if (last && [last isEqualToString:link] && when && -[when timeIntervalSinceNow] < 60) return NO;
        gLast = [link copy]; gWhen = [NSDate date];
        return YES;
    }
}

/// "ok" = VidGrab takes it from here, "open" = the app has to be opened to choose.
+ (NSString *)accept:(NSString *)link {
    __block UIApplicationState state = UIApplicationStateActive;
    dispatch_sync(dispatch_get_main_queue(), ^{ state = UIApplication.sharedApplication.applicationState; });
    BOOL canRunUnattended = VGDownloadDefaults.skipSheet && VGDownloadDefaults.autoStartShared;
    if (state == UIApplicationStateActive || !canRunUnattended) return @"open";   // on screen, or a choice is needed: the app opens as usual
    if (![self claimLink:link]) return @"ok";   // already being handled
    dispatch_async(dispatch_get_main_queue(), ^{
        [[VGEngine shared] fetch:link completion:^(VGVideo *video, NSString *error) {
            VGOption *opt = (video && !video.isPlaylist) ? [VGDownloadDefaults autoPickFrom:video.options] : nil;
            if (opt) {
                [[VGEngine shared] download:video option:opt progress:nil completion:nil];
                [self notify:@"Download started" body:video.title ?: link];
            } else {
                gLast = nil;   // the app still has to handle this one
                [NSUserDefaults.standardUserDefaults setObject:link forKey:kPendingKey];
                [self notify:video.isPlaylist ? @"Playlist ready" : (video ? @"Choose a quality" : @"Couldn't read that link") body:@"Open VidGrab to continue."];
            }
        }];
    });
    return @"ok";
}

+ (void)notify:(NSString *)title body:(NSString *)body {
    UNMutableNotificationContent *c = [UNMutableNotificationContent new];
    c.title = title; c.body = body;
    UNNotificationRequest *r = [UNNotificationRequest requestWithIdentifier:NSUUID.UUID.UUIDString content:c
                                                                    trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO]];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:r withCompletionHandler:nil];
}

@end
