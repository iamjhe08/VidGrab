#import <UIKit/UIKit.h>

/// Floating download progress button: a filling ring, the percentage, and a badge
/// with the number of downloads when more than one is running. Shown above the tab bar.
@interface VGProgressPill : UIControl
/// Re-reads the download queue and updates (and shows or hides) the pill.
- (void)refresh;
/// Hides the pill on screens that show progress their own way.
@property (nonatomic) BOOL suppressed;
@end
