#import "PlayerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>

static void *PlayerItemStatusContext = &PlayerItemStatusContext;

@interface PlayerViewController ()

@property (nonatomic, strong) AVPlayerView *playerView;
@property (nonatomic, strong) NSButton *playPauseButton;
@property (nonatomic, strong) NSStackView *controlBar;
@property (nonatomic, strong) NSVisualEffectView *controlBarContainer;
@property (nonatomic, strong) NSView *topTitleOverlay;
@property (nonatomic, strong) CAGradientLayer *topScrimLayer;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSPopUpButton *sourcePopup;
@property (nonatomic, strong) NSPopUpButton *episodePopup;
@property (nonatomic, strong) NSTextField *hintLabel;
@property (nonatomic, strong) NSButton *channelPrevButton;
@property (nonatomic, strong) NSButton *channelNextButton;
@property (nonatomic, strong) NSButton *linePrevButton;
@property (nonatomic, strong) NSButton *lineNextButton;
@property (nonatomic, strong) NSButton *zoomButton;
@property (nonatomic, strong) NSButton *fullscreenButton;
@property (nonatomic, strong) NSButton *returnButton;
@property (nonatomic, strong) NSButton *exitButton;
@property (nonatomic, strong) NSView *restoreOverlay;

@property (nonatomic, assign) BOOL immersive;
@property (nonatomic, assign) BOOL savedControlBarHidden;
@property (nonatomic, assign) BOOL savedTopTitleOverlayHidden;
@property (nonatomic, assign) BOOL fullscreenActive;
@property (nonatomic, assign) BOOL windowImmersive;
@property (nonatomic, weak) NSWindow *observedWindow;

@property (nonatomic, strong) TVVideo *video;
@property (nonatomic, strong) NSArray<TVPlaySource *> *sources;
@property (nonatomic, assign) NSInteger sourceIndex;
@property (nonatomic, assign) NSInteger episodeIndex;
@property (nonatomic, strong) NSArray<TVLiveLine *> *liveLines;
@property (nonatomic, strong) NSArray<TVLiveChannel *> *liveChannels;
@property (nonatomic, assign) NSInteger liveChannelIndex;
@property (nonatomic, assign) NSInteger liveLineIndex;
@property (nonatomic, strong) id keyMonitor;

@property (nonatomic, strong) AVPlayerItem *currentItem;
@property (nonatomic, assign) NSInteger liveTriedLines;
@property (nonatomic, assign) NSTimeInterval pendingSeekTime;

@end

