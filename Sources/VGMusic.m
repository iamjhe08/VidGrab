#import "VGLyrics.h"
#import "VGMusic.h"
#import "VGTheme.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

NSString *const VGMusicChangedNotification = @"VGMusicChanged";
NSString *const VGMusicPlaylistsChanged = @"VGMusicPlaylistsChanged";

#pragma mark - Playlists of songs

static NSString *const kPLKey = @"vg.musicPlaylists";

@implementation VGMusicPlaylists
+ (NSArray<NSDictionary *> *)all {
    NSArray *a = [NSUserDefaults.standardUserDefaults arrayForKey:kPLKey];
    return [a isKindOfClass:NSArray.class] ? a : @[];
}
+ (void)save:(NSArray *)a {
    [NSUserDefaults.standardUserDefaults setObject:a forKey:kPLKey];
    [NSNotificationCenter.defaultCenter postNotificationName:VGMusicPlaylistsChanged object:nil];
}
+ (NSDictionary *)withID:(NSString *)identifier {
    for (NSDictionary *d in self.all) if ([d[@"id"] isEqualToString:identifier]) return d;
    return nil;
}
+ (void)update:(NSString *)identifier block:(void (^)(NSMutableDictionary *))block {
    NSMutableArray *a = [self.all mutableCopy];
    for (NSUInteger i = 0; i < a.count; i++) {
        if (![a[i][@"id"] isEqualToString:identifier]) continue;
        NSMutableDictionary *d = [a[i] mutableCopy]; block(d); a[i] = d;
        [self save:a]; return;
    }
}
+ (NSDictionary *)create:(NSString *)name items:(NSArray<NSString *> *)fileNames {
    NSString *n = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSDictionary *d = @{@"id": NSUUID.UUID.UUIDString, @"name": n.length ? n : @"New Playlist", @"items": fileNames ?: @[]};
    [self save:[self.all arrayByAddingObject:d]];
    return d;
}
+ (void)rename:(NSString *)identifier to:(NSString *)name {
    NSString *n = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!n.length) return;
    [self update:identifier block:^(NSMutableDictionary *d) { d[@"name"] = n; }];
}
+ (void)remove:(NSString *)identifier {
    NSMutableArray *a = [self.all mutableCopy];
    for (NSDictionary *d in [a copy]) if ([d[@"id"] isEqualToString:identifier]) [a removeObject:d];
    [self save:a];
}
+ (void)add:(NSArray<NSString *> *)fileNames to:(NSString *)identifier {
    [self update:identifier block:^(NSMutableDictionary *d) {
        NSMutableArray *it = [d[@"items"] mutableCopy] ?: [NSMutableArray array];
        for (NSString *f in fileNames) if (![it containsObject:f]) [it addObject:f];
        d[@"items"] = it;
    }];
}
+ (void)removeFile:(NSString *)fileName from:(NSString *)identifier {
    [self update:identifier block:^(NSMutableDictionary *d) {
        NSMutableArray *it = [d[@"items"] mutableCopy] ?: [NSMutableArray array];
        [it removeObject:fileName]; d[@"items"] = it;
    }];
}
+ (NSArray<VGItem *> *)itemsIn:(NSString *)identifier {
    NSDictionary *p = [self withID:identifier];
    NSMutableDictionary *byName = [NSMutableDictionary dictionary];
    for (VGItem *i in [VGEngine shared].items) if (!i.vault && i.audio) byName[i.fileName] = i;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in p[@"items"]) { VGItem *i = byName[f]; if (i) [out addObject:i]; }
    return out;
}
@end
NSString *const VGMusicTickNotification = @"VGMusicTick";

static NSString *Clock(double s) {
    if (!isfinite(s) || s < 0) s = 0;
    int t = (int)round(s);
    return t >= 3600 ? [NSString stringWithFormat:@"%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60] : [NSString stringWithFormat:@"%d:%02d", t / 60, t % 60];
}

#pragma mark - Player

extern BOOL VGPlayerIsActive(void);   // a video or stream player is open: it owns the lock screen buttons

@implementation VGMusicPlayer {
    NSArray<VGItem *> *_queue;
    NSMutableArray<NSNumber *> *_order;
    NSInteger _pos;
    AVPlayer *_player;
    id _timeObs;
    BOOL _remoteSet;
    int _failures;
    BOOL _wantPlay;
}

+ (instancetype)shared {
    static VGMusicPlayer *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [VGMusicPlayer new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) { _queue = @[]; _order = [NSMutableArray array]; }
    return self;
}

- (NSArray<VGItem *> *)queue { return _queue; }
- (VGItem *)current { return (_pos >= 0 && (NSUInteger)_pos < _order.count) ? _queue[_order[(NSUInteger)_pos].unsignedIntegerValue] : nil; }
- (BOOL)playing { return _player && _player.timeControlStatus != AVPlayerTimeControlStatusPaused; }
- (double)position { double s = CMTimeGetSeconds(_player.currentTime); return isfinite(s) ? MAX(0, s) : 0; }
- (double)duration {
    double s = CMTimeGetSeconds(_player.currentItem.duration);
    if (isfinite(s) && s > 0) return s;
    return self.current.duration;
}

- (void)changed { [NSNotificationCenter.defaultCenter postNotificationName:VGMusicChangedNotification object:nil]; [self updateNowPlaying]; }

- (void)rebuildOrderKeepingCurrent:(BOOL)keep {
    NSUInteger curIdx = self.current ? _order[(NSUInteger)_pos].unsignedIntegerValue : 0;
    NSMutableArray *o = [NSMutableArray array];
    for (NSUInteger i = 0; i < _queue.count; i++) [o addObject:@(i)];
    if (_shuffle) {
        for (NSUInteger i = o.count; i > 1; i--) [o exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
        if (keep) {   // the playing song goes first
            NSUInteger at = [o indexOfObject:@(curIdx)];
            if (at != NSNotFound && at != 0) [o exchangeObjectAtIndex:0 withObjectAtIndex:at];
        }
    }
    _order = o;
    _pos = 0;
    if (keep && !_shuffle) _pos = (NSInteger)curIdx;
}

- (void)playQueue:(NSArray<VGItem *> *)items startAt:(NSUInteger)index {
    if (!items.count) return;
    _queue = [items copy];
    _failures = 0;
    NSMutableArray *o = [NSMutableArray array];
    for (NSUInteger i = 0; i < _queue.count; i++) [o addObject:@(i)];
    index = MIN(index, _queue.count - 1);
    if (_shuffle) {
        for (NSUInteger i = o.count; i > 1; i--) [o exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
        NSUInteger at = [o indexOfObject:@(index)];
        if (at != 0) [o exchangeObjectAtIndex:0 withObjectAtIndex:at];
        _pos = 0;
    } else _pos = (NSInteger)index;
    _order = o;
    [self loadCurrentAndPlay:YES];
}

- (void)setUpPlayer {
    if (_player) return;
    _player = [AVPlayer new];
    _player.automaticallyWaitsToMinimizeStalling = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    __weak typeof(self) ws = self;
    _timeObs = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, 600) queue:dispatch_get_main_queue() usingBlock:^(CMTime t) {
        [NSNotificationCenter.defaultCenter postNotificationName:VGMusicTickNotification object:nil];
        (void)ws;
    }];
}

- (void)loadCurrentAndPlay:(BOOL)play {
    VGItem *it = self.current;
    if (!it) return;
    [self setUpPlayer];
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
    AVPlayerItem *pi = [AVPlayerItem playerItemWithURL:it.fileURL];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(trackEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:pi];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(trackFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:pi];
    [_player replaceCurrentItemWithPlayerItem:pi];
    _wantPlay = play;
    if (play) [_player play];
    [self setUpRemote];
    [self changed];
    // A file that can't be opened: move on instead of sitting silent.
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        VGMusicPlayer *me = ws;
        if (me && me->_player.currentItem == pi && pi.status == AVPlayerItemStatusFailed) [me trackFailed:nil];
    });
}

