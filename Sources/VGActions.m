#import "VGActions.h"
#import "VGTheme.h"
#import <AVKit/AVKit.h>
#import <Photos/Photos.h>
#import "VGKeepAlive.h"

@implementation VGActions

+ (UIViewController *)top:(UIViewController *)vc {
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (void)play:(VGItem *)item from:(UIViewController *)vc {
    VGPlayerViewController *p = [VGPlayerViewController playerFor:item];
    [[self top:vc] presentViewController:p animated:YES completion:^{ [p start]; }];
}

+ (void)saveToPhotos:(VGItem *)item from:(UIViewController *)vc {
    NSURL *file = item.fileURL;
    if (item.audio) {
        [self alert:@"Audio can't go in Photos" message:@"Use Share or Save to Files to keep this audio file." from:vc];
        return;
    }
    if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(file.path)) {
        [self alert:@"Photos can't open this format"
            message:@"This video uses a format the Photos app doesn't accept. It's still in your Downloads, and you can use Save to Files or Share. Next time, pick a quality marked MP4."
               from:vc];
        return;
    }
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus st) {
        if (st != PHAuthorizationStatusAuthorized && st != PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self alert:@"No access to Photos" message:@"Turn on Photos access for VidGrab in Settings > Privacy & Security > Photos." from:vc];
            });
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:file];
        } completionHandler:^(BOOL ok, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (ok) {
                    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                    [self toast:@"Saved to Photos" icon:@"checkmark.circle.fill" in:vc.view.window ?: vc.view];
                } else {
                    [self alert:@"Couldn't save to Photos" message:err.localizedDescription ?: @"Try Share or Save to Files instead." from:vc];
                }
            });
        }];
    }];
}

+ (void)share:(VGItem *)item from:(UIViewController *)vc source:(UIView *)source {
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[item.fileURL] applicationActivities:nil];
    a.popoverPresentationController.sourceView = source;
    a.popoverPresentationController.sourceRect = source.bounds;
    [[self top:vc] presentViewController:a animated:YES completion:nil];
}

+ (void)saveToFiles:(VGItem *)item from:(UIViewController *)vc {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[item.fileURL] asCopy:YES];
    [[self top:vc] presentViewController:p animated:YES completion:nil];
}

+ (void)saveItemsToFiles:(NSArray<VGItem *> *)items from:(UIViewController *)vc {
    NSArray *urls = [items valueForKey:@"fileURL"];
    if (!urls.count) return;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForExportingURLs:urls asCopy:YES];
    [[self top:vc] presentViewController:p animated:YES completion:nil];
}

+ (void)shareItems:(NSArray<VGItem *> *)items from:(UIViewController *)vc source:(UIView *)source {
    NSArray *urls = [items valueForKey:@"fileURL"];
    if (!urls.count) return;
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    a.popoverPresentationController.sourceView = source;
    a.popoverPresentationController.sourceRect = source.bounds;
    [[self top:vc] presentViewController:a animated:YES completion:nil];
}

+ (void)saveItemsToPhotos:(NSArray<VGItem *> *)items from:(UIViewController *)vc {
    NSMutableArray<NSURL *> *ok = [NSMutableArray array];
    NSInteger audio = 0, format = 0;
    for (VGItem *i in items) {
        if (i.audio) audio++;
        else if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(i.fileURL.path)) format++;
        else [ok addObject:i.fileURL];
    }
    NSString *(^skipped)(void) = ^NSString *{
        NSMutableArray *why = [NSMutableArray array];
        if (audio) [why addObject:[NSString stringWithFormat:@"%ld audio %@ (Photos only takes video)", (long)audio, audio == 1 ? @"file" : @"files"]];
        if (format) [why addObject:[NSString stringWithFormat:@"%ld %@ in a format Photos doesn't accept", (long)format, format == 1 ? @"video" : @"videos"]];
        return why.count ? [NSString stringWithFormat:@"Skipped %@. Use Save to Files for those.", [why componentsJoinedByString:@" and "]] : nil;
    };
    if (!ok.count) { [self alert:@"Nothing to save to Photos" message:skipped() from:vc]; return; }
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus st) {
        if (st != PHAuthorizationStatusAuthorized && st != PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self alert:@"No access to Photos" message:@"Turn on Photos access for VidGrab in Settings > Privacy & Security > Photos." from:vc];
            });
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            for (NSURL *u in ok) [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:u];
        } completionHandler:^(BOOL success, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *more = skipped();
                if (!success) { [self alert:@"Couldn't save to Photos" message:err.localizedDescription from:vc]; return; }
                NSString *msg = [NSString stringWithFormat:@"Saved %lu %@ to Photos", (unsigned long)ok.count, ok.count == 1 ? @"video" : @"videos"];
                if (more) [self alert:msg message:more from:vc];
                else [self toast:msg icon:@"checkmark.circle.fill" in:vc.view.window ?: vc.view];
            });
        }];
    }];
}

