#import "VGQualityCell.h"
#import "VGTheme.h"


@implementation VGQualityCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = VGSurface2;
        self.contentView.layer.cornerRadius = 12;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.layer.borderWidth = 2;

        _resLabel = [UILabel new];
        _resLabel.font = VGRounded(26, UIFontWeightHeavy);
        _resLabel.textColor = VGText;
        _resLabel.adjustsFontSizeToFitWidth = YES;
        _resLabel.minimumScaleFactor = 0.6;

        _badgeLabel = [UILabel new];
        _badgeLabel.font = VGFont(11, UIFontWeightBold);
        _badgeLabel.textColor = VGAccent;

        _sizeLabel = [UILabel new];
        _sizeLabel.font = VGFont(14, UIFontWeightSemibold);
        _sizeLabel.textColor = VGSecondary;

        _fmtLabel = [UILabel new];
        _fmtLabel.font = VGFont(10, UIFontWeightHeavy);
        _fmtLabel.textColor = VGTertiary;

        _check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
        _check.tintColor = VGAccent;

        for (UIView *v in @[_resLabel, _badgeLabel, _sizeLabel, _fmtLabel, _check]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        UIView *c = self.contentView;
        [NSLayoutConstraint activateConstraints:@[
            [_resLabel.topAnchor constraintEqualToAnchor:c.topAnchor constant:14],
            [_resLabel.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:14],
            [_resLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_check.leadingAnchor constant:-4],
            [_badgeLabel.topAnchor constraintEqualToAnchor:_resLabel.bottomAnchor constant:2],
            [_badgeLabel.leadingAnchor constraintEqualToAnchor:_resLabel.leadingAnchor],
            [_fmtLabel.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-14],
            [_fmtLabel.leadingAnchor constraintEqualToAnchor:_resLabel.leadingAnchor],
            [_fmtLabel.trailingAnchor constraintLessThanOrEqualToAnchor:c.trailingAnchor constant:-10],
            [_sizeLabel.bottomAnchor constraintEqualToAnchor:_fmtLabel.topAnchor constant:-3],
            [_sizeLabel.leadingAnchor constraintEqualToAnchor:_resLabel.leadingAnchor],
            [_check.topAnchor constraintEqualToAnchor:c.topAnchor constant:10],
            [_check.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-10],
            [_check.widthAnchor constraintEqualToConstant:20],
            [_check.heightAnchor constraintEqualToConstant:20],
        ]];
    }
    return self;
}

- (void)configure:(VGOption *)o selected:(BOOL)selected {
    NSArray *parts = [o.res componentsSeparatedByString:@" "];
    self.resLabel.text = parts.firstObject;
    NSString *badge = parts.count > 1 ? [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@" "].uppercaseString : nil;
    if (o.audio) badge = @"SOUND ONLY";
    else if ([parts.firstObject isEqualToString:@"4K"] || [parts.firstObject isEqualToString:@"2K"]) badge = badge ?: @"ULTRA HD";
    self.badgeLabel.text = badge;
    self.sizeLabel.text = o.sizeText.length ? o.sizeText : @"Size unknown";
    self.fmtLabel.text = o.audio ? o.format : (o.convert ? @"MP4 · CONVERTS" : (o.photos ? [o.format stringByAppendingString:@" · PHOTOS"] : [o.format stringByAppendingString:@" · FILES ONLY"]));
    self.check.hidden = !selected;
    self.contentView.layer.borderColor = selected ? VGAccent.CGColor : UIColor.clearColor.CGColor;
    self.contentView.backgroundColor = selected ? VGHex(0x26232C) : VGSurface2;
}

@end