- (void)trackFailed:(NSNotification *)n {
    if (++_failures > (int)_queue.count) { [self pause]; _failures = 0; return; }
    [self advanceAutomatically:YES];
}

- (void)trackEnded:(NSNotification *)n {
    _failures = 0;
    if (_repeatMode == 2) { [self seekTo:0]; [_player play]; [self changed]; return; }
    [self advanceAutomatically:YES];
}

/// `auto` is YES when a song ended on its own (the list stops at the end unless repeat is on).
- (void)advanceAutomatically:(BOOL)automatic {
    if (!_order.count) return;
    if ((NSUInteger)_pos + 1 < _order.count) _pos++;
    else if (_repeatMode == 1 || !automatic) {
        if (_shuffle && _order.count > 1) {   // a fresh shuffle for the next round
            NSInteger last = _order.lastObject.integerValue;
            [self rebuildOrderKeepingCurrent:NO];
            if (_order.firstObject.integerValue == last) [_order exchangeObjectAtIndex:0 withObjectAtIndex:1];
        }
        _pos = 0;
    } else {
        [_player pause];
        [_player seekToTime:kCMTimeZero];
        [self changed];
        return;
    }
    [self loadCurrentAndPlay:YES];
}

- (void)next { [self advanceAutomatically:NO]; }

- (void)previous {
    if (!_order.count) return;
    if (self.position > 3) { [self seekTo:0]; return; }
    if (_pos > 0) _pos--;
    else if (_repeatMode == 1 || YES) _pos = (NSInteger)_order.count - 1;
    [self loadCurrentAndPlay:YES];
}

- (void)togglePlay {
    if (!_player || !self.current) return;
    if (self.playing) { _wantPlay = NO; [_player pause]; }
    else {
        _wantPlay = YES;
        if (self.duration > 0 && self.position >= self.duration - 0.3) [self seekTo:0];
        [AVAudioSession.sharedInstance setActive:YES error:nil];
        [_player play];
    }
    [self changed];
}

- (void)pause { _wantPlay = NO; if (self.playing) { [_player pause]; [self changed]; } }

/// A call, an alarm or another app's sound stops us; when it is over, carry on if we were playing.
- (void)interrupted:(NSNotification *)n {
    NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type != AVAudioSessionInterruptionTypeEnded || !_wantPlay || !self.current) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_wantPlay || self.playing) return;
        [AVAudioSession.sharedInstance setActive:YES error:nil];
        [self->_player play];
        [self changed];
    });
}

- (void)seekTo:(double)seconds {
    [_player seekToTime:CMTimeMakeWithSeconds(MAX(0, seconds), 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL f) { [self updateNowPlaying]; }];
}

- (void)setShuffle:(BOOL)shuffle {
    if (_shuffle == shuffle) return;
    _shuffle = shuffle;
    if (_queue.count) [self rebuildOrderKeepingCurrent:YES];
    [self changed];
}
- (void)toggleShuffle { self.shuffle = !_shuffle; }
- (void)cycleRepeat { _repeatMode = (_repeatMode + 1) % 3; [self changed]; }

