#import "VGStorageView.h"
#import "VGTheme.h"

@interface VGStorageView ()
@property (nonatomic, strong) UILabel *freeLabel, *appLabel;
@property (nonatomic, strong) UIView *track, *otherFill, *appFill;
@property (nonatomic) double appShare, otherShare;   // 0 to 1 of the whole phone
@property (nonatomic, copy, readwrite) NSString *detailsText;
@end

@implementation VGStorageView

// Sizes the way iPhone Settings writes them: decimal GB (1 GB = 1,000,000,000 bytes), two decimals for free space.
static NSString *gb2(long long b) {
    double g = (double)b / 1e9;
    if (g >= 1000) return [NSString stringWithFormat:@"%.2f TB", g / 1000];
    return [NSString stringWithFormat:@"%.2f GB", g];
}

// VidGrab's own share is small, so it reads better in the usual units.
static NSString *sizeShort(long long b) {
    NSByteCountFormatter *f = [NSByteCountFormatter new];
    f.countStyle = NSByteCountFormatterCountStyleFile;
    f.allowedUnits = NSByteCountFormatterUseMB | NSByteCountFormatterUseGB | NSByteCountFormatterUseTB;
    return [f stringFromByteCount:b];
}

// The phone's size as it is sold (the disk itself reports a bit less): 64, 128, 256, 512 GB, 1 TB, 2 TB.
static NSString *capacityName(long long total) {
    double g = (double)total / 1e9;
    static const double sizes[] = {16, 32, 64, 128, 256, 512, 1000, 2000};
    for (int i = 0; i < 8; i++) {
        if (g <= sizes[i] && g >= sizes[i] * 0.85) return sizes[i] >= 1000 ? [NSString stringWithFormat:@"%g TB", sizes[i] / 1000] : [NSString stringWithFormat:@"%g GB", sizes[i]];
    }
    return gb2(total);
}

// The bar's color follows how full the phone is: blue when nearly empty, green, yellow at 75%, orange at 85%, VidGrab red when nearly full.
static UIColor *usageColor(double used) {
    if (used >= 0.95) return VGAccent;
    if (used >= 0.85) return VGHex(0xFF9F0A);
    if (used >= 0.75) return VGHex(0xFFD60A);
    if (used >= 0.35) return VGHex(0x30D158);
    return VGHex(0x0A84FF);
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = VGSurface;
        self.layer.cornerRadius = 12;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1;
        self.layer.borderColor = VGStroke.CGColor;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];

        _freeLabel = [UILabel new];
        _freeLabel.font = VGFont(12, UIFontWeightBold);
        _freeLabel.textColor = VGText;
        _freeLabel.adjustsFontSizeToFitWidth = YES;
        _freeLabel.minimumScaleFactor = 0.7;
        _freeLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        _track = [UIView new];
        _track.backgroundColor = VGSurface2;
        _track.layer.cornerRadius = 4;
        _track.clipsToBounds = YES;
        _otherFill = [UIView new];
        _otherFill.backgroundColor = VGHex(0x7A7A88);
        _appFill = [UIView new];
        _appFill.backgroundColor = VGAccent;
        [_track addSubview:_otherFill];
        [_track addSubview:_appFill];

        _appLabel = [UILabel new];
        _appLabel.font = VGFont(11, UIFontWeightSemibold);
        _appLabel.textColor = VGSecondary;
        _appLabel.adjustsFontSizeToFitWidth = YES;
        _appLabel.minimumScaleFactor = 0.7;
        _appLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        for (UIView *v in @[_freeLabel, _track, _appLabel]) [self addSubview:v];
    }
    return self;
}

- (void)tapped { if (self.onTap) self.onTap(); }

