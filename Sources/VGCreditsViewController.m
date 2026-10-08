#import "VGCreditsViewController.h"
#import "VGTheme.h"

@implementation VGCreditsViewController {
    NSArray<NSDictionary *> *_groups;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

static NSDictionary *c(NSString *name, NSString *what, NSString *license, NSString *url) {
    return @{@"name": name, @"what": what, @"license": license, @"url": url};
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Credits";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.backgroundColor = VGBackground;
    self.tableView.separatorColor = VGStroke;
    _groups = @[
        @{@"title": @"Downloading", @"items": @[
            c(@"yt-dlp", @"The engine that finds and downloads videos from all these sites. VidGrab wouldn't exist without it.", @"Unlicense (public domain)", @"https://github.com/yt-dlp/yt-dlp"),
            c(@"Python for iOS (BeeWare)", @"Lets yt-dlp run on iPhone.", @"PSF License", @"https://github.com/beeware/Python-Apple-support"),
            c(@"certifi, requests, urllib3, idna, charset-normalizer, websockets", @"Python packages that yt-dlp relies on.", @"Their own open source licenses", @"https://pypi.org"),
        ]},
        @{@"title": @"Video and sound", @"items": @[
            c(@"FFmpeg", @"Joins video and sound and converts files.", @"LGPL 2.1 or later", @"https://ffmpeg.org"),
            c(@"LAME", @"Makes MP3 files.", @"LGPL", @"https://lame.sourceforge.io"),
        ]},
        @{@"title": @"Auto subtitles", @"items": @[
            c(@"whisper.cpp", @"Runs speech recognition on your iPhone to write the subtitles. By Georgi Gerganov and the ggml authors.", @"MIT", @"https://github.com/ggerganov/whisper.cpp"),
            c(@"OpenAI Whisper", @"The speech recognition models behind the subtitles, converted for whisper.cpp.", @"MIT", @"https://github.com/openai/whisper"),
            c(@"Hugging Face", @"Hosts the model files that download when you turn on auto subtitles.", @"Model files: MIT", @"https://huggingface.co/ggerganov/whisper.cpp"),
        ]},
        @{@"title": @"Browser and extras", @"items": @[
            c(@"uBlock Origin Lite", @"The filter lists behind the ad blocker.", @"GPLv3", @"https://github.com/uBlockOrigin/uBOL-home"),
            c(@"Peter Lowe's ad server list", @"More filter lists for the ad blocker.", @"Free for non-commercial use", @"https://pgl.yoyo.org/adservers/"),
            c(@"TrollSpeed (Lessica)", @"The way the floating progress bubble draws over other apps on jailbroken phones.", @"MIT", @"https://github.com/Lessica/TrollSpeed"),
        ]},
    ];
    UILabel *foot = [UILabel new];
    foot.text = @"Thank you to everyone who builds and shares these projects. VidGrab is free and open source (GPL v3).";
    foot.font = VGFont(12, UIFontWeightMedium);
    foot.textColor = VGTertiary;
    foot.numberOfLines = 0;
    foot.textAlignment = NSTextAlignmentCenter;
    UIView *fv = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 70)];
    foot.frame = CGRectMake(24, 14, UIScreen.mainScreen.bounds.size.width - 48, 44);
    foot.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [fv addSubview:foot];
    self.tableView.tableFooterView = fv;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)_groups.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)[_groups[s][@"items"] count]; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return _groups[s][@"title"]; }

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)s {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) ((UITableViewHeaderFooterView *)view).textLabel.textColor = VGTertiary;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    NSDictionary *d = _groups[ip.section][@"items"][ip.row];
    cell.backgroundColor = VGSurface;
    cell.selectedBackgroundView = ({ UIView *v = [UIView new]; v.backgroundColor = VGSurface2; v; });
    cell.accessoryType = UITableViewCellAccessoryNone;
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];
    UILabel *name = [UILabel new], *what = [UILabel new], *lic = [UILabel new];
    name.font = VGFont(16, UIFontWeightBold);
    name.textColor = VGText;
    name.numberOfLines = 0;
    name.text = d[@"name"];
    what.font = VGFont(13, UIFontWeightMedium);
    what.textColor = VGSecondary;
    what.numberOfLines = 0;
    what.text = d[@"what"];
    lic.font = VGFont(12, UIFontWeightSemibold);
    lic.textColor = VGAccent;
    lic.text = [NSString stringWithFormat:@"%@ · tap to open", d[@"license"]];
    lic.numberOfLines = 0;
    UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:@[name, what, lic]];
    st.axis = UILayoutConstraintAxisVertical;
    st.spacing = 3;
    st.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:st];
    [NSLayoutConstraint activateConstraints:@[
        [st.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:11],
        [st.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-11],
        [st.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [st.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
    ]];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tv estimatedHeightForRowAtIndexPath:(NSIndexPath *)ip { return 90; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return UITableViewAutomaticDimension; }

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSURL *u = [NSURL URLWithString:_groups[ip.section][@"items"][ip.row][@"url"]];
    if (u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
}

@end