- (void)stop {
    _wantPlay = NO;
    [_player pause];
    [_player replaceCurrentItemWithPlayerItem:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
    _queue = @[]; [_order removeAllObjects]; _pos = 0;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nil;
    [self changed];
}

#pragma mark Lock screen

- (void)setUpRemote {
    MPRemoteCommandCenter *cc = MPRemoteCommandCenter.sharedCommandCenter;
    if (_remoteSet) { for (MPRemoteCommand *c in @[cc.playCommand, cc.pauseCommand, cc.togglePlayPauseCommand, cc.nextTrackCommand, cc.previousTrackCommand, cc.changePlaybackPositionCommand]) [c removeTarget:self]; }
    _remoteSet = YES;
    __weak typeof(self) ws = self;
    cc.playCommand.enabled = cc.pauseCommand.enabled = cc.togglePlayPauseCommand.enabled = cc.nextTrackCommand.enabled = cc.previousTrackCommand.enabled = cc.changePlaybackPositionCommand.enabled = YES;
    [cc.playCommand addTarget:self action:@selector(remotePlay)];
    [cc.pauseCommand addTarget:self action:@selector(remotePause)];
    [cc.togglePlayPauseCommand addTarget:self action:@selector(remoteToggle)];
    [cc.nextTrackCommand addTarget:self action:@selector(remoteNext)];
    [cc.previousTrackCommand addTarget:self action:@selector(remotePrev)];
    [cc.changePlaybackPositionCommand addTarget:self action:@selector(remoteSeek:)];
    (void)ws;
}
- (MPRemoteCommandHandlerStatus)remotePlay { if (VGPlayerIsActive()) return MPRemoteCommandHandlerStatusCommandFailed; if (!self.playing) [self togglePlay]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remotePause { if (VGPlayerIsActive()) return MPRemoteCommandHandlerStatusCommandFailed; [self pause]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remoteToggle { if (VGPlayerIsActive()) return MPRemoteCommandHandlerStatusCommandFailed; [self togglePlay]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remoteNext { if (VGPlayerIsActive()) return MPRemoteCommandHandlerStatusCommandFailed; [self next]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remotePrev { if (VGPlayerIsActive()) return MPRemoteCommandHandlerStatusCommandFailed; [self previous]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remoteSeek:(MPChangePlaybackPositionCommandEvent *)e { if (VGPlayerIsActive()) return MPRemoteCommandHandlerStatusCommandFailed; [self seekTo:e.positionTime]; return MPRemoteCommandHandlerStatusSuccess; }

- (void)updateNowPlaying {
    VGItem *it = self.current;
    if (!it) return;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[MPMediaItemPropertyTitle] = it.title ?: @"";
    if (it.artist.length) d[MPMediaItemPropertyArtist] = it.artist;
    if (it.album.length) d[MPMediaItemPropertyAlbumTitle] = it.album;
    d[MPMediaItemPropertyPlaybackDuration] = @(self.duration);
    d[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.position);
    d[MPNowPlayingInfoPropertyPlaybackRate] = @(self.playing ? 1.0 : 0.0);
    UIImage *art = it.thumbnailImage;
    if (art) d[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:art.size requestHandler:^UIImage *(CGSize s) { return art; }];
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = d;
}

@end

#pragma mark - The bar

@interface VGMiniMusicView ()
@property (nonatomic, strong) UIImageView *art;
@property (nonatomic, strong) UILabel *titleLabel, *subLabel, *elapsed, *remaining;
@property (nonatomic, strong) UIButton *topPlay, *topNext, *chevron, *shuffleB, *prevB, *playB, *nextB, *repeatB, *closeB;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIView *extra;
@property (nonatomic, strong) NSLayoutConstraint *heightC;
@property (nonatomic) BOOL expanded, scrubbing;
@end

@implementation VGMiniMusicView

static UIButton *IconButton(NSString *symbol, CGFloat size, SEL action, id target) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
    c.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold]];
    c.baseForegroundColor = VGText;
    b.configuration = c;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = VGSurface2;
    self.layer.cornerRadius = 16;
    self.layer.borderWidth = 1;
    self.layer.borderColor = VGStroke.CGColor;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.35; self.layer.shadowRadius = 10; self.layer.shadowOffset = CGSizeMake(0, 3);

    self.art = [UIImageView new];
    self.art.contentMode = UIViewContentModeScaleAspectFill;
    self.art.clipsToBounds = YES;
    self.art.layer.cornerRadius = 8;
    self.art.backgroundColor = VGSurface;
    self.art.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = [UILabel new]; self.titleLabel.font = VGFont(15, UIFontWeightSemibold); self.titleLabel.textColor = VGText;
    self.subLabel = [UILabel new]; self.subLabel.font = VGFont(12, UIFontWeightMedium); self.subLabel.textColor = VGSecondary;
    UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.subLabel]];
    labels.axis = UILayoutConstraintAxisVertical; labels.spacing = 2;

    self.topPlay = IconButton(@"play.fill", 20, @selector(playTapped), self);
    self.topNext = IconButton(@"forward.fill", 18, @selector(nextTapped), self);
    self.chevron = IconButton(@"chevron.up", 14, @selector(toggleExpanded), self);
    self.chevron.configuration.baseForegroundColor = VGSecondary;

    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[self.art, labels, self.topPlay, self.topNext, self.chevron]];
    top.alignment = UIStackViewAlignmentCenter; top.spacing = 10;
    top.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:top];

    // Expanded part
    self.extra = [UIView new];
    self.extra.translatesAutoresizingMaskIntoConstraints = NO;
    self.extra.hidden = YES; self.extra.alpha = 0;
    [self addSubview:self.extra];

    self.slider = [UISlider new];
    self.slider.minimumTrackTintColor = VGAccent;
    self.slider.maximumTrackTintColor = VGStroke;
    [self.slider setThumbImage:[[UIImage systemImageNamed:@"circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12]] imageWithTintColor:VGText renderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    [self.slider addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
    [self.slider addTarget:self action:@selector(scrubMoved) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    self.elapsed = [UILabel new]; self.remaining = [UILabel new];
    for (UILabel *l in @[self.elapsed, self.remaining]) { l.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium]; l.textColor = VGSecondary; }
    self.remaining.textAlignment = NSTextAlignmentRight;
    UIStackView *seekRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.elapsed, self.slider, self.remaining]];
    seekRow.spacing = 8; seekRow.alignment = UIStackViewAlignmentCenter;
    [self.elapsed.widthAnchor constraintEqualToConstant:42].active = YES;
    [self.remaining.widthAnchor constraintEqualToConstant:42].active = YES;

    self.shuffleB = IconButton(@"shuffle", 18, @selector(shuffleTapped), self);
    self.prevB = IconButton(@"backward.fill", 24, @selector(prevTapped), self);
    self.playB = IconButton(@"play.circle.fill", 44, @selector(playTapped), self);
    self.playB.configuration.baseForegroundColor = VGText;
    self.nextB = IconButton(@"forward.fill", 24, @selector(nextTapped), self);
    self.repeatB = IconButton(@"repeat", 18, @selector(repeatTapped), self);
    UIStackView *ctrl = [[UIStackView alloc] initWithArrangedSubviews:@[self.shuffleB, self.prevB, self.playB, self.nextB, self.repeatB]];
    ctrl.distribution = UIStackViewDistributionEqualSpacing; ctrl.alignment = UIStackViewAlignmentCenter;

    self.closeB = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cc = [UIButtonConfiguration plainButtonConfiguration];
    cc.title = @"Close player";
    cc.image = [UIImage systemImageNamed:@"xmark"];
    cc.imagePadding = 6;
    cc.baseForegroundColor = VGSecondary;
    cc.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *in) { NSMutableDictionary *m = [in mutableCopy]; m[NSFontAttributeName] = VGFont(12, UIFontWeightSemibold); return m; };
    self.closeB.configuration = cc;
    [self.closeB addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[seekRow, ctrl, self.closeB]];
    col.axis = UILayoutConstraintAxisVertical; col.spacing = 6;
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [self.extra addSubview:col];

    [NSLayoutConstraint activateConstraints:@[
        [self.art.widthAnchor constraintEqualToConstant:46], [self.art.heightAnchor constraintEqualToConstant:46],
        [top.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [top.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [top.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
        [self.extra.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:8],
        [self.extra.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [self.extra.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [col.topAnchor constraintEqualToAnchor:self.extra.topAnchor], [col.leadingAnchor constraintEqualToAnchor:self.extra.leadingAnchor],
        [col.trailingAnchor constraintEqualToAnchor:self.extra.trailingAnchor], [col.bottomAnchor constraintEqualToAnchor:self.extra.bottomAnchor],
    ]];
    self.heightC = [self.heightAnchor constraintEqualToConstant:66];
    self.heightC.active = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleExpanded)];
    [labels addGestureRecognizer:tap];
    [self.art addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleExpanded)]];
    self.art.userInteractionEnabled = YES;

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(refresh) name:VGMusicChangedNotification object:nil];
    [nc addObserver:self selector:@selector(tick) name:VGMusicTickNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (CGFloat)currentHeight { return self.hidden ? 0 : self.heightC.constant; }

- (void)toggleExpanded {
    if (self.onOpenPanel) { self.onOpenPanel(); return; }
    self.expanded = !self.expanded;
    if (self.expanded) self.extra.hidden = NO;
    self.heightC.constant = self.expanded ? 66 + 8 + 124 : 66;
    UIImage *img = [UIImage systemImageNamed:self.expanded ? @"chevron.down" : @"chevron.up" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold]];
    UIButtonConfiguration *c = self.chevron.configuration; c.image = img; self.chevron.configuration = c;
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.extra.alpha = self.expanded ? 1 : 0;
        if (self.onHeightChange) self.onHeightChange();
        [self.superview layoutIfNeeded];
    } completion:^(BOOL f) { if (!self.expanded) self.extra.hidden = YES; }];
}