@implementation PlayerViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960, 620)];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.playerView = [[AVPlayerView alloc] init];
    self.playerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.playerView.controlsStyle = AVPlayerViewControlsStyleFloating;
    [self.view addSubview:self.playerView];

    // 顶部标题覆盖层：当前视频信息覆盖在视频组件上显示，带渐变蒙版保证在画面上清晰可读
    self.titleLabel = [NSTextField labelWithString:@""];
    self.titleLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.textColor = [NSColor whiteColor];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.topTitleOverlay = [[NSView alloc] init];
    self.topTitleOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.topTitleOverlay.wantsLayer = YES;
    CAGradientLayer *scrim = [CAGradientLayer layer];
    scrim.colors = @[(id)[NSColor colorWithCalibratedWhite:0.0 alpha:0.60].CGColor,
                     (id)[NSColor colorWithCalibratedWhite:0.0 alpha:0.0].CGColor];
    scrim.locations = @[@0.0, @1.0];
    scrim.startPoint = CGPointMake(0.5, 0.0);
    scrim.endPoint = CGPointMake(0.5, 1.0);
    self.topScrimLayer = scrim;
    [self.topTitleOverlay.layer addSublayer:scrim];
    [self.topTitleOverlay addSubview:self.titleLabel];
    [self.view addSubview:self.topTitleOverlay];

    self.sourcePopup = [[NSPopUpButton alloc] init];
    self.sourcePopup.font = [NSFont systemFontOfSize:12];
    [self.sourcePopup setTarget:self];
    [self.sourcePopup setAction:@selector(sourceChanged:)];

    self.episodePopup = [[NSPopUpButton alloc] init];
    self.episodePopup.font = [NSFont systemFontOfSize:12];
    [self.episodePopup setTarget:self];
    [self.episodePopup setAction:@selector(episodeChanged:)];

    self.hintLabel = [NSTextField labelWithString:@"↑↓ 切换频道　←→ 切换线路"];
    self.hintLabel.font = [NSFont systemFontOfSize:12];
    self.hintLabel.textColor = [NSColor colorWithCalibratedWhite:0.85 alpha:1.0];
    self.hintLabel.hidden = YES;

    self.channelPrevButton = [self iconButtonWithSymbol:@"chevron.up" tooltip:@"上一个频道" action:@selector(channelPrevAction:)];
    self.channelNextButton = [self iconButtonWithSymbol:@"chevron.down" tooltip:@"下一个频道" action:@selector(channelNextAction:)];
    self.linePrevButton = [self iconButtonWithSymbol:@"chevron.left" tooltip:@"上一个线路" action:@selector(linePrevAction:)];
    self.lineNextButton = [self iconButtonWithSymbol:@"chevron.right" tooltip:@"下一个线路" action:@selector(lineNextAction:)];
    self.zoomButton = [self iconButtonWithSymbol:@"eye.slash" tooltip:@"隐藏 / 恢复显示" action:@selector(toggleFullWindowAction:)];
    self.fullscreenButton = [self iconButtonWithSymbol:@"arrow.up.left.and.arrow.down.right" tooltip:@"全屏 / 返回" action:@selector(toggleFullScreenAction:)];
    self.channelPrevButton.hidden = YES;
    self.channelNextButton.hidden = YES;
    self.linePrevButton.hidden = YES;
    self.lineNextButton.hidden = YES;

    self.playPauseButton = [self iconButtonWithSymbol:@"pause.fill" tooltip:@"播放 / 暂停" action:@selector(togglePlayPauseAction:)];

    self.controlBar = [NSStackView stackViewWithViews:@[self.playPauseButton, self.channelPrevButton, self.channelNextButton, self.sourcePopup, self.linePrevButton, self.lineNextButton, self.episodePopup, self.hintLabel, self.zoomButton, self.fullscreenButton]];
    self.controlBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.controlBar.spacing = 8;
    self.controlBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.controlBar.edgeInsets = NSEdgeInsetsMake(4, 10, 4, 10);

    // 控制条采用毛玻璃材质覆盖在视频上显示，圆角 + 细边框，现代时尚
    self.controlBarContainer = [[NSVisualEffectView alloc] init];
    self.controlBarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.controlBarContainer.material = NSVisualEffectMaterialHUDWindow;
    self.controlBarContainer.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.controlBarContainer.state = NSVisualEffectStateActive;
    self.controlBarContainer.wantsLayer = YES;
    self.controlBarContainer.layer.cornerRadius = 10;
    self.controlBarContainer.layer.masksToBounds = YES;
    self.controlBarContainer.layer.borderWidth = 1.0;
    self.controlBarContainer.layer.borderColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.10].CGColor;
    [self.controlBarContainer addSubview:self.controlBar];
    [self.view addSubview:self.controlBarContainer];

    // 视频播放组件占满整个窗口
    [NSLayoutConstraint activateConstraints:@[
        [self.playerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.playerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.playerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.playerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // 顶部标题覆盖层约束：覆盖在视频顶部，标题置于左上角
    [NSLayoutConstraint activateConstraints:@[
        [self.topTitleOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.topTitleOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topTitleOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topTitleOverlay.heightAnchor constraintEqualToConstant:72],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.topTitleOverlay.leadingAnchor constant:18],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.topTitleOverlay.trailingAnchor constant:-80],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.topTitleOverlay.topAnchor constant:16],
    ]];

    // 底部控制条约束：覆盖在视频底部
    [NSLayoutConstraint activateConstraints:@[
        [self.controlBarContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.controlBarContainer.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.controlBarContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8],
        [self.controlBarContainer.heightAnchor constraintEqualToConstant:38],

        [self.controlBar.leadingAnchor constraintEqualToAnchor:self.controlBarContainer.leadingAnchor],
        [self.controlBar.trailingAnchor constraintEqualToAnchor:self.controlBarContainer.trailingAnchor],
        [self.controlBar.topAnchor constraintEqualToAnchor:self.controlBarContainer.topAnchor],
        [self.controlBar.bottomAnchor constraintEqualToAnchor:self.controlBarContainer.bottomAnchor],

        [self.sourcePopup.widthAnchor constraintGreaterThanOrEqualToConstant:200],
        [self.episodePopup.widthAnchor constraintGreaterThanOrEqualToConstant:120],
    ]];

    // 隐藏模式下显示“恢复显示”按钮与 X 按钮，二者均用于恢复显示除视频外的其他组件。
    self.returnButton = [NSButton buttonWithTitle:@"恢复显示" target:self action:@selector(exitImmersiveAction:)];
    self.returnButton.image = [NSImage imageWithSystemSymbolName:@"arrow.uturn.backward" accessibilityDescription:@"恢复显示"];
    self.returnButton.imagePosition = NSImageLeading;
    self.returnButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.returnButton.contentTintColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
    self.returnButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.exitButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"恢复显示"] target:self action:@selector(exitImmersiveAction:)];
    self.exitButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.exitButton.contentTintColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
    self.exitButton.toolTip = @"恢复显示";
    self.exitButton.translatesAutoresizingMaskIntoConstraints = NO;

    // 隐藏后显示的按钮统一放在一个半透明灰色衬底容器中，保证在视频画面上清晰可见。
    self.restoreOverlay = [[NSView alloc] init];
    self.restoreOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.restoreOverlay.wantsLayer = YES;
    self.restoreOverlay.layer.cornerRadius = 8;
    self.restoreOverlay.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.4 alpha:0.6].CGColor;
    self.restoreOverlay.layer.borderWidth = 1.0;
    self.restoreOverlay.layer.borderColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.10].CGColor;
    self.restoreOverlay.hidden = YES;
    [self.view addSubview:self.restoreOverlay];

    [self.restoreOverlay addSubview:self.returnButton];
    [self.restoreOverlay addSubview:self.exitButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.restoreOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [self.restoreOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.restoreOverlay.heightAnchor constraintEqualToConstant:36],

        [self.exitButton.trailingAnchor constraintEqualToAnchor:self.restoreOverlay.trailingAnchor constant:-8],
        [self.exitButton.centerYAnchor constraintEqualToAnchor:self.restoreOverlay.centerYAnchor],
        [self.returnButton.trailingAnchor constraintEqualToAnchor:self.exitButton.leadingAnchor constant:-8],
        [self.returnButton.centerYAnchor constraintEqualToAnchor:self.restoreOverlay.centerYAnchor],
        [self.returnButton.leadingAnchor constraintEqualToAnchor:self.restoreOverlay.leadingAnchor constant:8],
    ]];

    __weak typeof(self) weakSelf = self;
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        if ([weakSelf handleKeyEvent:event]) {
            return nil;
        }
        return event;
    }];
}