- (CGSize)sizeThatFits:(CGSize)s { return CGSizeMake(s.width, 60); }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat pad = 10, w = self.bounds.size.width - pad * 2, h = self.bounds.size.height;
    // Three rows (text, bar, text) centered in the card.
    CGFloat textH = 15, barH = 8, gap = 5;
    CGFloat total = textH + gap + barH + gap + textH;
    CGFloat y = floor((h - total) / 2);
    self.freeLabel.frame = CGRectMake(pad, y, w, textH);
    self.track.frame = CGRectMake(pad, y + textH + gap, w, barH);
    self.appLabel.frame = CGRectMake(pad, y + textH + gap + barH + gap, w, textH);
    [self layoutBar];
}

- (void)layoutBar {
    CGFloat w = self.track.bounds.size.width, h = self.track.bounds.size.height;
    // Even a tiny share gets a visible sliver.
    CGFloat app = self.appShare > 0 ? MAX(3, (CGFloat)(self.appShare * w)) : 0;
    CGFloat other = (CGFloat)(self.otherShare * w);
    app = MIN(app, w);
    other = MIN(other, w - app);
    self.appFill.frame = CGRectMake(0, 0, app, h);
    self.otherFill.frame = CGRectMake(app, 0, other, h);
}

- (void)refreshWithVidGrabBytes:(long long)vid {
    NSDictionary *v = [[NSURL fileURLWithPath:NSHomeDirectory()] resourceValuesForKeys:@[NSURLVolumeTotalCapacityKey,
                                                                                          NSURLVolumeAvailableCapacityForImportantUsageKey,
                                                                                          NSURLVolumeAvailableCapacityKey] error:nil];
    long long total = [v[NSURLVolumeTotalCapacityKey] longLongValue];
    // Apple documents this figure as the one that is closest to what Settings shows: free space plus the caches and
    // other data iOS clears by itself when it needs room. (The plain "free right now" number is several GB lower.)
    long long free = [v[NSURLVolumeAvailableCapacityForImportantUsageKey] longLongValue];
    long long freeNow = [v[NSURLVolumeAvailableCapacityKey] longLongValue];
    if (free <= 0) free = freeNow;
    if (total <= 0) {
        self.freeLabel.text = @"Storage unavailable";
        self.detailsText = @"The phone did not report its storage.";
        self.appLabel.text = @"";
        self.appShare = self.otherShare = 0;
        self.accessibilityLabel = @"Storage unavailable";
        [self layoutBar];
        return;
    }
    free = MIN(MAX(free, 0), total);
    long long used = total - free;
    vid = MIN(MAX(vid, 0), used);
    self.appShare = (double)vid / (double)total;
    self.otherShare = (double)(used - vid) / (double)total;
    NSDictionary *more = [[NSURL fileURLWithPath:NSHomeDirectory()] resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey, NSURLVolumeAvailableCapacityForOpportunisticUsageKey] error:nil];
    long long opportunistic = [more[NSURLVolumeAvailableCapacityForOpportunisticUsageKey] longLongValue];
    self.detailsText = [NSString stringWithFormat:
        @"Capacity (disk): %@\nFree (shown on the card): %@\nUsed: %@\nFree right now, without space iOS can clear: %@\nFree for optional files: %@\nVidGrab videos: %@\n\nSettings works this number out in its own way, so it can differ from the card by a little.",
        gb2(total), gb2(free), gb2(used), gb2(freeNow), gb2(opportunistic), gb2(vid)];
    UIColor *c = usageColor((double)used / (double)total);
    // The whole used part takes the color; VidGrab's own share is a lighter tint of it at the start of the bar.
    self.otherFill.backgroundColor = c;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [c getRed:&r green:&g blue:&b alpha:&a];
    self.appFill.backgroundColor = [UIColor colorWithRed:r + (1 - r) * 0.55 green:g + (1 - g) * 0.55 blue:b + (1 - b) * 0.55 alpha:1];
    self.freeLabel.text = [NSString stringWithFormat:@"%@ free of %@", gb2(free), capacityName(total)];
    self.appLabel.text = [NSString stringWithFormat:@"VidGrab %@", sizeShort(vid)];
    self.accessibilityLabel = [NSString stringWithFormat:@"Phone storage: %@ free of %@. VidGrab videos use %@.", gb2(free), capacityName(total), sizeShort(vid)];
    [self layoutBar];
}

@end