- (void)playTapped { [VGMusicPlayer.shared togglePlay]; }
- (void)nextTapped { [VGMusicPlayer.shared next]; }
- (void)prevTapped { [VGMusicPlayer.shared previous]; }
- (void)shuffleTapped { [VGMusicPlayer.shared toggleShuffle]; }
- (void)repeatTapped { [VGMusicPlayer.shared cycleRepeat]; }
- (void)closeTapped {
    [VGMusicPlayer.shared stop];
    if (self.expanded) { self.expanded = NO; self.extra.hidden = YES; self.extra.alpha = 0; self.heightC.constant = 66; }
}

- (void)scrubBegan { self.scrubbing = YES; }
- (void)scrubMoved {
    double d = VGMusicPlayer.shared.duration;
    self.elapsed.text = Clock(self.slider.value * d);
    self.remaining.text = [@"-" stringByAppendingString:Clock(d - self.slider.value * d)];
}
- (void)scrubEnded {
    self.scrubbing = NO;
    [VGMusicPlayer.shared seekTo:self.slider.value * VGMusicPlayer.shared.duration];
}

- (void)tick {
    VGMusicPlayer *p = VGMusicPlayer.shared;
    if (self.scrubbing || !p.current) return;
    double d = p.duration, s = p.position;
    self.slider.value = d > 0 ? (float)MIN(1, s / d) : 0;
    self.elapsed.text = Clock(s);
    self.remaining.text = d > 0 ? [@"-" stringByAppendingString:Clock(MAX(0, d - s))] : @"--:--";
}

static void SetSymbol(UIButton *b, NSString *name, CGFloat size, UIColor *tint) {
    UIButtonConfiguration *c = b.configuration;
    c.image = [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold]];
    c.baseForegroundColor = tint;
    b.configuration = c;
}

- (void)refresh {
    VGMusicPlayer *p = VGMusicPlayer.shared;
    VGItem *it = p.current;
    BOOL show = it != nil && !self.suppressed;
    if (self.hidden == show) { self.hidden = !show; if (self.onHeightChange) self.onHeightChange(); }
    if (!it) return;
    self.titleLabel.text = it.title;
    self.subLabel.text = it.artist.length ? it.artist : (it.album.length ? it.album : @"Audio");
    UIImage *img = it.thumbnailImage;
    self.art.image = img ?: [UIImage systemImageNamed:@"music.note"];
    self.art.contentMode = img ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
    self.art.tintColor = VGTertiary;
    BOOL pl = p.playing;
    SetSymbol(self.topPlay, pl ? @"pause.fill" : @"play.fill", 20, VGText);
    SetSymbol(self.playB, pl ? @"pause.circle.fill" : @"play.circle.fill", 44, VGText);
    SetSymbol(self.shuffleB, @"shuffle", 18, p.shuffle ? VGAccent : VGSecondary);
    SetSymbol(self.repeatB, p.repeatMode == 2 ? @"repeat.1" : @"repeat", 18, p.repeatMode ? VGAccent : VGSecondary);
    self.prevB.enabled = self.nextB.enabled = self.topNext.enabled = p.queue.count > 0;
    [self tick];
}