- (void)viewDidLayout {
    [super viewDidLayout];
    // 顶部渐变蒙版需要跟随覆盖层尺寸变化，保证缩放窗口后仍覆盖整个标题区域。
    self.topScrimLayer.frame = self.topTitleOverlay.bounds;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.keyMonitor) {
        [NSEvent removeMonitor:self.keyMonitor];
        self.keyMonitor = nil;
    }
    if (self.currentItem) {
        [self.currentItem removeObserver:self forKeyPath:@"status" context:PlayerItemStatusContext];
        self.currentItem = nil;
    }
}

- (void)viewWillAppear {
    [super viewWillAppear];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSWindow *window = self.view.window;
    if (!window) return;
    self.observedWindow = window;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(playerWindowWillEnterFullScreen:) name:NSWindowWillEnterFullScreenNotification object:window];
    [nc addObserver:self selector:@selector(playerWindowDidExitFullScreen:) name:NSWindowDidExitFullScreenNotification object:window];
}

- (void)playerWindowWillEnterFullScreen:(NSNotification *)note {
    self.fullscreenActive = YES;
    [self updateImmersiveContent];
}

- (void)playerWindowDidExitFullScreen:(NSNotification *)note {
    self.fullscreenActive = NO;
    [self updateImmersiveContent];
}