+ (void)alert:(NSString *)title message:(NSString *)message from:(UIViewController *)vc {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[self top:vc] presentViewController:a animated:YES completion:nil];
}

static __weak UIView *gToast;

+ (void)toast:(NSString *)text icon:(NSString *)icon in:(UIView *)view { [self toast:text icon:icon in:view bottom:70]; }

+ (void)toast:(NSString *)text icon:(NSString *)icon in:(UIView *)view bottom:(CGFloat)bottom { [self toast:text icon:icon in:view bottom:bottom top:-1]; }

/// top >= 0 puts the message that far below the top edge (top centre) instead of above the bottom edge.
+ (void)toast:(NSString *)text icon:(NSString *)icon in:(UIView *)view top:(CGFloat)top { [self toast:text icon:icon in:view bottom:70 top:top]; }

+ (void)toast:(NSString *)text icon:(NSString *)icon in:(UIView *)view bottom:(CGFloat)bottom top:(CGFloat)top {
    if (!view) return;
    // A new message replaces the one still showing, so two never pile up on top of each other.
    UIView *old = gToast;
    if (old) { gToast = nil; [old.layer removeAllAnimations]; [old removeFromSuperview]; }   // gone at once: a fading copy used to stay on screen under the new one
    UIView *pill = [UIView new];
    pill.backgroundColor = [VGSurface2 colorWithAlphaComponent:0.97];
    pill.layer.cornerRadius = 22;
    pill.layer.borderColor = VGStroke.CGColor;
    pill.layer.borderWidth = 1;
    pill.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    iv.tintColor = VGAccent;
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = VGFont(15, UIFontWeightSemibold);
    l.textColor = UIColor.whiteColor;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[iv, l]];
    s.spacing = 8;
    s.alignment = UIStackViewAlignmentCenter;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [pill addSubview:s];
    [view addSubview:pill];
    gToast = pill;
    l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.75;
    [NSLayoutConstraint activateConstraints:@[
        [pill.widthAnchor constraintLessThanOrEqualToAnchor:view.widthAnchor constant:-24],
        [s.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:18],
        [s.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-18],
        [s.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [pill.heightAnchor constraintEqualToConstant:44],
        [pill.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        top >= 0 ? [pill.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:top]
                 : [pill.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor constant:-bottom],
    ]];
    // Place it before animating: otherwise the first layout happens inside the animation and the pill flies in from the corner.
    [view layoutIfNeeded];
    pill.alpha = 0;
    pill.transform = CGAffineTransformMakeTranslation(0, top >= 0 ? -12 : 12);
    [UIView animateWithDuration:0.25 animations:^{ pill.alpha = 1; pill.transform = CGAffineTransformIdentity; }
                     completion:^(BOOL f) {
        [UIView animateWithDuration:0.3 delay:1.6 options:0 animations:^{ pill.alpha = 0; }
                         completion:^(BOOL f2) { if (f2 || !pill.superview) { [pill removeFromSuperview]; if (gToast == pill) gToast = nil; } }];
    }];
}

@end
