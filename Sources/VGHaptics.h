#import <UIKit/UIKit.h>

/// Small taps on the phone's vibration motor. One switch in Settings turns them all off.
@interface VGHaptics : NSObject
@property (class, nonatomic) BOOL enabled;   // on by default
+ (void)tap;        // a light press
+ (void)select;     // a switch, a tab, a choice
+ (void)success;    // something finished
+ (void)warning;    // something failed
@end