- (void)updateImmersiveContent {
    BOOL immersive = self.fullscreenActive || self.windowImmersive;
    if (immersive != self.immersive) {
        self.immersive = immersive;
        if (immersive) {
            // 全屏或“隐藏”模式下，只保留视频播放组件，隐藏顶部标题覆盖层与底部控制条。
            self.savedControlBarHidden = self.controlBarContainer.hidden;
            self.savedTopTitleOverlayHidden = self.topTitleOverlay.hidden;
            self.controlBarContainer.hidden = YES;
            self.topTitleOverlay.hidden = YES;
        } else {
            self.controlBarContainer.hidden = self.savedControlBarHidden;
            self.topTitleOverlay.hidden = self.savedTopTitleOverlayHidden;
        }
    }
    // 仅在“隐藏”模式下显示“恢复显示”按钮与 X 按钮所在的衬底容器；全屏时同样隐藏。
    BOOL showOverlay = self.windowImmersive && !self.fullscreenActive;
    self.restoreOverlay.hidden = !showOverlay;
}

- (BOOL)handleKeyEvent:(NSEvent *)event {
    if (!self.view.window || !self.view.window.isKeyWindow) return NO;

    // 隐藏模式下按 X 键恢复显示。
    if (self.windowImmersive) {
        NSString *chars = event.charactersIgnoringModifiers.lowercaseString;
        if ([chars isEqualToString:@"x"]) {
            [self exitImmersiveAction:nil];
            return YES;
        }
    }

    if (self.liveChannels.count == 0) return NO;

    switch (event.keyCode) {
        case 126: // 上方向键
            [self switchLiveChannelByDelta:-1];
            return YES;
        case 125: // 下方向键
            [self switchLiveChannelByDelta:1];
            return YES;
        case 123: // 左方向键
            [self switchLiveLineByDelta:-1];
            return YES;
        case 124: // 右方向键
            [self switchLiveLineByDelta:1];
            return YES;
        default:
            return NO;
    }
}

- (void)switchLiveChannelByDelta:(NSInteger)delta {
    NSInteger count = (NSInteger)self.liveChannels.count;
    if (count == 0) return;
    NSInteger index = self.liveChannelIndex + delta;
    if (index < 0) index = count - 1;
    if (index >= count) index = 0;
    self.liveChannelIndex = index;
    [self applyCurrentLiveChannel];
}

- (void)switchLiveLineByDelta:(NSInteger)delta {
    NSInteger count = (NSInteger)self.liveLines.count;
    if (count == 0) return;
    NSInteger index = self.liveLineIndex + delta;
    if (index < 0) index = count - 1;
    if (index >= count) index = 0;
    self.liveLineIndex = index;
    self.liveTriedLines = 0;
    [self.sourcePopup selectItemAtIndex:index];
    [self playCurrentLiveLine];
}

- (NSButton *)iconButtonWithSymbol:(NSString *)symbolName tooltip:(NSString *)tooltip action:(SEL)action {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:tooltip];
    NSButton *button = [NSButton buttonWithImage:image target:self action:action];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.contentTintColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
    button.toolTip = tooltip;
    return button;
}

- (void)channelPrevAction:(id)sender { [self switchLiveChannelByDelta:-1]; }
- (void)channelNextAction:(id)sender { [self switchLiveChannelByDelta:1]; }
- (void)linePrevAction:(id)sender { [self switchLiveLineByDelta:-1]; }
- (void)lineNextAction:(id)sender { [self switchLiveLineByDelta:1]; }
- (void)toggleFullWindowAction:(id)sender {
    self.windowImmersive = !self.windowImmersive;
    [self updateImmersiveContent];
}
- (void)toggleFullScreenAction:(id)sender { [self.view.window toggleFullScreen:nil]; }
- (void)exitImmersiveAction:(id)sender {
    self.windowImmersive = NO;
    [self updateImmersiveContent];
}

