#import "PlayerViewController.h"
#import "TVBoxVLCPlayerView.h"
#import "ConfigManager.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>

static void *PlayerItemStatusContext = &PlayerItemStatusContext;
static void *PlayerBufferContext = &PlayerBufferContext;

static NSString * const kTVBoxUseVLCKey = @"TVBoxUseVLCPlayback";

@interface PlayerViewController ()

@property (nonatomic, assign) BOOL useVLC;
@property (nonatomic, strong) AVPlayerView *playerView;
@property (nonatomic, strong) TVBoxVLCPlayerView *vlcPlayerView;
@property (nonatomic, strong) NSView *activeVideoView;
@property (nonatomic, strong) NSButton *playPauseButton;
@property (nonatomic, strong) NSButton *skipButton;
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
@property (nonatomic, strong) NSView *loadingContainer;
@property (nonatomic, strong) NSProgressIndicator *loadingIndicator;

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
@property (nonatomic, strong) NSTimer *stallRecoveryTimer;
@property (nonatomic, strong) id playbackTimeObserver;
@property (nonatomic, strong) NSTimer *vlcTickTimer;

@end

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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.stallRecoveryTimer invalidate];
    self.stallRecoveryTimer = nil;
    if (self.keyMonitor) {
        [NSEvent removeMonitor:self.keyMonitor];
        self.keyMonitor = nil;
    }
    if (self.currentItem) {
        [self.currentItem removeObserver:self forKeyPath:@"status" context:PlayerItemStatusContext];
        [self.currentItem removeObserver:self forKeyPath:@"playbackBufferEmpty" context:PlayerBufferContext];
        [self.currentItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:PlayerBufferContext];
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
        if (self.currentItem) {
            [self.currentItem removeObserver:self forKeyPath:@"status" context:PlayerItemStatusContext];
            [self.currentItem removeObserver:self forKeyPath:@"playbackBufferEmpty" context:PlayerBufferContext];
            [self.currentItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:PlayerBufferContext];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.currentItem];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:self.currentItem];
            self.currentItem = nil;
        }
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
    // 点播：按“跳过片头”设置，从指定时间点开始播放（续播由 resumeVideo 覆盖）
    self.pendingSeekTime = self.video.skipIntroSeconds;
    [self playURL:episodes[self.episodeIndex].url];
}

- (void)playURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    [self.stallRecoveryTimer invalidate];
    self.stallRecoveryTimer = nil;

    [self preflightURL:url completion:^(BOOL reachable, NSInteger httpStatus) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!reachable || (httpStatus > 0 && httpStatus >= 400)) {
                if (self.liveChannels.count > 0) {
                    [self handlePlaybackFailure];
                } else {
                    [self showNetworkErrorAlert];
                }
                return;
            }
            [self actuallyPlayURL:urlString];
        });
    }];
}

- (void)actuallyPlayURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    if (self.useVLC) {
        [self setLoadingVisible:YES];
        [self.vlcPlayerView playURL:urlString];
        [self updatePlayPauseButton];
        if (self.pendingSeekTime > 0) {
            NSTimeInterval time = self.pendingSeekTime;
            self.pendingSeekTime = 0;
            [self.vlcPlayerView seekToTime:time];
        }
        [self.vlcTickTimer invalidate];
        __weak typeof(self) weakSelf = self;
        self.vlcTickTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [weakSelf handlePlaybackTimeTick];
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setLoadingVisible:NO];
        });
        return;
    }

    if (self.currentItem) {
        [self.currentItem removeObserver:self forKeyPath:@"status" context:PlayerItemStatusContext];
        [self.currentItem removeObserver:self forKeyPath:@"playbackBufferEmpty" context:PlayerBufferContext];
        [self.currentItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:PlayerBufferContext];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.currentItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:self.currentItem];
        self.currentItem = nil;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    item.preferredForwardBufferDuration = (self.video != nil) ? 30.0 : 3.0;
    self.currentItem = item;
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:PlayerItemStatusContext];
    [item addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:PlayerBufferContext];
    [item addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:PlayerBufferContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidPlayToEndTime:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidStall:) name:AVPlayerItemPlaybackStalledNotification object:item];

    AVPlayer *player = self.playerView.player;
    if (!player) {
        player = [[AVPlayer alloc] init];
        self.playerView.player = player;
        [self installPlaybackTimeObserver];
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
    if (context == PlayerBufferContext) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateLoadingIndicator];
        });
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

