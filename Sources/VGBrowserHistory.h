#import <UIKit/UIKit.h>

/// The pages opened in the built-in browser, newest first, kept on the phone.
@interface VGBrowserHistory : NSObject
+ (NSArray<NSDictionary *> *)entries;           // each: url, title, time (seconds since 1970)
+ (NSDictionary *)latest;                       // the last page opened, or nil
+ (void)noteURL:(NSURL *)url title:(NSString *)title;
+ (void)removeAtIndex:(NSUInteger)index;
+ (void)clear;
@end

/// The History screen: search, tap to open, swipe to delete, Clear all.
@interface VGHistoryViewController : UITableViewController
@property (nonatomic, copy) void (^openURL)(NSString *url);
@end