// 点击播放按钮来播放、暂停视频播放
- (void)togglePlayPauseAction:(id)sender {
    AVPlayer *player = self.playerView.player;
    if (!player) return;
    if (player.rate > 0) {
        [player pause];
    } else {
        [player play];
    }
    [self updatePlayPauseButton];
}

- (void)updatePlayPauseButton {
    BOOL playing = (self.playerView.player && self.playerView.player.rate > 0);
    NSString *symbol = playing ? @"pause.fill" : @"play.fill";
    self.playPauseButton.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"播放/暂停"];
    self.playPauseButton.toolTip = playing ? @"暂停" : @"播放";
}

- (void)playVideo:(TVVideo *)video {
    [self resumeVideo:video sourceIndex:0 episodeIndex:0 resumeTime:0];
}

- (void)resumeVideo:(TVVideo *)video sourceIndex:(NSInteger)sourceIndex episodeIndex:(NSInteger)episodeIndex resumeTime:(NSTimeInterval)resumeTime {
    self.video = video;
    self.sources = [video playSources];
    self.sourceIndex = 0;
    self.episodeIndex = 0;
    self.liveLines = @[];
    self.liveChannels = @[];
    self.liveChannelIndex = 0;
    self.liveLineIndex = 0;
    self.pendingSeekTime = resumeTime;
    self.titleLabel.stringValue = video.name ?: @"";
    self.episodePopup.hidden = NO;
    self.hintLabel.hidden = YES;
    self.channelPrevButton.hidden = YES;
    self.channelNextButton.hidden = YES;
    self.linePrevButton.hidden = YES;
    self.lineNextButton.hidden = YES;

    [self rebuildSourcePopup];
    [self rebuildEpisodePopup];

    if (self.sources.count == 0) {
        self.controlBarContainer.hidden = YES;
        return;
    }

    // 恢复到指定的播放源与集数
    if (sourceIndex >= 0 && sourceIndex < (NSInteger)self.sources.count) {
        self.sourceIndex = sourceIndex;
        [self.sourcePopup selectItemAtIndex:sourceIndex];
        [self rebuildEpisodePopup];
        NSArray<TVEpisode *> *episodes = self.sources[self.sourceIndex].episodes;
        if (episodeIndex >= 0 && episodeIndex < (NSInteger)episodes.count) {
            self.episodeIndex = episodeIndex;
            [self.episodePopup selectItemAtIndex:episodeIndex];
        } else {
            self.episodeIndex = 0;
            [self.episodePopup selectItemAtIndex:0];
        }
    }

    self.controlBarContainer.hidden = NO;
    [self playCurrentEpisode];
}

- (void)playLiveChannel:(TVLiveChannel *)channel {
    [self playLiveChannels:(channel ? @[channel] : @[]) atIndex:0];
}

- (void)playLiveChannels:(NSArray<TVLiveChannel *> *)channels atIndex:(NSInteger)index {
    self.video = nil;
    self.sources = @[];
    self.liveChannels = channels ?: @[];
    self.liveChannelIndex = index;
    if (self.liveChannelIndex < 0) self.liveChannelIndex = 0;
    if (self.liveChannelIndex >= (NSInteger)self.liveChannels.count) self.liveChannelIndex = (NSInteger)self.liveChannels.count - 1;
    if (self.liveChannels.count == 0) {
        self.titleLabel.stringValue = @"";
        self.controlBarContainer.hidden = YES;
        self.hintLabel.hidden = YES;
        return;
    }
    [self applyCurrentLiveChannel];
}

- (void)applyCurrentLiveChannel {
    TVLiveChannel *channel = self.liveChannels[self.liveChannelIndex];
    self.liveLines = channel.lines ?: @[];
    self.liveLineIndex = 0;
    self.liveTriedLines = 0;
    if (self.liveLines.count == 0 && channel.url.length > 0) {
        TVLiveLine *line = [[TVLiveLine alloc] init];
        line.sourceName = @"默认";
        line.name = @"默认";
        line.url = channel.url;
        self.liveLines = @[line];
    }
    self.titleLabel.stringValue = channel.name ?: @"";
    // 上下键或图标切换频道时同步更新播放窗体标题文字
    if (channel.name.length > 0) {
        self.view.window.title = channel.name;
    }
    self.episodePopup.hidden = YES;
    self.hintLabel.hidden = NO;
    self.channelPrevButton.hidden = NO;
    self.channelNextButton.hidden = NO;
    self.linePrevButton.hidden = NO;
    self.lineNextButton.hidden = NO;
    self.controlBarContainer.hidden = (self.liveLines.count == 0);

    [self rebuildLiveLinePopup];
    [self playCurrentLiveLine];
}