// 显示 / 隐藏网络加载缓存等待提示，并同步控制指示器动画
- (void)setLoadingVisible:(BOOL)visible {
    self.loadingContainer.hidden = !visible;
    if (visible) {
        [self.loadingIndicator startAnimation:nil];
    } else {
        [self.loadingIndicator stopAnimation:nil];
    }
}

// 根据当前播放项缓冲状态决定是否显示等待提示：缓冲不足或尚未缓冲完成时显示，加载完成后隐藏
- (void)updateLoadingIndicator {
    AVPlayerItem *item = self.currentItem;
    if (!item) {
        [self setLoadingVisible:NO];
        return;
    }
    BOOL buffering = item.isPlaybackBufferEmpty || !item.isPlaybackLikelyToKeepUp;
    [self setLoadingVisible:buffering];
}

// 直播视频无法正确播放时，自动切换到下一线路
- (void)handlePlaybackFailure {
    if (self.liveLines.count <= 1) {
        [self showNetworkErrorAlert];
        return;
    }
    if (self.liveTriedLines >= (NSInteger)self.liveLines.count) {
        [self showNetworkErrorAlert];
        return;
    }

    self.liveTriedLines++;
    NSInteger next = self.liveLineIndex + 1;
    if (next >= (NSInteger)self.liveLines.count) next = 0;
    self.liveLineIndex = next;
    [self.sourcePopup selectItemAtIndex:next];
    [self playCurrentLiveLine];
}

- (void)showNetworkErrorAlert {
    [self setLoadingVisible:NO];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"网络有问题";
    alert.informativeText = @"检查网络连接";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"好的"];
    NSWindow *window = self.view.window;
    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:nil];
    } else {
        [alert runModal];
    }
}

// 播放断流（缓冲停滞）通知：直播在超时后仍未恢复时自动切换下一线路；点播交由 AVPlayer 自动缓冲恢复。
- (void)playerItemDidStall:(NSNotification *)note {
    if (note.object != self.currentItem) return; // 已切换到其他内容，忽略过期通知
    if (self.video != nil) return;               // 点播由更大缓冲配合 AVPlayer 自动恢复
    if (self.liveLines.count <= 1) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.stallRecoveryTimer) return; // 已在等待恢复，避免重复创建定时器

        __weak typeof(self) weakSelf = self;
        self.stallRecoveryTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.stallRecoveryTimer = nil;
            // 超时后仍处于缓冲不足状态才切换线路，避免误伤已恢复的播放
            AVPlayerItem *item = strongSelf.currentItem;
            if (item && !item.isPlaybackLikelyToKeepUp) {
                [strongSelf handlePlaybackFailure];
            }
        }];
    });
}

#pragma mark - 跳过片头片尾

// “设置跳过片头片尾”按钮仅在点播且非全屏时显示
- (void)updateSkipButtonVisibility {
    self.skipButton.hidden = (self.video == nil) || self.fullscreenActive;
}

