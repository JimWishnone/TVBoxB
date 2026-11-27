#import "PlayerViewController+Private.h"
#import "ConfigManager.h"

void *PlayerItemStatusContext = &PlayerItemStatusContext;
void *PlayerBufferContext = &PlayerBufferContext;

static NSString * const kTVBoxUseVLCKey = @"TVBoxUseVLCPlayback";


@implementation PlayerViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960, 620)];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.useVLC = [defaults boolForKey:kTVBoxUseVLCKey] && [TVBoxVLCPlayerView vlcAvailable];

    if (self.useVLC) {
        self.vlcPlayerView = [[TVBoxVLCPlayerView alloc] init];
        self.vlcPlayerView.translatesAutoresizingMaskIntoConstraints = NO;
        self.activeVideoView = self.vlcPlayerView;

        __weak typeof(self) weakSelf = self;
        self.vlcPlayerView.onPlaybackError = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (strongSelf.liveChannels.count > 0) {
                [strongSelf handlePlaybackFailure];
            } else {
                [strongSelf showNetworkErrorAlert];
            }
        };
        self.vlcPlayerView.onPlaybackEnded = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf handleVLCDidPlayToEnd];
        };
        self.vlcPlayerView.onPlaybackStateChanged = ^(BOOL paused) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf updatePlayPauseButton];
        };
    } else {
        self.playerView = [[AVPlayerView alloc] init];
        self.playerView.translatesAutoresizingMaskIntoConstraints = NO;
        self.playerView.controlsStyle = AVPlayerViewControlsStyleFloating;
        self.activeVideoView = self.playerView;
    }
    [self.view addSubview:self.activeVideoView];

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

    // 仅点播且非全屏时显示，点击弹出模态窗口设置跳过片头/片尾时间
    self.skipButton = [NSButton buttonWithTitle:@"设置跳过片头片尾" target:self action:@selector(showSkipIntroOutroAction:)];
    self.skipButton.image = [self whiteSymbolImage:@"scissors" description:@"设置跳过片头片尾"];
    self.skipButton.imagePosition = NSImageLeading;
    self.skipButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.skipButton.font = [NSFont systemFontOfSize:12];
    // 按钮文字与图标统一使用白色，在暗色玻璃控制条上清晰可见
    NSColor *skipButtonColor = [NSColor whiteColor];
    self.skipButton.contentTintColor = skipButtonColor;
    self.skipButton.attributedTitle = [[NSMutableAttributedString alloc] initWithString:@"设置跳过片头片尾" attributes:@{
        NSForegroundColorAttributeName: skipButtonColor,
        NSFontAttributeName: [NSFont systemFontOfSize:12],
    }];
    self.skipButton.hidden = YES;

    self.controlBar = [NSStackView stackViewWithViews:@[self.playPauseButton, self.skipButton, self.channelPrevButton, self.channelNextButton, self.sourcePopup, self.linePrevButton, self.lineNextButton, self.episodePopup, self.hintLabel, self.zoomButton, self.fullscreenButton]];
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
        [self.activeVideoView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.activeVideoView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.activeVideoView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.activeVideoView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
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

        [self.sourcePopup.widthAnchor constraintLessThanOrEqualToConstant:200],
        [self.episodePopup.widthAnchor constraintLessThanOrEqualToConstant:120],
    ]];

    // 隐藏模式下显示“恢复显示”按钮与 X 按钮，二者均用于恢复显示除视频外的其他组件。
    self.returnButton = [NSButton buttonWithTitle:@"恢复显示" target:self action:@selector(exitImmersiveAction:)];
    self.returnButton.image = [self whiteSymbolImage:@"arrow.uturn.backward" description:@"恢复显示"];
    self.returnButton.imagePosition = NSImageLeading;
    self.returnButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.returnButton.contentTintColor = [NSColor whiteColor];
    self.returnButton.attributedTitle = [[NSAttributedString alloc] initWithString:@"恢复显示" attributes:@{
        NSForegroundColorAttributeName: [NSColor whiteColor],
    }];
    self.returnButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.exitButton = [NSButton buttonWithImage:[self whiteSymbolImage:@"xmark" description:@"恢复显示"] target:self action:@selector(exitImmersiveAction:)];
    self.exitButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.exitButton.contentTintColor = [NSColor whiteColor];
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

    // 网络加载缓存时的等待提示：居中显示于视频画面上，加载完成后自动隐藏
    self.loadingIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.loadingIndicator.style = NSProgressIndicatorStyleSpinning;
    self.loadingIndicator.controlSize = NSControlSizeRegular;
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *loadingLabel = [NSTextField labelWithString:@"正在加载，请稍候…"];
    loadingLabel.font = [NSFont systemFontOfSize:13];
    loadingLabel.textColor = [NSColor whiteColor];
    loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.loadingContainer = [[NSView alloc] init];
    self.loadingContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingContainer.wantsLayer = YES;
    self.loadingContainer.layer.cornerRadius = 10;
    self.loadingContainer.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.55].CGColor;
    self.loadingContainer.layer.borderWidth = 1.0;
    self.loadingContainer.layer.borderColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.12].CGColor;
    [self.loadingContainer addSubview:self.loadingIndicator];
    [self.loadingContainer addSubview:loadingLabel];
    [self.view addSubview:self.loadingContainer];

    [NSLayoutConstraint activateConstraints:@[
        [self.loadingContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.loadingContainer.heightAnchor constraintEqualToConstant:48],

        [self.loadingIndicator.leadingAnchor constraintEqualToAnchor:self.loadingContainer.leadingAnchor constant:14],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.loadingContainer.centerYAnchor],
        [self.loadingIndicator.widthAnchor constraintEqualToConstant:20],
        [self.loadingIndicator.heightAnchor constraintEqualToConstant:20],

        [loadingLabel.leadingAnchor constraintEqualToAnchor:self.loadingIndicator.trailingAnchor constant:8],
        [loadingLabel.trailingAnchor constraintEqualToAnchor:self.loadingContainer.trailingAnchor constant:-16],
        [loadingLabel.centerYAnchor constraintEqualToAnchor:self.loadingContainer.centerYAnchor],
    ]];

    [self setLoadingVisible:NO];

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