- (void)stop {
    [self.playerView.player pause];
    self.playerView.player = nil;
    if (self.currentItem) {
        [self.currentItem removeObserver:self forKeyPath:@"status" context:PlayerItemStatusContext];
        self.currentItem = nil;
    }
    [self updatePlayPauseButton];
}

- (NSTimeInterval)currentPlaybackTime {
    AVPlayer *player = self.playerView.player;
    if (!player) return 0;
    CMTime time = player.currentTime;
    if (CMTIME_IS_INVALID(time)) return 0;
    NSTimeInterval seconds = CMTimeGetSeconds(time);
    return (seconds > 0) ? seconds : 0;
}

// 将当前播放状态同步到历史记录：记录“该视频的所有数据”，包括集数、线路、频道与播放时间。
- (void)syncPlaybackStateToHistoryItem:(TVHistoryItem *)item {
    if (!item) return;
    item.playbackTime = [self currentPlaybackTime];

    if (item.isLive) {
        if (self.liveChannelIndex >= 0 && self.liveChannelIndex < (NSInteger)self.liveChannels.count) {
            TVLiveChannel *channel = self.liveChannels[self.liveChannelIndex];
            item.title = channel.name ?: item.title;
            item.subtitle = channel.group.length > 0 ? [NSString stringWithFormat:@"分组：%@", channel.group] : @"";
            item.posterURL = channel.logo ?: @"";
            item.sourceIndex = self.liveLineIndex;
            item.episodeIndex = self.liveLineIndex;

            NSMutableArray *lines = [NSMutableArray array];
            for (TVLiveLine *line in (channel.lines ?: @[])) {
                [lines addObject:@{@"sourceName": line.sourceName ?: @"",
                                   @"name": line.name ?: @"",
                                   @"url": line.url ?: @""}];
            }
            item.payload = @{@"name": channel.name ?: @"",
                             @"group": channel.group ?: @"",
                             @"logo": channel.logo ?: @"",
                             @"url": channel.url ?: @"",
                             @"lines": lines};
        }
        return;
    }

    // 点播：同步当前播放源与集数
    item.sourceIndex = self.sourceIndex;
    item.episodeIndex = self.episodeIndex;
    NSString *sourceName = @"";
    NSString *episodeName = @"";
    if (self.sourceIndex >= 0 && self.sourceIndex < (NSInteger)self.sources.count) {
        TVPlaySource *source = self.sources[self.sourceIndex];
        sourceName = source.name ?: @"";
        if (self.episodeIndex >= 0 && self.episodeIndex < (NSInteger)source.episodes.count) {
            episodeName = source.episodes[self.episodeIndex].name ?: @"";
            item.episodeName = episodeName;
        }
    }
    NSMutableArray *parts = [NSMutableArray array];
    if (self.video.typeName.length > 0) [parts addObject:self.video.typeName];
    if (sourceName.length > 0) [parts addObject:sourceName];
    if (episodeName.length > 0) [parts addObject:episodeName];
    item.subtitle = [parts componentsJoinedByString:@" · "];
}

- (void)rebuildSourcePopup {
    [self.sourcePopup removeAllItems];
    for (TVPlaySource *source in self.sources) {
        [self.sourcePopup addItemWithTitle:source.name];
    }
    if (self.sources.count > 0) {
        [self.sourcePopup selectItemAtIndex:0];
    }
}

- (void)rebuildEpisodePopup {
    [self.episodePopup removeAllItems];
    if (self.sourceIndex < (NSInteger)self.sources.count) {
        NSArray<TVEpisode *> *episodes = self.sources[self.sourceIndex].episodes;
        for (TVEpisode *episode in episodes) {
            [self.episodePopup addItemWithTitle:episode.name];
        }
        if (episodes.count > 0) {
            [self.episodePopup selectItemAtIndex:0];
        }
    }
}