- (void)showSkipIntroOutroAction:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"设置跳过片头片尾";
    alert.informativeText = @"时间按「分、秒」填写，以视频开始 00:00:00 为基准，填 0 表示不跳过。\n跳过片头：从设定时间点开始播放；跳过片尾：播放至影片结尾或设定时间点后继续播放下一集（如有）。";
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    [alert addButtonWithTitle:@"清除"];

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 112)];

    // 已设置过则回填当前值；未设置时，若当前播放位置靠近片头/片尾，则自动代入
    NSTimeInterval introSeconds = self.video.skipIntroSeconds;
    NSTimeInterval outroSeconds = self.video.skipOutroSeconds;
    if (introSeconds <= 0) introSeconds = [self autoFillIntroSeconds];
    if (outroSeconds <= 0) outroSeconds = [self autoFillOutroSeconds];

    NSInteger introMin = ((NSInteger)introSeconds) / 60;
    NSInteger introSec = ((NSInteger)introSeconds) % 60;
    NSInteger outroMin = ((NSInteger)outroSeconds) / 60;
    NSInteger outroSec = ((NSInteger)outroSeconds) % 60;

    NSTextField *introLabel = [NSTextField labelWithString:@"跳过片头："];
    introLabel.frame = NSMakeRect(0, 78, 90, 24);

    NSTextField *introMinField = [self timeFieldWithValue:introMin];
    introMinField.frame = NSMakeRect(95, 72, 60, 30);
    NSTextField *introMinUnit = [NSTextField labelWithString:@"分"];
    introMinUnit.frame = NSMakeRect(158, 78, 20, 24);

    NSTextField *introSecField = [self timeFieldWithValue:introSec];
    introSecField.frame = NSMakeRect(182, 72, 60, 30);
    NSTextField *introSecUnit = [NSTextField labelWithString:@"秒"];
    introSecUnit.frame = NSMakeRect(245, 78, 20, 24);

    NSTextField *outroLabel = [NSTextField labelWithString:@"跳过片尾："];
    outroLabel.frame = NSMakeRect(0, 34, 90, 24);

    NSTextField *outroMinField = [self timeFieldWithValue:outroMin];
    outroMinField.frame = NSMakeRect(95, 28, 60, 30);
    NSTextField *outroMinUnit = [NSTextField labelWithString:@"分"];
    outroMinUnit.frame = NSMakeRect(158, 34, 20, 24);

    NSTextField *outroSecField = [self timeFieldWithValue:outroSec];
    outroSecField.frame = NSMakeRect(182, 28, 60, 30);
    NSTextField *outroSecUnit = [NSTextField labelWithString:@"秒"];
    outroSecUnit.frame = NSMakeRect(245, 34, 20, 24);

    [accessory addSubview:introLabel];
    [accessory addSubview:introMinField];
    [accessory addSubview:introMinUnit];
    [accessory addSubview:introSecField];
    [accessory addSubview:introSecUnit];
    [accessory addSubview:outroLabel];
    [accessory addSubview:outroMinField];
    [accessory addSubview:outroMinUnit];
    [accessory addSubview:outroSecField];
    [accessory addSubview:outroSecUnit];
    alert.accessoryView = accessory;

    NSWindow *window = self.view.window;
    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
            if (response == NSAlertFirstButtonReturn) {
                NSTimeInterval intro = introMinField.integerValue * 60 + introSecField.integerValue;
                NSTimeInterval outro = outroMinField.integerValue * 60 + outroSecField.integerValue;
                [self applySkipIntroOutro:intro outro:outro];
            } else if (response == NSAlertThirdButtonReturn) {
                [self clearSkipIntroOutro];
            }
        }];
    } else {
        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            NSTimeInterval intro = introMinField.integerValue * 60 + introSecField.integerValue;
            NSTimeInterval outro = outroMinField.integerValue * 60 + outroSecField.integerValue;
            [self applySkipIntroOutro:intro outro:outro];
        } else if (response == NSAlertThirdButtonReturn) {
            [self clearSkipIntroOutro];
        }
    }
}

// 创建放大显示的“分/秒”时间输入框
- (NSTextField *)timeFieldWithValue:(NSInteger)value {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.font = [NSFont systemFontOfSize:16];
    field.placeholderString = @"0";
    field.integerValue = value;
    return field;
}

// 获取当前播放条目的总时长（秒），直播或时长未知返回 0
- (NSTimeInterval)currentItemDuration {
    if (self.useVLC) {
        return [self.vlcPlayerView duration];
    }
    AVPlayer *player = self.playerView.player;
    if (!player || !player.currentItem) return 0;
    CMTime duration = player.currentItem.duration;
    if (CMTIME_IS_INVALID(duration) || CMTIME_IS_INDEFINITE(duration)) return 0;
    return CMTimeGetSeconds(duration);
}