@end

#pragma mark - The big player over the song list

@interface VGMusicPanel () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIView *artShadow, *lyricsBox;
@property (nonatomic, strong) UITableView *lyricsTable;
@property (nonatomic, strong) UILabel *lyricsStatus;
@property (nonatomic, strong) UIPageControl *dots;
@property (nonatomic, strong) UIButton *searchB;
@property (nonatomic, strong) UIButton *hintB;
@property (nonatomic, strong) VGLyrics *lyrics;
@property (nonatomic, strong) UIImageView *art;
@property (nonatomic, strong) UILabel *titleLabel, *subLabel, *elapsed, *remaining;
@property (nonatomic, strong) UIButton *shuffleB, *prevB, *playB, *nextB, *repeatB, *minB, *stopB;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic) BOOL scrubbing;
@end

@implementation VGMusicPanel {
    UIViewPropertyAnimator *_blur;
    UIView *_grab;
    UIStackView *_unused;
    BOOL _lyricsOn;
    NSString *_lyricsKey, *_customQuery;
    NSInteger _curLine;
    NSTimeInterval _dragAt;
    CADisplayLink *_link;
}

- (instancetype)init {
    if (!(self = [super initWithEffect:nil])) return nil;
    self.layer.cornerRadius = 28;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
    self.layer.borderWidth = 1;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    UIView *c = self.contentView;
    c.backgroundColor = UIColor.clearColor;

    _grab = [UIView new];
    _grab.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
    _grab.layer.cornerRadius = 2.5;
    [c addSubview:_grab];

    self.artShadow = [UIView new];
    self.artShadow.layer.shadowColor = UIColor.blackColor.CGColor;
    self.artShadow.layer.shadowOpacity = 0.4; self.artShadow.layer.shadowRadius = 16; self.artShadow.layer.shadowOffset = CGSizeMake(0, 8);
    self.art = [UIImageView new];
    self.art.clipsToBounds = YES;
    self.art.layer.cornerRadius = 20;
    self.art.layer.cornerCurve = kCACornerCurveContinuous;
    self.art.backgroundColor = VGSurface;
    [self.artShadow addSubview:self.art];
    [c addSubview:self.artShadow];

    self.titleLabel = [UILabel new]; self.titleLabel.font = VGFont(20, UIFontWeightBold); self.titleLabel.textColor = VGText;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.subLabel = [UILabel new]; self.subLabel.font = VGFont(15, UIFontWeightMedium); self.subLabel.textColor = VGSecondary;
    self.subLabel.textAlignment = NSTextAlignmentCenter;
    [c addSubview:self.titleLabel]; [c addSubview:self.subLabel];

    self.slider = [UISlider new];
    self.slider.minimumTrackTintColor = VGAccent;
    self.slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.22];
    [self.slider setThumbImage:[[UIImage systemImageNamed:@"circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13]] imageWithTintColor:VGText renderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    [self.slider addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
    [self.slider addTarget:self action:@selector(scrubMoved) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    self.elapsed = [UILabel new]; self.remaining = [UILabel new];
    for (UILabel *l in @[self.elapsed, self.remaining]) { l.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium]; l.textColor = VGSecondary; }
    self.remaining.textAlignment = NSTextAlignmentRight;
    [c addSubview:self.slider]; [c addSubview:self.elapsed]; [c addSubview:self.remaining];

    self.shuffleB = IconButton(@"shuffle", 19, @selector(shuffleTapped), self);
    self.prevB = IconButton(@"backward.fill", 26, @selector(prevTapped), self);
    self.playB = [UIButton buttonWithType:UIButtonTypeCustom];   // the main button: a solid disc in the app's text colour
    self.playB.backgroundColor = VGText;
    self.playB.layer.cornerRadius = 32;
    [self.playB addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    self.nextB = IconButton(@"forward.fill", 26, @selector(nextTapped), self);
    self.repeatB = IconButton(@"repeat", 19, @selector(repeatTapped), self);
    self.minB = IconButton(@"chevron.down", 18, @selector(minTapped), self);
    self.stopB = IconButton(@"xmark.circle.fill", 24, @selector(stopTapped), self);
    SetSymbol(self.stopB, @"xmark.circle.fill", 24, VGSecondary);
    SetSymbol(self.minB, @"chevron.down", 18, VGText);
    self.minB.accessibilityLabel = @"Minimize player";
    self.stopB.accessibilityLabel = @"Stop and close";
    for (UIButton *b in @[self.shuffleB, self.prevB, self.nextB, self.repeatB, self.minB, self.stopB]) {
        UIButtonConfiguration *cf = b.configuration; cf.contentInsets = NSDirectionalEdgeInsetsZero; b.configuration = cf;
    }
    for (UIView *v in @[self.shuffleB, self.prevB, self.playB, self.nextB, self.repeatB, self.minB, self.stopB]) [c addSubview:v];

    // Lyrics: swipe the cover to the left
    self.lyricsBox = [UIView new];
    self.lyricsBox.alpha = 0; self.lyricsBox.hidden = YES;
    self.lyricsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.lyricsTable.backgroundColor = UIColor.clearColor;
    self.lyricsTable.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.lyricsTable.dataSource = self; self.lyricsTable.delegate = self;
    self.lyricsTable.showsVerticalScrollIndicator = NO;
    self.lyricsTable.allowsSelection = NO;   // scrolling only: tapping a line does nothing
    self.lyricsTable.rowHeight = UITableViewAutomaticDimension; self.lyricsTable.estimatedRowHeight = 44;
    [self.lyricsBox addSubview:self.lyricsTable];
    self.lyricsStatus = [UILabel new];
    self.lyricsStatus.font = VGFont(16, UIFontWeightMedium); self.lyricsStatus.textColor = VGSecondary;
    self.lyricsStatus.textAlignment = NSTextAlignmentCenter; self.lyricsStatus.numberOfLines = 0;
    [self.lyricsBox addSubview:self.lyricsStatus];
    [c addSubview:self.lyricsBox];
    self.searchB = IconButton(@"magnifyingglass", 15, @selector(searchTapped), self);
    SetSymbol(self.searchB, @"magnifyingglass", 15, VGSecondary);
    self.searchB.accessibilityLabel = @"Search lyrics again";
    self.searchB.alpha = 0; self.searchB.hidden = YES;
    [c addSubview:self.searchB];
    self.hintB = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.hintB setImage:[[UIImage systemImageNamed:@"chevron.compact.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightBold]] imageWithTintColor:[UIColor colorWithWhite:1 alpha:0.75] renderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    [self.hintB addTarget:self action:@selector(swipedLeft) forControlEvents:UIControlEventTouchUpInside];
    self.hintB.accessibilityLabel = @"Show lyrics";
    [c addSubview:self.hintB];
    self.dots = [UIPageControl new];
    self.dots.numberOfPages = 2; self.dots.userInteractionEnabled = NO;
    self.dots.pageIndicatorTintColor = [UIColor colorWithWhite:1 alpha:0.3]; self.dots.currentPageIndicatorTintColor = VGText;
    [c addSubview:self.dots];
    self.artShadow.userInteractionEnabled = YES;
    UISwipeGestureRecognizer *sl = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedLeft)];
    sl.direction = UISwipeGestureRecognizerDirectionLeft;
    UISwipeGestureRecognizer *sl2 = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedLeft)];
    sl2.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.artShadow addGestureRecognizer:sl];
    UISwipeGestureRecognizer *sr = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedRight)];
    sr.direction = UISwipeGestureRecognizerDirectionRight;
    [self.lyricsBox addGestureRecognizer:sr];
    (void)sl2;

    // Drag the sheet down to put it away and pick another song
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
    pan.delegate = (id<UIGestureRecognizerDelegate>)self;
    [self addGestureRecognizer:pan];

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(refresh) name:VGMusicChangedNotification object:nil];
    [nc addObserver:self selector:@selector(tick) name:VGMusicTickNotification object:nil];
    [nc addObserver:self selector:@selector(applyBlur) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self refresh];
    return self;
}

