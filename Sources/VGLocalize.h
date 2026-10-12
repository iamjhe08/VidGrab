#import <UIKit/UIKit.h>

/// Language of the app's own text. "auto" follows the phone, otherwise a language code such as "en" or "zh-Hans".
@interface VGLocalize : NSObject
+ (void)start;                                  // call once at launch (installs the text hooks)
+ (NSString *)choice;                           // "auto", "en", "zh-Hans"
+ (void)setChoice:(NSString *)choice;
+ (NSString *)activeCode;                       // the language really in use ("en" or "zh-Hans")
+ (NSArray<NSString *> *)choices;               // all values for the picker
+ (NSString *)nameForChoice:(NSString *)choice; // shown in the picker (always in its own language)
+ (NSString *)translate:(NSString *)english;
/// Shows the language list; changing it rebuilds the app's pages. `done` runs after a change.
+ (void)presentPickerFrom:(UIViewController *)vc source:(UIView *)source done:(void (^)(void))done;    // returns the same string when there is nothing to change
@end

/// Short form for text that is built in code.
#define VGT(s) ([VGLocalize translate:(s)])
