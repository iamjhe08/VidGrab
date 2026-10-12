// Share > VidGrab. Takes the link (or text with a link) from the share sheet and hands it to the app.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>
static void *objc_msgSend_ptr(void) { return (void *)objc_msgSend; }

@interface VGShareViewController : UIViewController
@end

@implementation VGShareViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSMutableArray<NSItemProvider *> *providers = [NSMutableArray array];
    for (NSExtensionItem *it in self.extensionContext.inputItems) [providers addObjectsFromArray:it.attachments ?: @[]];
    [self findLink:providers index:0];
}

- (void)findLink:(NSArray<NSItemProvider *> *)providers index:(NSUInteger)i {
    if (i >= providers.count) { [self done]; return; }
    NSItemProvider *p = providers[i];
    NSString *urlType = UTTypeURL.identifier, *textType = UTTypePlainText.identifier;
    __weak typeof(self) ws = self;
    if ([p hasItemConformingToTypeIdentifier:urlType]) {
        [p loadItemForTypeIdentifier:urlType options:nil completionHandler:^(id item, NSError *e) {
            NSString *s = [item isKindOfClass:NSURL.class] ? [(NSURL *)item absoluteString] : ([item isKindOfClass:NSString.class] ? item : nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (s.length) [ws openApp:s]; else [ws findLink:providers index:i + 1];
            });
        }];
    } else if ([p hasItemConformingToTypeIdentifier:textType]) {
        [p loadItemForTypeIdentifier:textType options:nil completionHandler:^(id item, NSError *e) {
            NSString *t = [item isKindOfClass:NSString.class] ? item : nil;
            NSString *found = nil;
            if (t.length) {
                NSDataDetector *d = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
                NSTextCheckingResult *m = [d firstMatchInString:t options:0 range:NSMakeRange(0, t.length)];
                found = m.URL.absoluteString;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (found.length) [ws openApp:found]; else [ws findLink:providers index:i + 1];
            });
        }];
    } else {
        [self findLink:providers index:i + 1];
    }
}

/// First try VidGrab in the background (works while it is still awake); if it does not answer, open the app.
- (void)openApp:(NSString *)link {
    NSString *enc = [link stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
    NSURL *quick = [NSURL URLWithString:[@"http://127.0.0.1:47631/add?url=" stringByAppendingString:enc ?: @""]];
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 1.5;
    __weak typeof(self) ws = self;
    [[[NSURLSession sessionWithConfiguration:cfg] dataTaskWithURL:quick completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSString *reply = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([reply isEqualToString:@"ok"]) [ws showAdded];
            else [ws openAppDirectly:link];
        });
    }] resume];
}

- (void)showAdded {
    UILabel *l = [UILabel new];
    l.text = @"  Sent to VidGrab  ";
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    l.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.92];
    l.layer.cornerRadius = 14; l.clipsToBounds = YES;
    [l sizeToFit];
    l.frame = CGRectInset(l.frame, -10, -12);
    l.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    [self.view addSubview:l];
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws done]; });
}

- (void)openAppDirectly:(NSString *)link {
    NSURLComponents *c = [NSURLComponents componentsWithString:@"vidgrab://download"];
    c.queryItems = @[[NSURLQueryItem queryItemWithName:@"url" value:link]];
    NSURL *url = c.URL;
    __weak typeof(self) ws = self;
    // An extension can't call UIApplication directly; walk up to it and ask it to open the app.
    UIResponder *r = self;
    SEL openSel = NSSelectorFromString(@"openURL:options:completionHandler:");
    while (r) {
        if ([r isKindOfClass:UIApplication.class]) {
            UIApplication *app = (UIApplication *)r;
            if ([app respondsToSelector:openSel]) {
                void (*send)(id, SEL, NSURL *, NSDictionary *, id) = (void *)objc_msgSend_ptr();
                send(app, openSel, url, @{}, nil);
            }
            break;
        }
        r = r.nextResponder;
    }
    [self.extensionContext openURL:url completionHandler:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws done]; });
}

- (void)done {
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

@end
