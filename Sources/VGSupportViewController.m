#import "VGSupportViewController.h"
#import "VGTheme.h"
#import "VGActions.h"

@implementation VGSupportViewController

- (void)presentFrom:(UIViewController *)host {
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = self.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
    sheet.prefersGrabberVisible = YES;
    sheet.preferredCornerRadius = 22;
    [host presentViewController:self animated:YES completion:nil];
}

- (NSDictionary *)config {
    NSString *path = [NSBundle.mainBundle pathForResource:@"support" ofType:@"json"];
    NSData *d = path ? [NSData dataWithContentsOfFile:path] : nil;
    id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [obj isKindOfClass:NSDictionary.class] ? obj : @{};
}

- (UILabel *)label:(UIFont *)f color:(UIColor *)c {
    UILabel *l = [UILabel new];
    l.font = f;
    l.textColor = c;
    l.numberOfLines = 0;
    return l;
}

/// One "label / value / copy" row on the Wise card.
- (UIView *)rowTitle:(NSString *)title value:(NSString *)value {
    UILabel *t = [self label:VGFont(12, UIFontWeightHeavy) color:VGTertiary];
    t.attributedText = [[NSAttributedString alloc] initWithString:title.uppercaseString attributes:@{NSKernAttributeName: @0.8}];
    UILabel *v = [self label:VGFont(16, UIFontWeightSemibold) color:VGText];
    v.text = value;
    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[t, v]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 2;
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    [copy setImage:[UIImage systemImageNamed:@"doc.on.doc" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold]]
          forState:UIControlStateNormal];
    copy.tintColor = VGAccent;
    copy.accessibilityLabel = [@"Copy " stringByAppendingString:title];
    [copy setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [copy.widthAnchor constraintEqualToConstant:44].active = YES;
    [copy addAction:[UIAction actionWithHandler:^(UIAction *a) {
        UIPasteboard.generalPasteboard.string = value;
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [VGActions toast:[title stringByAppendingString:@" copied"] icon:@"doc.on.doc.fill" in:self.view];
    }] forControlEvents:UIControlEventTouchUpInside];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[texts, copy]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    return row;
}