// 未设置片头且当前播放位置靠近片头时，代入当前时间作为片头跳过时间
- (NSTimeInterval)autoFillIntroSeconds {
    NSTimeInterval total = [self currentItemDuration];
    if (total <= 0) return 0;
    NSTimeInterval current;
    if (self.useVLC) {
        current = [self.vlcPlayerView currentTime];
    } else {
        AVPlayer *player = self.playerView.player;
        if (!player || !player.currentItem) return 0;
        current = CMTimeGetSeconds(player.currentTime);
    }
    if (isnan(current) || current <= 0) return 0;
    if (current <= total * 0.2) return current;
    return 0;
}

- (NSTimeInterval)autoFillOutroSeconds {
    NSTimeInterval total = [self currentItemDuration];
    if (total <= 0) return 0;
    NSTimeInterval current;
    if (self.useVLC) {
        current = [self.vlcPlayerView currentTime];
    } else {
        AVPlayer *player = self.playerView.player;
        if (!player || !player.currentItem) return 0;
        current = CMTimeGetSeconds(player.currentTime);
    }
    if (isnan(current)) return 0;
    NSTimeInterval remaining = total - current;
    if (remaining <= 0) return 0;
    if (remaining <= total * 0.15) return current;
    return 0;
}

- (void)applySkipIntroOutro:(NSTimeInterval)intro outro:(NSTimeInterval)outro {
    if (!self.video) return;
    self.video.skipIntroSeconds = intro < 0 ? 0 : intro;
    self.video.skipOutroSeconds = outro < 0 ? 0 : outro;
    [self saveSkipSettingsForCurrentVideo];
    // 保存后即刻生效，包括当前正在播放的视频
    [self applySkipSettingsToCurrentPlayback];
}

// 清除已设置的跳过片头片尾时间，即刻生效
- (void)clearSkipIntroOutro {
    if (!self.video) return;
    self.video.skipIntroSeconds = 0;
    self.video.skipOutroSeconds = 0;
    [self saveSkipSettingsForCurrentVideo];
}

- (void)applySkipSettingsToCurrentPlayback {
    if (!self.video) return;

    NSTimeInterval intro = self.video.skipIntroSeconds;
    if (intro > 0) {
        NSTimeInterval current;
        if (self.useVLC) {
            current = [self.vlcPlayerView currentTime];
            if (current < intro) {
                [self.vlcPlayerView seekToTime:intro];
            }
        } else {
            AVPlayer *player = self.playerView.player;
            if (!player || !player.currentItem) return;
            current = CMTimeGetSeconds(player.currentTime);
            if (!isnan(current) && current < intro) {
                [player seekToTime:CMTimeMakeWithSeconds(intro, NSEC_PER_SEC)
                   toleranceBefore:kCMTimeZero
                    toleranceAfter:kCMTimeZero];
            }
        }
    }

    [self handlePlaybackTimeTick];
}

- (NSString *)skipSettingsKeyForCurrentVideo {
    TVVideo *video = self.video;
    if (!video) return nil;
    // 纳入站点标识：vodId 仅在各站点内部唯一，不同站点的同名同号影片不应共用跳过设置
    NSString *siteKey = video.sourceSite.key ?: @"";
    return [NSString stringWithFormat:@"%@_%ld_%@", siteKey, (long)video.vodId, (video.name ?: @"")];
}

- (void)loadSkipSettingsForCurrentVideo {
    NSString *key = [self skipSettingsKeyForCurrentVideo];
    if (!key) return;
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"TVBoxSkipIntroOutroSettings"];
    NSDictionary *entry = all[key];
    if ([entry isKindOfClass:[NSDictionary class]]) {
        self.video.skipIntroSeconds = [entry[@"intro"] doubleValue];
        self.video.skipOutroSeconds = [entry[@"outro"] doubleValue];
    }
}

