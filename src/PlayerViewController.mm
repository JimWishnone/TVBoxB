#import "PlayerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

static void *PlayerItemStatusContext = &PlayerItemStatusContext;

@interface PlayerViewController ()

@property (nonatomic, strong) AVPlayerView *playerView;
@property (nonatomic, strong) NSStackView *controlBar;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSPopUpButton *sourcePopup;
@property (nonatomic, strong) NSPopUpButton *episodePopup;
@property (nonatomic, strong) NSTextField *detailLabel;
@property (nonatomic, strong) NSTextField *hintLabel;
@property (nonatomic, strong) NSButton *channelPrevButton;
@property (nonatomic, strong) NSButton *channelNextButton;
@property (nonatomic, strong) NSButton *linePrevButton;
@property (nonatomic, strong) NSButton *lineNextButton;
@property (nonatomic, strong) NSButton *zoomButton;
@property (nonatomic, strong) NSButton *fullscreenButton;
@property (nonatomic, strong) NSButton *returnButton;
@property (nonatomic, strong) NSButton *exitButton;

@property (nonatomic, assign) BOOL immersive;
@property (nonatomic, assign) BOOL savedDetailHidden;
@property (nonatomic, assign) BOOL savedControlBarHidden;
@property (nonatomic, assign) BOOL fullscreenActive;
@property (nonatomic, assign) BOOL windowImmersive;
@property (nonatomic, weak) NSWindow *observedWindow;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *normalLayoutConstraints;
@property (nonatomic, strong) NSLayoutConstraint *immersiveBottomConstraint;

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

    self.titleLabel = [NSTextField labelWithString:@""];
    self.titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.sourcePopup = [[NSPopUpButton alloc] init];
    [self.sourcePopup setTarget:self];
    [self.sourcePopup setAction:@selector(sourceChanged:)];

    self.episodePopup = [[NSPopUpButton alloc] init];
    [self.episodePopup setTarget:self];
    [self.episodePopup setAction:@selector(episodeChanged:)];

    self.detailLabel = [NSTextField wrappingLabelWithString:@""];
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailLabel.font = [NSFont systemFontOfSize:12];
    self.detailLabel.textColor = [NSColor secondaryLabelColor];
    self.detailLabel.maximumNumberOfLines = 0;
    self.detailLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.view addSubview:self.detailLabel];

    self.hintLabel = [NSTextField labelWithString:@"↑↓ 切换频道　←→ 切换线路"];
    self.hintLabel.font = [NSFont systemFontOfSize:12];
    self.hintLabel.textColor = [NSColor secondaryLabelColor];
    self.hintLabel.hidden = YES;

    self.channelPrevButton = [self iconButtonWithSymbol:@"chevron.up" tooltip:@"上一个频道" action:@selector(channelPrevAction:)];
    self.channelNextButton = [self iconButtonWithSymbol:@"chevron.down" tooltip:@"下一个频道" action:@selector(channelNextAction:)];
    self.linePrevButton = [self iconButtonWithSymbol:@"chevron.left" tooltip:@"上一个线路" action:@selector(linePrevAction:)];
    self.lineNextButton = [self iconButtonWithSymbol:@"chevron.right" tooltip:@"下一个线路" action:@selector(lineNextAction:)];
    self.zoomButton = [self iconButtonWithSymbol:@"macwindow" tooltip:@"全窗口 / 返回" action:@selector(toggleFullWindowAction:)];
    self.fullscreenButton = [self iconButtonWithSymbol:@"arrow.up.left.and.arrow.down.right" tooltip:@"全屏 / 返回" action:@selector(toggleFullScreenAction:)];
    self.channelPrevButton.hidden = YES;
    self.channelNextButton.hidden = YES;
    self.linePrevButton.hidden = YES;
    self.lineNextButton.hidden = YES;

    self.controlBar = [NSStackView stackViewWithViews:@[self.titleLabel, self.channelPrevButton, self.channelNextButton, self.sourcePopup, self.linePrevButton, self.lineNextButton, self.episodePopup, self.hintLabel, self.zoomButton, self.fullscreenButton]];
    self.controlBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.controlBar.spacing = 8;
    self.controlBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.controlBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.playerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.playerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.playerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    self.normalLayoutConstraints = @[
        [self.detailLabel.topAnchor constraintEqualToAnchor:self.playerView.bottomAnchor constant:8],
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.detailLabel.heightAnchor constraintEqualToConstant:110],

        [self.controlBar.topAnchor constraintEqualToAnchor:self.detailLabel.bottomAnchor constant:8],
        [self.controlBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.controlBar.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.controlBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8],
        [self.controlBar.heightAnchor constraintEqualToConstant:30],

        [self.titleLabel.widthAnchor constraintGreaterThanOrEqualToConstant:160],
        [self.sourcePopup.widthAnchor constraintGreaterThanOrEqualToConstant:200],
        [self.episodePopup.widthAnchor constraintGreaterThanOrEqualToConstant:120],
    ];
    [NSLayoutConstraint activateConstraints:self.normalLayoutConstraints];

    self.immersiveBottomConstraint = [self.playerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];

    // 全窗口模式下显示“返回正常窗体”按钮与 X 按钮，二者均用于返回正常窗体。
    self.returnButton = [NSButton buttonWithTitle:@"返回正常窗体" target:self action:@selector(exitImmersiveAction:)];
    self.returnButton.image = [NSImage imageWithSystemSymbolName:@"arrow.uturn.backward" accessibilityDescription:@"返回正常窗体"];
    self.returnButton.imagePosition = NSImageLeading;
    self.returnButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.returnButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.returnButton.hidden = YES;

    self.exitButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"返回正常窗体"] target:self action:@selector(exitImmersiveAction:)];
    self.exitButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.exitButton.toolTip = @"返回正常窗体";
    self.exitButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.exitButton.hidden = YES;

    [self.view addSubview:self.returnButton];
    [self.view addSubview:self.exitButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.exitButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [self.exitButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.returnButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [self.returnButton.trailingAnchor constraintEqualToAnchor:self.exitButton.leadingAnchor constant:-8],
    ]];

    __weak typeof(self) weakSelf = self;
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        if ([weakSelf handleKeyEvent:event]) {
            return nil;
        }
        return event;
    }];
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
            self.savedDetailHidden = self.detailLabel.hidden;
            self.savedControlBarHidden = self.controlBar.hidden;
            [NSLayoutConstraint deactivateConstraints:self.normalLayoutConstraints];
            self.immersiveBottomConstraint.active = YES;
            self.detailLabel.hidden = YES;
            self.controlBar.hidden = YES;
        } else {
            self.immersiveBottomConstraint.active = NO;
            [NSLayoutConstraint activateConstraints:self.normalLayoutConstraints];
            self.detailLabel.hidden = self.savedDetailHidden;
            self.controlBar.hidden = self.savedControlBarHidden;
        }
    }
    // 仅在“全窗口”模式下显示“返回正常窗体”按钮与 X 按钮。
    BOOL showOverlay = self.windowImmersive;
    self.returnButton.hidden = !showOverlay;
    self.exitButton.hidden = !showOverlay;
}

