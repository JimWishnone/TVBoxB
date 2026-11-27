#import "PlayerViewController+Private.h"

@implementation PlayerViewController (Playback)

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

    [self _cleanupAVPlayerItem];

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
@end