/// A light frosted glass: only part of the blur is applied, so the list behind shows through as soft shapes.
- (void)applyBlur {
    if (_blur) { [_blur stopAnimation:YES]; _blur = nil; self.effect = nil; }
    UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:1 curve:UIViewAnimationCurveLinear animations:^{
        self.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    }];
    a.pausesOnCompletion = YES;
    a.fractionComplete = 0.30;
    _blur = a;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) { [self stopLink]; return; }
    if (_lyricsOn) [self startLink];
    [self applyBlur];
    [self.hintB.layer removeAllAnimations];
    CABasicAnimation *nudge = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    nudge.fromValue = @0; nudge.toValue = @5; nudge.duration = 0.8; nudge.autoreverses = YES; nudge.repeatCount = HUGE_VALF;
    nudge.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.hintB.layer addAnimation:nudge forKey:@"nudge"];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    self.contentView.frame = self.bounds;
    _grab.frame = CGRectMake(W / 2 - 19, 8, 38, 5);
    self.minB.frame = CGRectMake(10, 14, 44, 44);
    self.stopB.frame = CGRectMake(W - 54, 14, 44, 44);

    CGFloat top = 58, bottomPad = 22;
    CGFloat below = 14 + 26 + 2 + 20 + 14 + 30 + 16 + 64;    // everything under the cover
    CGFloat A = MAX(80, MIN(W - 140, H - top - bottomPad - below));
    CGFloat total = A + below;
    CGFloat y = top + MAX(0, (H - top - bottomPad - total) / 2);
    CGRect artR = CGRectMake((W - A) / 2, y, A, A);   // set by centre and size, so a slide-in transform doesn't upset it
    self.artShadow.bounds = CGRectMake(0, 0, A, A); self.artShadow.center = CGPointMake(CGRectGetMidX(artR), CGRectGetMidY(artR));
    self.art.frame = self.artShadow.bounds;
    self.lyricsBox.bounds = CGRectMake(0, 0, W - 40, A); self.lyricsBox.center = CGPointMake(W / 2, CGRectGetMidY(artR));
    self.lyricsTable.frame = self.lyricsBox.bounds;
    CGFloat inset = A / 2 - 20;
    self.lyricsTable.contentInset = UIEdgeInsetsMake(inset, 0, inset, 0);
    self.lyricsStatus.frame = CGRectInset(self.lyricsBox.bounds, 16, 0);
    self.searchB.frame = CGRectMake(W - 54 - 44, 14, 44, 44);
    self.hintB.frame = CGRectMake(CGRectGetMaxX(artR) + 2, CGRectGetMidY(artR) - 22, 36, 44);
    self.dots.frame = CGRectMake((W - 60) / 2, artR.origin.y + A - 4, 60, 18);
    y += A + 14;
    self.titleLabel.frame = CGRectMake(24, y, W - 48, 26); y += 28;
    self.subLabel.frame = CGRectMake(24, y, W - 48, 20); y += 34;
    self.elapsed.frame = CGRectMake(24, y, 44, 30);
    self.remaining.frame = CGRectMake(W - 68, y, 44, 30);
    self.slider.frame = CGRectMake(72, y, W - 144, 30); y += 46;
    // the five controls share the width evenly and sit on one line through the middle of the play disc
    CGFloat cy = y + 32, usable = W - 48, slot = usable / 5;
    NSArray<UIView *> *row = @[self.shuffleB, self.prevB, self.playB, self.nextB, self.repeatB];
    for (NSUInteger i = 0; i < row.count; i++) {
        CGFloat w = row[i] == self.playB ? 64 : 46;
        row[i].frame = CGRectMake(24 + slot * (i + 0.5) - w / 2, cy - w / 2, w, w);
    }
}

