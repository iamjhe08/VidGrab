#import "VGActions.h"
#import "VGTheme.h"
#import <AVKit/AVKit.h>
#import <Photos/Photos.h>

@implementation VGActions

+ (UIViewController *)top:(UIViewController *)vc {
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (void)play:(VGItem *)item from:(UIViewController *)vc {
    AVPlayerViewController *p = [AVPlayerViewController new];
    p.player = [AVPlayer playerWithURL:item.fileURL];
    p.allowsPictureInPicturePlayback = YES;
    [[self top:vc] presentViewController:p animated:YES completion:^{ [p.player play]; }];
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

+ (void)alert:(NSString *)title message:(NSString *)message from:(UIViewController *)vc {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[self top:vc] presentViewController:a animated:YES completion:nil];
}

+ (void)toast:(NSString *)text icon:(NSString *)icon in:(UIView *)view {
    if (!view) return;
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
    [NSLayoutConstraint activateConstraints:@[
        [s.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:18],
        [s.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-18],
        [s.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [pill.heightAnchor constraintEqualToConstant:44],
        [pill.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [pill.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor constant:-70],
    ]];
    pill.alpha = 0;
    pill.transform = CGAffineTransformMakeTranslation(0, 12);
    [UIView animateWithDuration:0.25 animations:^{ pill.alpha = 1; pill.transform = CGAffineTransformIdentity; }
                     completion:^(BOOL f) {
        [UIView animateWithDuration:0.3 delay:1.6 options:0 animations:^{ pill.alpha = 0; }
                         completion:^(BOOL f2) { [pill removeFromSuperview]; }];
    }];
}

@end
