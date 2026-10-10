#import "VGHaptics.h"

@implementation VGHaptics

+ (BOOL)enabled {
    id v = [NSUserDefaults.standardUserDefaults objectForKey:@"vgHaptics"];
    return v ? [v boolValue] : YES;
}
+ (void)setEnabled:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:@"vgHaptics"]; }

+ (void)tap {
    if (!self.enabled) return;
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}
+ (void)select {
    if (!self.enabled) return;
    UISelectionFeedbackGenerator *g = [UISelectionFeedbackGenerator new];
    [g selectionChanged];
}
+ (void)success {
    if (!self.enabled) return;
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
}
+ (void)warning {
    if (!self.enabled) return;
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeWarning];
}

@end