- (void)dealloc { [_blur stopAnimation:YES]; [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)minTapped { if (self.onMinimize) self.onMinimize(); }

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)g {
    CGPoint v = [g velocityInView:self];
    if (_lyricsOn && CGRectContainsPoint(self.lyricsBox.frame, [g locationInView:self.contentView])) return NO;   // scrolling the words
    return fabs(v.y) > fabs(v.x) && v.y > -50;   // only a downward drag, never the seek bar
}

- (void)dragged:(UIPanGestureRecognizer *)g {
    CGFloat dy = MAX(0, [g translationInView:self.superview].y);
    if (g.state == UIGestureRecognizerStateChanged) {
        self.transform = CGAffineTransformMakeTranslation(0, dy);
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGFloat vy = [g velocityInView:self.superview].y;
        if (g.state == UIGestureRecognizerStateEnded && (dy > self.bounds.size.height * 0.25 || vy > 900)) {
            if (self.onMinimize) self.onMinimize();
        } else {
            [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{ self.transform = CGAffineTransformIdentity; } completion:nil];
        }
    }
}
- (void)stopTapped { [VGMusicPlayer.shared stop]; }
- (void)playTapped { [VGMusicPlayer.shared togglePlay]; }
- (void)nextTapped { [VGMusicPlayer.shared next]; }
- (void)prevTapped { [VGMusicPlayer.shared previous]; }
- (void)shuffleTapped { [VGMusicPlayer.shared toggleShuffle]; }
- (void)repeatTapped { [VGMusicPlayer.shared cycleRepeat]; }
- (void)scrubBegan { self.scrubbing = YES; }
- (void)scrubMoved {
    double d = VGMusicPlayer.shared.duration;
    self.elapsed.text = Clock(self.slider.value * d);
    self.remaining.text = [@"-" stringByAppendingString:Clock(d - self.slider.value * d)];
}
- (void)scrubEnded {
    self.scrubbing = NO;
    [VGMusicPlayer.shared seekTo:self.slider.value * VGMusicPlayer.shared.duration];
}

- (void)tick {
    VGMusicPlayer *p = VGMusicPlayer.shared;
    if (self.scrubbing || !p.current) return;
    double d = p.duration, s = p.position;
    self.slider.value = d > 0 ? (float)MIN(1, s / d) : 0;
    self.elapsed.text = Clock(s);
    self.remaining.text = d > 0 ? [@"-" stringByAppendingString:Clock(MAX(0, d - s))] : @"--:--";
    if (_lyricsOn && self.lyrics.synced) {
        NSInteger i = [self.lyrics lineAt:s];
        if (i != _curLine) { _curLine = i; [self styleVisibleLines]; [self followLine:YES]; }
    }
}

#pragma mark Lyrics

/// Runs once per screen refresh while the words are showing, so unsynced lyrics glide instead of jumping.
- (void)startLink {
    if (_link) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(glide:)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)stopLink { [_link invalidate]; _link = nil; }

- (void)glide:(CADisplayLink *)l {
    if (!_lyricsOn || !self.window) { [self stopLink]; return; }
    VGMusicPlayer *p = VGMusicPlayer.shared;
    UITableView *t = self.lyricsTable;
    if (self.lyrics.synced || self.lyrics.lines.count < 2 || p.duration <= 0) return;
    if (t.isDragging || t.isDecelerating) return;
    CGFloat minY = -t.contentInset.top, maxY = MAX(minY, t.contentSize.height - t.bounds.size.height + t.contentInset.bottom);
    CGFloat want = minY + (maxY - minY) * (CGFloat)MIN(1, MAX(0, (p.position - self.lyrics.offset) / p.duration));
    CGFloat cur = t.contentOffset.y, diff = want - cur;
    CGFloat next = fabs(diff) > 120 ? want : cur + diff * 0.2;   // ease toward the target a little each frame
    if (fabs(next - cur) > 0.05) [t setContentOffset:CGPointMake(0, next) animated:NO];
}

- (void)swipedLeft { [self showLyrics:YES]; }
- (void)swipedRight { [self showLyrics:NO]; }

- (void)showLyrics:(BOOL)on {
    if (on == _lyricsOn) return;
    _lyricsOn = on;
    if (on) [self startLink]; else [self stopLink];
    if (on) { self.lyricsBox.hidden = NO; self.searchB.hidden = NO; self.lyricsBox.transform = CGAffineTransformMakeTranslation(40, 0); [self ensureLyrics]; }
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.artShadow.alpha = on ? 0 : 1;
        self.artShadow.transform = on ? CGAffineTransformMakeTranslation(-40, 0) : CGAffineTransformIdentity;
        self.lyricsBox.alpha = on ? 1 : 0;
        self.lyricsBox.transform = on ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(40, 0);
        self.searchB.alpha = on ? 1 : 0;
        self.dots.currentPage = on ? 1 : 0;
        self.hintB.alpha = on ? 0 : 1;
    } completion:^(BOOL f) {
        // whatever happened during the slide, end exactly in place (cover in the middle)
        BOOL on2 = self->_lyricsOn;
        self.artShadow.transform = on2 ? CGAffineTransformMakeTranslation(-40, 0) : CGAffineTransformIdentity;
        self.artShadow.alpha = on2 ? 0 : 1;
        self.lyricsBox.transform = on2 ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(40, 0);
        self.lyricsBox.alpha = on2 ? 1 : 0;
        self.hintB.alpha = on2 ? 0 : 1;
        if (!on2) { self.lyricsBox.hidden = YES; self.searchB.hidden = YES; }
        [self setNeedsLayout];
    }];
}

- (void)ensureLyrics {
    VGItem *it = VGMusicPlayer.shared.current;
    if (!it) return;
    NSString *key = it.fileName ?: it.title;
    if ([key isEqualToString:_lyricsKey]) return;
    _lyricsKey = key; _customQuery = nil; _curLine = -1;
    self.lyrics = [VGLyrics cachedFor:it];
    [self lyricsChanged];
    if (self.lyrics) return;
    [self fetchLyrics:nil];
}