- (BOOL)handleKeyEvent:(NSEvent *)event {
    if (!self.view.window || !self.view.window.isKeyWindow) return NO;

    // 全窗口模式下按 X 键返回正常窗体。
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
    self.detailLabel.attributedStringValue = [self detailAttributedTextForVideo:video];
    self.detailLabel.hidden = NO;
    self.episodePopup.hidden = NO;
    self.hintLabel.hidden = YES;
    self.channelPrevButton.hidden = YES;
    self.channelNextButton.hidden = YES;
    self.linePrevButton.hidden = YES;
    self.lineNextButton.hidden = YES;

    [self rebuildSourcePopup];
    [self rebuildEpisodePopup];

    if (self.sources.count == 0) {
        self.controlBar.hidden = YES;
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

    self.controlBar.hidden = NO;
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
        self.detailLabel.stringValue = @"";
        self.controlBar.hidden = YES;
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
    self.detailLabel.stringValue = channel.group.length > 0 ? [NSString stringWithFormat:@"分组：%@", channel.group] : @"";
    self.detailLabel.hidden = NO;
    self.episodePopup.hidden = YES;
    self.hintLabel.hidden = NO;
    self.channelPrevButton.hidden = NO;
    self.channelNextButton.hidden = NO;
    self.linePrevButton.hidden = NO;
    self.lineNextButton.hidden = NO;
    self.controlBar.hidden = (self.liveLines.count == 0);

    [self rebuildLiveLinePopup];
    [self playCurrentLiveLine];
}

- (NSAttributedString *)detailAttributedTextForVideo:(TVVideo *)video {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
    };

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    NSMutableArray<NSString *> *meta = [NSMutableArray array];
    if (video.typeName.length > 0) [meta addObject:video.typeName];
    if (video.vodTime.length > 0) [meta addObject:video.vodTime];
    if (video.remarks.length > 0) [meta addObject:video.remarks];

    if (meta.count > 0) {
        [self appendDetailLine:result text:[meta componentsJoinedByString:@"  ·  "] attrs:attrs];
    }
    if (video.vodDirector.length > 0) {
        [self appendDetailLine:result text:[NSString stringWithFormat:@"导演：%@", video.vodDirector] attrs:attrs];
    }
    if (video.vodActor.length > 0) {
        [self appendDetailLine:result text:[NSString stringWithFormat:@"主演：%@", video.vodActor] attrs:attrs];
    }
    if (video.vodContent.length > 0) {
        [self appendDetailLine:result text:@"简介：" attrs:attrs];
        NSAttributedString *html = [self htmlAttributedString:video.vodContent];
        if (html.length > 0) {
            [result appendAttributedString:html];
        } else {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:video.vodContent attributes:attrs]];
        }
    }

    if (result.length == 0) {
        return [[NSAttributedString alloc] initWithString:@"暂无详细信息" attributes:attrs];
    }
    return result;
}