- (UIView *)cardFor:(NSDictionary *)m {
    NSString *name = [m[@"name"] isKindOfClass:NSString.class] ? m[@"name"] : @"";
    NSString *link = [m[@"link"] isKindOfClass:NSString.class] ? m[@"link"] : @"";
    NSString *qrFile = [m[@"qr"] isKindOfClass:NSString.class] ? m[@"qr"] : @"";
    UIImage *qr = qrFile.length ? [UIImage imageNamed:qrFile] : nil;
    if (!name.length || (!link.length && !qr)) return nil;

    UILabel *title = [self label:VGFont(13, UIFontWeightHeavy) color:VGText];
    title.attributedText = [[NSAttributedString alloc] initWithString:[@"SEND WITH " stringByAppendingString:name.uppercaseString]
                                                           attributes:@{NSKernAttributeName: @1.0}];
    NSMutableArray *parts = [NSMutableArray arrayWithObject:title];

    if (qr) {
        // White tile so the code scans well from a dark screen.
        UIView *tile = [UIView new];
        tile.backgroundColor = UIColor.whiteColor;
        tile.layer.cornerRadius = 16;
        tile.layer.cornerCurve = kCACornerCurveContinuous;
        UIImageView *iv = [[UIImageView alloc] initWithImage:qr];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.accessibilityLabel = [name stringByAppendingString:@" QR code"];
        iv.isAccessibilityElement = YES;
        [tile addSubview:iv];
        tile.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [iv.topAnchor constraintEqualToAnchor:tile.topAnchor constant:10],
            [iv.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor constant:-10],
            [iv.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:10],
            [iv.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-10],
            [tile.widthAnchor constraintEqualToConstant:220],
            [tile.heightAnchor constraintEqualToConstant:220],
        ]];
        UIView *center = [UIView new];
        [center addSubview:tile];
        [NSLayoutConstraint activateConstraints:@[
            [tile.topAnchor constraintEqualToAnchor:center.topAnchor],
            [tile.bottomAnchor constraintEqualToAnchor:center.bottomAnchor],
            [tile.centerXAnchor constraintEqualToAnchor:center.centerXAnchor],
        ]];
        [parts addObject:center];
    }

    if (link.length) {
        UIButton *open = VGPrimaryButton([@"Open " stringByAppendingString:name], @"arrow.up.right");
        [open addAction:[UIAction actionWithHandler:^(UIAction *a) {
            NSURL *u = [NSURL URLWithString:link];
            if (u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
        }] forControlEvents:UIControlEventTouchUpInside];
        [parts addObject:open];
    }

    NSMutableArray *small = [NSMutableArray array];
    if (link.length) {
        UIButton *copy = VGSecondaryButton(@"Copy link", @"link");
        [copy addAction:[UIAction actionWithHandler:^(UIAction *a) {
            UIPasteboard.generalPasteboard.string = link;
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            [VGActions toast:[name stringByAppendingString:@" link copied"] icon:@"doc.on.doc.fill" in:self.view];
        }] forControlEvents:UIControlEventTouchUpInside];
        [small addObject:copy];
    }
    if (qr) {
        UIButton *save = VGSecondaryButton(@"Save QR", @"square.and.arrow.down");
        [save addAction:[UIAction actionWithHandler:^(UIAction *a) {
            UIImageWriteToSavedPhotosAlbum(qr, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
        }] forControlEvents:UIControlEventTouchUpInside];
        [small addObject:save];
    }
    if (small.count) {
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:small];
        row.spacing = 10;
        row.distribution = UIStackViewDistributionFillEqually;
        [parts addObject:row];
    }

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:parts];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    UIView *card = [UIView new];
    card.backgroundColor = VGSurface2;
    card.layer.cornerRadius = 14;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderColor = VGStroke.CGColor;
    card.layer.borderWidth = 1;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
    ]];
    return card;
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)info {
    if (error) [VGActions alert:@"Couldn't save the QR code" message:@"Allow VidGrab to add photos in Settings > Privacy & Security > Photos." from:self];
    else [VGActions toast:@"QR code saved to Photos" icon:@"checkmark.circle.fill" in:self.view];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VGSurface;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    NSDictionary *cfg = [self config];

    // Coffee badge
    UIView *badge = [UIView new];
    badge.backgroundColor = [VGAccent colorWithAlphaComponent:0.15];
    badge.layer.cornerRadius = 36;
    UIImageView *cup = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"cup.and.saucer.fill"
                                                               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:32 weight:UIImageSymbolWeightSemibold]]];
    cup.tintColor = VGAccent;
    cup.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:cup];
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:72],
        [badge.heightAnchor constraintEqualToConstant:72],
        [cup.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [cup.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
    ]];

    UILabel *title = [self label:VGFont(26, UIFontWeightHeavy) color:VGText];
    title.text = cfg[@"title"] ?: @"Buy me a coffee";
    title.textAlignment = NSTextAlignmentCenter;
    UILabel *msg = [self label:VGFont(15, UIFontWeightRegular) color:VGSecondary];
    msg.text = cfg[@"message"] ?: @"";
    msg.textAlignment = NSTextAlignmentCenter;

    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[badge, title, msg]];
    top.axis = UILayoutConstraintAxisVertical;
    top.alignment = UIStackViewAlignmentCenter;
    top.spacing = 10;
    [top setCustomSpacing:16 afterView:badge];

    // One card per payment method (Wise, PayPal), each with its QR code.
    NSMutableArray *cards = [NSMutableArray array];
    NSArray *methods = [cfg[@"methods"] isKindOfClass:NSArray.class] ? cfg[@"methods"] : @[];
    for (NSDictionary *m in methods) {
        if (![m isKindOfClass:NSDictionary.class]) continue;
        UIView *card = [self cardFor:m];
        if (card) [cards addObject:card];
    }
    if (!cards.count) {
        UILabel *soon = [self label:VGFont(15, UIFontWeightMedium) color:VGSecondary];
        soon.text = @"Donation details are coming soon. Thanks for wanting to help!";
        soon.textAlignment = NSTextAlignmentCenter;
        [cards addObject:soon];
    }
    UILabel *hint = [self label:VGFont(12, UIFontWeightMedium) color:VGTertiary];
    hint.text = @"On this phone? Tap Open. On another device? Scan the QR code.";
    hint.textAlignment = NSTextAlignmentCenter;
    hint.hidden = methods.count == 0;
    UIStackView *cardList = [[UIStackView alloc] initWithArrangedSubviews:[cards arrayByAddingObject:hint]];
    cardList.axis = UILayoutConstraintAxisVertical;
    cardList.spacing = 16;
    UIView *card = cardList;

    UIStackView *root = [[UIStackView alloc] initWithArrangedSubviews:@[top, card]];
    root.axis = UILayoutConstraintAxisVertical;
    root.spacing = 26;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];
    [scroll addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:34],
        [root.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [root.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:22],
        [root.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-22],
    ]];
}

@end