- (void)fetchLyrics:(NSString *)query {
    VGItem *it = VGMusicPlayer.shared.current;
    if (!it) return;
    NSString *key = _lyricsKey;
    self.lyrics = nil; [self lyricsChanged];
    self.lyricsStatus.text = @"Loading lyrics…"; self.lyricsStatus.hidden = NO;
    [VGLyrics loadFor:it query:query completion:^(VGLyrics *l) {
        if (![key isEqualToString:self->_lyricsKey]) return;
        self.lyrics = l; self->_curLine = -1;
        [self lyricsChanged];
    }];
}

- (void)lyricsChanged {
    [self.lyricsTable reloadData];
    BOOL has = self.lyrics.lines.count > 0;
    self.lyricsStatus.hidden = has;
    if (!has) self.lyricsStatus.text = _lyricsKey ? @"No lyrics found.\nTap the magnifier to search again." : @"";
    self.lyricsTable.contentOffset = CGPointMake(0, -self.lyricsTable.contentInset.top);
    [self tick];
}

- (void)styleVisibleLines {
    for (UITableViewCell *cell in self.lyricsTable.visibleCells) {
        NSIndexPath *ip = [self.lyricsTable indexPathForCell:cell];
        if (ip) [self styleLabel:(UILabel *)[cell.contentView viewWithTag:7] row:ip.row];
    }
}

- (void)styleLabel:(UILabel *)l row:(NSInteger)row {
    BOOL syn = self.lyrics.synced;
    l.alpha = !syn ? 0.95 : (row == _curLine ? 1 : (row < _curLine ? 0.28 : 0.45));
}

- (void)followLine:(BOOL)animated {
    if (_curLine < 0 || _curLine >= (NSInteger)self.lyrics.lines.count) return;
    if (self.lyricsTable.isDragging || self.lyricsTable.isDecelerating) return;
    [self.lyricsTable scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:_curLine inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:animated];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)sv willDecelerate:(BOOL)d { if (!d) [self applyManualTiming]; }
- (void)scrollViewDidEndDecelerating:(UIScrollView *)sv { [self applyManualTiming]; }

/// Where the reader leaves the words is the new timing for this song; the auto scroll carries on from there.
- (void)applyManualTiming {
    VGItem *it = VGMusicPlayer.shared.current;
    UITableView *t = self.lyricsTable;
    double pos = VGMusicPlayer.shared.position, dur = VGMusicPlayer.shared.duration;
    if (!it || !self.lyrics.lines.count) return;
    if (self.lyrics.synced) {
        NSIndexPath *ip = [t indexPathForRowAtPoint:CGPointMake(t.bounds.size.width / 2, t.contentOffset.y + t.bounds.size.height / 2)];
        if (!ip) return;
        self.lyrics.offset = pos - [self.lyrics.times[ip.row] doubleValue];
    } else if (dur > 0) {
        CGFloat minY = -t.contentInset.top, maxY = MAX(minY + 1, t.contentSize.height - t.bounds.size.height + t.contentInset.bottom);
        double frac = MIN(1, MAX(0, (t.contentOffset.y - minY) / (maxY - minY)));
        self.lyrics.offset = pos - frac * dur;
    } else return;
    [self.lyrics saveFor:it];
    _curLine = -2;
    [self tick];
}


- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.lyrics.lines.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"l"];
    UILabel *l;
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"l"];
        cell.backgroundColor = UIColor.clearColor; cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.userInteractionEnabled = NO;
        l = [UILabel new]; l.tag = 7; l.numberOfLines = 0; l.textAlignment = NSTextAlignmentCenter;
        l.font = VGFont(22, UIFontWeightBold); l.textColor = VGText;
        l.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:l];
        [NSLayoutConstraint activateConstraints:@[
            [l.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:8],
            [l.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-8],
            [l.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:7],
            [l.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-7]]];
    }
    l = (UILabel *)[cell.contentView viewWithTag:7];
    NSString *t = self.lyrics.lines[ip.row];
    l.text = t.length ? t : @"♪";
    [self styleLabel:l row:ip.row];
    return cell;
}

- (void)searchTapped {
    VGItem *it = VGMusicPlayer.shared.current;
    if (!it) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Search lyrics" message:@"Type the artist and the song name." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = self->_customQuery ?: [VGLyrics guessFor:it]; tf.clearButtonMode = UITextFieldViewModeWhileEditing; tf.autocapitalizationType = UITextAutocapitalizationTypeWords; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Search" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *q = a.textFields.firstObject.text;
        self->_customQuery = q;
        [self fetchLyrics:q];
    }]];
    UIViewController *top = self.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:a animated:YES completion:nil];
}

- (void)refresh {
    VGMusicPlayer *p = VGMusicPlayer.shared;
    VGItem *it = p.current;
    if (!it) return;
    self.titleLabel.text = it.title;
    self.subLabel.text = it.artist.length ? it.artist : (it.album.length ? it.album : @"Audio");
    UIImage *img = it.thumbnailImage;
    if (img) { self.art.image = img; self.art.contentMode = UIViewContentModeScaleAspectFill; }
    else {
        self.art.image = [UIImage systemImageNamed:@"music.note" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:80 weight:UIImageSymbolWeightLight]];
        self.art.contentMode = UIViewContentModeCenter;
    }
    self.art.tintColor = VGTertiary;
    BOOL pl = p.playing;
    [self.playB setImage:[[UIImage systemImageNamed:pl ? @"pause.fill" : @"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightBold]] imageWithTintColor:VGBackground renderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    SetSymbol(self.shuffleB, @"shuffle", 19, p.shuffle ? VGAccent : VGSecondary);
    SetSymbol(self.repeatB, p.repeatMode == 2 ? @"repeat.1" : @"repeat", 19, p.repeatMode ? VGAccent : VGSecondary);
    self.prevB.enabled = self.nextB.enabled = p.queue.count > 0;
    if (_lyricsOn) [self ensureLyrics];
    [self tick];
}

@end
