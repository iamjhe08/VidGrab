#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// How the Private Vault is locked: a VidGrab passcode, Face ID (or Touch ID), or both.
/// With both, either one opens the vault, so a problem with one never locks you out.
@interface VGVaultLock : NSObject

/// The one-time warning shown the first time the vault is opened. Calls `next` right away when it was already shown.
+ (void)warnFirstTimeFrom:(UIViewController *)vc then:(void (^)(void))next;

/// Opens the vault. The first time, it asks you to choose a lock and set it up.
+ (void)unlockFrom:(UIViewController *)vc completion:(void (^)(BOOL ok))done;

/// "Face ID" or "Touch ID" for this phone, or nil when it has neither.
+ (nullable NSString *)biometryName;

/// "Passcode and Face ID", "Passcode", "Face ID", or "Not set up".
+ (NSString *)methodDescription;
+ (BOOL)isSetUp;
+ (BOOL)usesPasscode;

/// From Settings: confirms it's you, then lets you pick a new lock or a new passcode.
+ (void)changeLockFrom:(UIViewController *)vc completion:(void (^)(void))done;
+ (void)changePasscodeFrom:(UIViewController *)vc completion:(void (^)(void))done;

@end

NS_ASSUME_NONNULL_END