- (void)_cleanupAVPlayerItem {
    if (self.currentItem) {
        [self.currentItem removeObserver:self forKeyPath:@"status" context:PlayerItemStatusContext];
        [self.currentItem removeObserver:self forKeyPath:@"playbackBufferEmpty" context:PlayerBufferContext];
        [self.currentItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:PlayerBufferContext];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.currentItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:self.currentItem];
        self.currentItem = nil;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.stallRecoveryTimer invalidate];
    self.stallRecoveryTimer = nil;
    [self.vlcTickTimer invalidate];
    self.vlcTickTimer = nil;
    if (self.keyMonitor) {
        [NSEvent removeMonitor:self.keyMonitor];
        self.keyMonitor = nil;
    }
    if (self.playbackTimeObserver) {
        [self.playerView.player removeTimeObserver:self.playbackTimeObserver];
        self.playbackTimeObserver = nil;
    }
    [self _cleanupAVPlayerItem];
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

    // 全屏 / 返回、隐藏 / 恢复显示时，同步“设置跳过片头片尾”按钮的可见性
    [self updateSkipButtonVisibility];
}

- (BOOL)handleKeyEvent:(NSEvent *)event {
    if (!self.view.window || !self.view.window.isKeyWindow) return NO;

    if ((event.modifierFlags & NSEventModifierFlagCommand) && event.keyCode == 13) {
        [self closePlayerWindow];
        return YES;
    }

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

// 缓存已染白的 SF Symbol 图标，避免播放/暂停切换等频繁调用时重复渲染
static NSCache<NSString *, NSImage *> *TVBoxWhiteSymbolCache(void) {
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
    });
    return cache;
}

