#import "PlayerViewController.h"
#import "TVBoxVLCPlayerView.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>

// KVO 上下文指针：主实现中定义，供各 Category 共享（保持同一地址以正确区分回调来源）
extern void *PlayerItemStatusContext;
extern void *PlayerBufferContext;

// 私有属性与内部方法声明：供 PlayerViewController.mm 与各 Category 实现文件共享，
// 保证拆分后编译可见性一致、无功能变化。
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

// 主实现中定义、供 Category 调用的内部方法
- (void)applyCurrentLiveChannel;
- (void)updatePlayPauseButton;
- (void)_cleanupAVPlayerItem;

@end

// 播放核心模块（点播 / 直播 / 线路切换 / 播放 URL 调度）
@interface PlayerViewController (Playback)

- (void)rebuildSourcePopup;
- (void)rebuildEpisodePopup;
- (void)sourceChanged:(NSPopUpButton *)sender;
- (void)rebuildLiveLinePopup;
- (void)playCurrentLiveLine;
- (void)episodeChanged:(NSPopUpButton *)sender;
- (void)playCurrentEpisode;
- (void)playURL:(NSString *)urlString;
- (void)actuallyPlayURL:(NSString *)urlString;

@end

// 网络预检 / 加载提示 / 播放失败处理模块
@interface PlayerViewController (Network)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context;
- (void)setLoadingVisible:(BOOL)visible;
- (void)updateLoadingIndicator;
- (void)handlePlaybackFailure;
- (void)showNetworkErrorAlert;
- (void)playerItemDidStall:(NSNotification *)note;
- (void)preflightURL:(NSURL *)url completion:(void (^)(BOOL reachable, NSInteger httpStatus))completion;

@end

// 跳过片头片尾模块
@interface PlayerViewController (Skip)

- (void)updateSkipButtonVisibility;
- (void)showSkipIntroOutroAction:(id)sender;
- (NSTextField *)timeFieldWithValue:(NSInteger)value;
- (NSTimeInterval)currentItemDuration;
- (NSTimeInterval)autoFillIntroSeconds;
- (NSTimeInterval)autoFillOutroSeconds;
- (void)applySkipIntroOutro:(NSTimeInterval)intro outro:(NSTimeInterval)outro;
- (void)clearSkipIntroOutro;
- (void)applySkipSettingsToCurrentPlayback;
- (NSString *)skipSettingsKeyForCurrentVideo;
- (void)loadSkipSettingsForCurrentVideo;
- (void)saveSkipSettingsForCurrentVideo;
- (void)installPlaybackTimeObserver;
- (void)handlePlaybackTimeTick;
- (void)playerItemDidPlayToEndTime:(NSNotification *)note;
- (void)handleVLCDidPlayToEnd;
- (void)advanceToNextEpisode;

@end