- (void)sourceChanged:(NSPopUpButton *)sender {
    if (self.liveLines.count > 0) {
        self.liveLineIndex = sender.indexOfSelectedItem;
        self.liveTriedLines = 0;
        [self playCurrentLiveLine];
        return;
    }
    self.sourceIndex = sender.indexOfSelectedItem;
    self.episodeIndex = 0;
    [self rebuildEpisodePopup];
    [self playCurrentEpisode];
}

- (void)rebuildLiveLinePopup {
    [self.sourcePopup removeAllItems];
    for (TVLiveLine *line in self.liveLines) {
        NSString *title = line.name.length > 0 ? line.name : (line.sourceName ?: @"线路");
        [self.sourcePopup addItemWithTitle:title];
    }
    if (self.liveLineIndex >= 0 && self.liveLineIndex < (NSInteger)self.liveLines.count) {
        [self.sourcePopup selectItemAtIndex:self.liveLineIndex];
    } else if (self.liveLines.count > 0) {
        [self.sourcePopup selectItemAtIndex:0];
    }
}

- (void)playCurrentLiveLine {
    if (self.liveLineIndex < 0 || self.liveLineIndex >= (NSInteger)self.liveLines.count) return;
    if (self.sourcePopup.indexOfSelectedItem != self.liveLineIndex) {
        [self.sourcePopup selectItemAtIndex:self.liveLineIndex];
    }
    [self playURL:self.liveLines[self.liveLineIndex].url];
}

- (void)episodeChanged:(NSPopUpButton *)sender {
    self.episodeIndex = sender.indexOfSelectedItem;
    [self playCurrentEpisode];
}

- (void)playCurrentEpisode {
    if (self.sourceIndex < 0 || self.sourceIndex >= (NSInteger)self.sources.count) return;
    NSArray<TVEpisode *> *episodes = self.sources[self.sourceIndex].episodes;
    if (self.episodeIndex < 0 || self.episodeIndex >= (NSInteger)episodes.count) return;
    [self playURL:episodes[self.episodeIndex].url];
}

- (void)playURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    if (self.currentItem) {
        [self.currentItem removeObserver:self forKeyPath:@"status" context:PlayerItemStatusContext];
        self.currentItem = nil;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    self.currentItem = item;
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:PlayerItemStatusContext];

    // 复用同一个 AVPlayer，通过 replaceCurrentItemWithPlayerItem: 切换内容。
    // 每次切换频道/线路都新建 AVPlayer 并整体替换 playerView.player，会导致上一个
    // 播放器在尚未停止的状态下被释放，其音频输出可能残留，与新内容的声音同时播放。
    AVPlayer *player = self.playerView.player;
    if (!player) {
        player = [[AVPlayer alloc] init];
        self.playerView.player = player;
    }
    [player replaceCurrentItemWithPlayerItem:item];
    [player play];
    [self updatePlayPauseButton];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context == PlayerItemStatusContext) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (item.status == AVPlayerItemStatusFailed) {
                [self handlePlaybackFailure];
            } else if (item.status == AVPlayerItemStatusReadyToPlay) {
                self.liveTriedLines = 0;
                if (self.pendingSeekTime > 0) {
                    NSTimeInterval time = self.pendingSeekTime;
                    self.pendingSeekTime = 0;
                    [self.playerView.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)
                                       toleranceBefore:kCMTimeZero
                                        toleranceAfter:kCMTimeZero];
                }
            }
        });
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

// 直播视频无法正确播放时，自动切换到下一线路
- (void)handlePlaybackFailure {
    if (self.liveLines.count <= 1) return;
    // 已尝试过所有线路仍未成功，停止自动切换，避免死循环
    if (self.liveTriedLines >= (NSInteger)self.liveLines.count) return;

    self.liveTriedLines++;
    NSInteger next = self.liveLineIndex + 1;
    if (next >= (NSInteger)self.liveLines.count) next = 0;
    self.liveLineIndex = next;
    [self.sourcePopup selectItemAtIndex:next];
    [self playCurrentLiveLine];
}

@end