// 将 SF Symbol 模板图标渲染为纯白色，保证在任意按钮样式下图标都为白色
- (NSImage *)whiteSymbolImage:(NSString *)symbolName description:(NSString *)description {
    NSCache<NSString *, NSImage *> *cache = TVBoxWhiteSymbolCache();
    NSImage *cached = [cache objectForKey:symbolName];
    if (cached) return cached;

    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:description];
    if (!image) return nil;
    NSImage *tinted = [[NSImage alloc] initWithSize:image.size];
    [tinted lockFocus];
    [[NSColor whiteColor] set];
    [image drawInRect:NSMakeRect(0, 0, image.size.width, image.size.height)
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:YES
                hints:nil];
    [tinted unlockFocus];
    [cache setObject:tinted forKey:symbolName];
    return tinted;
}

- (NSButton *)iconButtonWithSymbol:(NSString *)symbolName tooltip:(NSString *)tooltip action:(SEL)action {
    NSImage *image = [self whiteSymbolImage:symbolName description:tooltip];
    NSButton *button = [NSButton buttonWithImage:image target:self action:action];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.contentTintColor = [NSColor whiteColor];
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

- (void)closePlayerWindow {
    NSWindow *window = self.view.window;
    if (!window) return;
    if (self.fullscreenActive) {
        [window toggleFullScreen:nil];
    }
    [window close];
}

- (void)togglePlayPauseAction:(id)sender {
    if (self.useVLC) {
        if (self.vlcPlayerView.paused) {
            [self.vlcPlayerView play];
        } else {
            [self.vlcPlayerView pause];
        }
    } else {
        AVPlayer *player = self.playerView.player;
        if (!player) return;
        if (player.rate > 0) {
            [player pause];
        } else {
            [player play];
        }
    }
    [self updatePlayPauseButton];
}

- (void)updatePlayPauseButton {
    BOOL playing = NO;
    if (self.useVLC) {
        playing = !self.vlcPlayerView.paused;
    } else {
        playing = (self.playerView.player && self.playerView.player.rate > 0);
    }
    NSString *symbol = playing ? @"pause.fill" : @"play.fill";
    self.playPauseButton.image = [self whiteSymbolImage:symbol description:@"播放/暂停"];
    self.playPauseButton.toolTip = playing ? @"暂停" : @"播放";
}

- (void)playVideo:(TVVideo *)video {
    [self resumeVideo:video sourceIndex:0 episodeIndex:0 resumeTime:0];
}

- (void)resumeVideo:(TVVideo *)video sourceIndex:(NSInteger)sourceIndex episodeIndex:(NSInteger)episodeIndex resumeTime:(NSTimeInterval)resumeTime {
    self.video = video;
    [self loadSkipSettingsForCurrentVideo];
    self.sources = [video playSources];
    self.sourceIndex = 0;
    self.episodeIndex = 0;
    self.liveLines = @[];
    self.liveChannels = @[];
    self.liveChannelIndex = 0;
    self.liveLineIndex = 0;
    self.pendingSeekTime = 0;
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

    // 续播优先于“跳过片头”：全新播放按片头设置跳转，续播按历史记录时间跳转
    if (resumeTime > 0) {
        self.pendingSeekTime = resumeTime;
    }
    [self updateSkipButtonVisibility];
}

- (void)playLiveChannel:(TVLiveChannel *)channel {
    [self playLiveChannels:(channel ? @[channel] : @[]) atIndex:0];
}

- (void)playLiveChannels:(NSArray<TVLiveChannel *> *)channels atIndex:(NSInteger)index {
    self.video = nil;
    self.sources = @[];
    [self updateSkipButtonVisibility];
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
    [self.vlcTickTimer invalidate];
    self.vlcTickTimer = nil;

    if (self.useVLC) {
        [self.vlcPlayerView stop];
    } else {
        AVPlayer *player = self.playerView.player;
        if (player && self.playbackTimeObserver) {
            [player removeTimeObserver:self.playbackTimeObserver];
            self.playbackTimeObserver = nil;
        }
        [player pause];
        self.playerView.player = nil;
        [self.stallRecoveryTimer invalidate];
        self.stallRecoveryTimer = nil;
        [self _cleanupAVPlayerItem];
    }
    [self setLoadingVisible:NO];
    [self updatePlayPauseButton];
}

- (NSTimeInterval)currentPlaybackTime {
    if (self.useVLC) {
        return [self.vlcPlayerView currentTime];
    }
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

@end
