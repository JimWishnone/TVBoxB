#import "PlayerViewController+Private.h"

@implementation PlayerViewController (Skip)

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
    // 纳入站点标识：vodId 仅在各站点内部唯一，不同站点的同名同号影片不应共用跳过设置。
    // 不纳入视频名：vodId 在站点内已唯一，name 易变（站点改名会导致已保存设置失效）。
    NSString *siteKey = video.sourceSite.key ?: @"";
    return [NSString stringWithFormat:@"%@_%ld", siteKey, (long)video.vodId];
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

// VLC 播放至自然结尾时触发：与 AVKit 的 playerItemDidPlayToEndTime 保持一致，
// 仅在设置了跳过片尾时间时续播下一集（片尾设定时间晚于实际结尾时由本回调兜底续播）。
- (void)handleVLCDidPlayToEnd {
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

@end
