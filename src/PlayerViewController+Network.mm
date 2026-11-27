#import "PlayerViewController+Private.h"
#import "ConfigManager.h"

@implementation PlayerViewController (Network)

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