- (void)appendDetailLine:(NSMutableAttributedString *)target text:(NSString *)text attrs:(NSDictionary *)attrs {
    if (target.length > 0) {
        [target appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:attrs]];
    }
    [target appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attrs]];
}

// 将简介内容按 HTML 解释，支持 <br>、<p>、<b>、<i> 等标签。
- (NSAttributedString *)htmlAttributedString:(NSString *)html {
    if (html.length == 0) return nil;
    NSString *wrapped = [NSString stringWithFormat:@"<span style=\"font-size:12px;\">%@</span>", html];
    NSData *data = [wrapped dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;

    NSError *error = nil;
    NSDictionary *options = @{
        NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
        NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding),
    };
    NSAttributedString *attr = [[NSAttributedString alloc] initWithData:data
                                                                options:options
                                                     documentAttributes:nil
                                                                  error:&error];
    if (error || attr.length == 0) return nil;

    NSMutableAttributedString *normalized = [attr mutableCopy];
    [attr enumerateAttributesInRange:NSMakeRange(0, attr.length)
                             options:0
                          usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attributes, NSRange range, BOOL *stop) {
        NSFont *font = attributes[NSFontAttributeName];
        NSFontManager *fontManager = [NSFontManager sharedFontManager];
        NSFont *newFont = [NSFont systemFontOfSize:12];
        if (font && ([fontManager traitsOfFont:font] & NSBoldFontMask)) {
            newFont = [fontManager convertFont:newFont toHaveTrait:NSBoldFontMask];
        }
        if (font && ([fontManager traitsOfFont:font] & NSItalicFontMask)) {
            newFont = [fontManager convertFont:newFont toHaveTrait:NSItalicFontMask];
        }
        [normalized addAttribute:NSFontAttributeName value:newFont range:range];
        [normalized addAttribute:NSForegroundColorAttributeName value:[NSColor secondaryLabelColor] range:range];
    }];
    return normalized;
}

- (void)stop {
    [self.playerView.player pause];
    self.playerView.player = nil;
    if (self.currentItem) {
        [self.currentItem removeObserver:self forKeyPath:@"status" context:PlayerItemStatusContext];
        self.currentItem = nil;
    }
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

    AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
    self.playerView.player = player;
    [player play];
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