- (void)saveSkipSettingsForCurrentVideo {
    NSString *key = [self skipSettingsKeyForCurrentVideo];
    if (!key) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all = [[defaults dictionaryForKey:@"TVBoxSkipIntroOutroSettings"] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (self.video.skipIntroSeconds <= 0 && self.video.skipOutroSeconds <= 0) {
        [all removeObjectForKey:key];
    } else {
        all[key] = @{@"intro": @(self.video.skipIntroSeconds), @"outro": @(self.video.skipOutroSeconds)};
    }
    [defaults setObject:all forKey:@"TVBoxSkipIntroOutroSettings"];
}

- (void)installPlaybackTimeObserver {
    AVPlayer *player = self.playerView.player;
    if (!player) return;
    if (self.playbackTimeObserver) {
        [player removeTimeObserver:self.playbackTimeObserver];
        self.playbackTimeObserver = nil;
    }
    __weak typeof(self) weakSelf = self;
    self.playbackTimeObserver = [player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, NSEC_PER_SEC)
                                                                     queue:dispatch_get_main_queue()
                                                                usingBlock:^(CMTime time) {
        [weakSelf handlePlaybackTimeTick];
    }];
}

- (void)handlePlaybackTimeTick {
    if (!self.video) return;
    NSTimeInterval outro = self.video.skipOutroSeconds;
    if (outro <= 0) return;

    NSTimeInterval current;
    if (self.useVLC) {
        current = [self.vlcPlayerView currentTime];
    } else {
        AVPlayer *player = self.playerView.player;
        if (!player || !player.currentItem) return;
        current = CMTimeGetSeconds(player.currentTime);
    }
    if (isnan(current)) return;
    if (current >= outro) {
        [self advanceToNextEpisode];
    }
}

// 视频自然播放至结尾时触发：片尾设定时间晚于实际结尾时，播放到影片结尾也继续播放下一集。
- (void)playerItemDidPlayToEndTime:(NSNotification *)note {
    if (note.object != self.currentItem) return; // 已切换到下一集，忽略过期通知
    if (!self.video) return;
    if (self.video.skipOutroSeconds <= 0) return;
    [self advanceToNextEpisode];
}

// 播放至片尾设定时间后，继续播放本视频下一集（如有）；已是最后一集则停止
- (void)advanceToNextEpisode {
    if (!self.video) return;
    NSArray<TVEpisode *> *episodes = (self.sourceIndex >= 0 && self.sourceIndex < (NSInteger)self.sources.count) ? self.sources[self.sourceIndex].episodes : @[];
    NSInteger next = self.episodeIndex + 1;
    if (next < (NSInteger)episodes.count) {
        self.episodeIndex = next;
        if (self.episodePopup.indexOfSelectedItem != next) {
            [self.episodePopup selectItemAtIndex:next];
        }
        [self playCurrentEpisode];
    } else {
        if (self.useVLC) {
            [self.vlcPlayerView pause];
        } else {
            [self.playerView.player pause];
        }
        [self updatePlayPauseButton];
    }
}

- (void)preflightURL:(NSURL *)url completion:(void (^)(BOOL reachable, NSInteger httpStatus))completion {
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        if (completion) completion(YES, 0);
        return;
    }

    NSMutableURLRequest *headRequest = [NSMutableURLRequest requestWithURL:url];
    headRequest.HTTPMethod = @"HEAD";
    headRequest.timeoutInterval = 5.0;
    [headRequest setValue:TVBoxHTTPUserAgent forHTTPHeaderField:@"User-Agent"];
    [headRequest setValue:@"*/*" forHTTPHeaderField:@"Accept"];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:headRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[Preflight] HEAD %@ -> ERROR: %@", url.absoluteString, error.localizedDescription);
            if (completion) completion(NO, 0);
            return;
        }
        NSInteger status = 0;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            status = ((NSHTTPURLResponse *)response).statusCode;
        }
        NSLog(@"[Preflight] HEAD %@ -> status=%ld", url.absoluteString, (long)status);
        if (completion) completion(YES, status);
    }];
    [task resume];
}

@end