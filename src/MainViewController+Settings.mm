#import "MainViewController+Private.h"

@implementation MainViewController (Settings)

#pragma mark - 播放器展示

// 播放器窗体只允许存在一个：无论是点播还是直播，都复用同一个窗体与同一个播放器。
- (void)presentPlayerWithTitle:(NSString *)title block:(void (^)(PlayerViewController *player))block {
    // 切换播放内容前，先把上一条播放记录落盘。
    [self finalizeCurrentHistory];

    PlayerViewController *player = (PlayerViewController *)self.playerWindow.contentViewController;
    if (player && [player isKindOfClass:[PlayerViewController class]]) {
        self.playerWindow.title = title ?: @"TVBox";
        [self.playerWindow makeKeyAndOrderFront:nil];
        block(player);
        return;
    }

    player = [[PlayerViewController alloc] init];

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 620)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = title ?: @"TVBox";
    window.releasedWhenClosed = NO;
    window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    window.contentViewController = player;
    [window center];
    [window makeKeyAndOrderFront:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerWindowWillClose:)
                                                 name:NSWindowWillCloseNotification
                                               object:window];

    self.playerWindow = window;
    block(player);
}

- (void)playerWindowWillClose:(NSNotification *)note {
    NSWindow *window = note.object;
    if ([window.contentViewController isKindOfClass:[PlayerViewController class]]) {
        [self finalizeCurrentHistory];
        [(PlayerViewController *)window.contentViewController stop];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSWindowWillCloseNotification
                                                  object:window];
    self.playerWindow = nil;
}

#pragma mark - 设置动作

- (void)reloadConfigAction:(id)sender {
    [self reloadConfig];
}

- (void)refreshDataSourcesAction:(id)sender {
    [self reloadConfig];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self checkDataSourcesAvailabilityInteractive:YES];
    });
}

- (void)loadConfigURLRows {
    NSArray<NSString *> *vodURLs = [self.config configURLs];
    self.vodConfigURLField.stringValue = vodURLs.count > 0 ? vodURLs.firstObject : @"";
    NSArray<NSString *> *liveURLs = [self.config liveConfigURLs];
    self.liveConfigURLField.stringValue = liveURLs.count > 0 ? liveURLs.firstObject : @"";
}

// 读取并回填历史记录相关设置（是否保存 + 保存条数）
- (void)loadHistorySettings {
    BOOL enabled = [self saveHistoryEnabled];
    self.historySaveSwitch.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.historyLimitField.integerValue = (NSInteger)[self historyLimit];
    self.historyLimitField.enabled = enabled;
}

// 切换“保存视频播放历史记录”选项：立即持久化，并同步条数输入框可用状态
- (void)historySaveSwitchChanged:(id)sender {
    BOOL enabled = (self.historySaveSwitch.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kTVBoxSaveHistoryKey];
    self.historyLimitField.enabled = enabled;
    if (!enabled) {
        // 关闭历史记录时清空已保存内容，避免残留旧记录
        [self.historyItems removeAllObjects];
        [self saveHistory];
        [self.historyTable reloadData];
    }
}

// 用户结束编辑“保存条数”后，持久化新值并裁剪现有历史
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object != self.historyLimitField) return;
    NSInteger limit = self.historyLimitField.integerValue;
    if (limit < 1) limit = 1;
    if (limit > 500) limit = 500;
    self.historyLimitField.integerValue = limit;
    [[NSUserDefaults standardUserDefaults] setInteger:limit forKey:kTVBoxHistoryLimitKey];
    while (self.historyItems.count > (NSUInteger)limit) {
        [self.historyItems removeLastObject];
    }
    [self saveHistory];
    [self.historyTable reloadData];
}

// 是否保存播放历史记录（未设置时默认开启）
- (BOOL)saveHistoryEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kTVBoxSaveHistoryKey] == nil) return YES;
    return [defaults boolForKey:kTVBoxSaveHistoryKey];
}

// 历史记录保存条数上限（未设置时默认 30）
- (NSUInteger)historyLimit {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kTVBoxHistoryLimitKey] == nil) return kTVBoxHistoryLimit;
    NSInteger limit = [defaults integerForKey:kTVBoxHistoryLimitKey];
    if (limit < 1) limit = 1;
    return (NSUInteger)limit;
}


- (void)loadVLCSetting {
    BOOL useVLC = [[NSUserDefaults standardUserDefaults] boolForKey:kTVBoxUseVLCKey];
    self.vlcPlaybackSwitch.state = useVLC ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)vlcPlaybackSwitchChanged:(id)sender {
    BOOL enabled = (self.vlcPlaybackSwitch.state == NSControlStateValueOn);
    if (!enabled) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kTVBoxUseVLCKey];
        return;
    }
    [self showVLCCheckPanel];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL capable = [TVBoxVLCPlayerView checkVLCCapable];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideVLCCheckPanel];
            if (capable) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kTVBoxUseVLCKey];
            } else {
                self.vlcPlaybackSwitch.state = NSControlStateValueOff;
                [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kTVBoxUseVLCKey];
                NSAlert *alert = [[NSAlert alloc] init];
                alert.alertStyle = NSAlertStyleCritical;
                alert.messageText = @"VLC 视频播放能力检查失败";
                alert.informativeText = @"未检测到可用的 VLC 视频播放能力。本软件已集成 VLC 播放组件（位于 App Bundle 内），若出现此问题可能是集成文件已损坏或丢失。请尝试重新编译构建，或将 /Applications/TVBoxB.app 删除后重新生成。若已单独安装 VLC 媒体播放器到 /Applications/VLC.app，也可作为备选方案。";
                [alert addButtonWithTitle:@"好的"];
                [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
            }
        });
    });
}

- (void)showVLCCheckPanel {
    if (self.vlcCheckPanel) return;
    NSWindow *parent = self.view.window;
    if (!parent) return;

    NSWindow *panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 380, 140)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    panel.title = @"检查中";
    panel.releasedWhenClosed = NO;

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 380, 140)];

    NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 86, 24, 24)];
    spinner.style = NSProgressIndicatorStyleSpinning;
    [spinner startAnimation:nil];

    NSTextField *titleLabel = [NSTextField labelWithString:@"正在检查 VLC 视频播放能力…"];
    titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    titleLabel.frame = NSMakeRect(56, 90, 300, 20);

    NSTextField *statusLabel = [NSTextField labelWithString:@"正在检测内置 VLC 播放组件…"];
    statusLabel.font = [NSFont systemFontOfSize:12];
    statusLabel.textColor = [NSColor secondaryLabelColor];
    statusLabel.frame = NSMakeRect(56, 64, 300, 18);
    self.vlcCheckStatusLabel = statusLabel;

    [content addSubview:spinner];
    [content addSubview:titleLabel];
    [content addSubview:statusLabel];
    panel.contentView = content;

    self.vlcCheckPanel = panel;
    [parent beginSheet:panel completionHandler:nil];
}

- (void)hideVLCCheckPanel {
    if (self.vlcCheckPanel) {
        NSWindow *panel = self.vlcCheckPanel;
        self.vlcCheckPanel = nil;
        self.vlcCheckStatusLabel = nil;
        [self.view.window endSheet:panel];
    }
}

- (void)saveConfigURLAction:(id)sender {
    // 结束当前编辑，确保已输入内容提交
    [self.view.window makeFirstResponder:nil];
    [self setSettingsProgress:@""];

    NSString *vodURL = [self.vodConfigURLField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *liveURL = [self.liveConfigURLField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // 未填写点播数据源时：清空点播源，仅处理直播数据源
    if (vodURL.length == 0) {
        [self.config saveConfigURLs:@[]];
        if (liveURL.length > 0) {
            // 直播数据源单独进行详细验证后保存
            [self validateLiveURLAndSave:liveURL];
        } else {
            [self.config saveLiveConfigURLs:@[]];
            [self loadConfigURLRows];
            [self reloadConfig];
        }
        return;
    }

    // 点播数据源必须经过可访问、可解析、TVBox 格式验证后才能保存，验证过程逐步展示
    [self.config validateVODConfigURL:vodURL progress:^(NSString *step) {
        [self setSettingsProgress:step];
        [self showValidationProgress:step forLabel:self.vodValidationResultLabel];
    } completion:^(NSArray<TVLiveSource *> * _Nullable detectedLives, NSError * _Nullable error) {
        if (error) {
            [self setSettingsProgress:@""];
            [self showValidationFailure:error.localizedDescription forLabel:self.vodValidationResultLabel];
            [self showErrorAlertWithMessage:error.localizedDescription];
            return;
        }
        [self showValidationSuccess:@"✓ 点播数据源验证通过。" forLabel:self.vodValidationResultLabel];
        [self.config saveConfigURLs:@[vodURL]];

        // 该配置包含直播数据源时，提供列表供用户选择是否保存
        if (detectedLives.count > 0) {
            [self presentLiveSourcePicker:detectedLives completion:^(TVLiveSource * _Nullable chosenSource) {
                NSString *finalLive = (chosenSource.url.length > 0) ? chosenSource.url : liveURL;
                if (chosenSource) {
                    // 同步保存该直播源自带的节目单地址（无 epg 则清除旧关联）
                    [self.config saveLiveEPGURL:chosenSource.epg ?: @""];
                }
                [self validateAndSaveLiveURL:finalLive];
            }];
        } else {
            // 不包含直播数据：提示用户，并不从该地址保存直播数据源；仅处理用户手动填写的专属直播数据源
            [self showInfoAlertWithMessage:@"该点播数据源地址不包含直播数据，未从该地址保存直播数据源。"];
            [self validateAndSaveLiveURL:liveURL];
        }
    }];
}

// 设置页验证进度显示
- (void)setSettingsProgress:(NSString *)text {
    self.settingsProgressLabel.stringValue = text ?: @"";
}

// 在指定结果标签上显示验证进行中状态（橙色）
- (void)showValidationProgress:(NSString *)text forLabel:(NSTextField *)label {
    label.stringValue = text ?: @"";
    label.textColor = [NSColor systemOrangeColor];
}

// 在指定结果标签上显示验证通过状态（绿色）
- (void)showValidationSuccess:(NSString *)text forLabel:(NSTextField *)label {
    label.stringValue = text ?: @"";
    label.textColor = [NSColor systemGreenColor];
}

// 在指定结果标签上显示验证失败状态（红色）
- (void)showValidationFailure:(NSString *)text forLabel:(NSTextField *)label {
    label.stringValue = text ?: @"";
    label.textColor = [NSColor systemRedColor];
}

// 处理直播数据源：为空则清空并完成保存，否则单独详细验证后保存
- (void)validateAndSaveLiveURL:(NSString *)liveURL {
    NSString *trimmed = [liveURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        [self.config saveLiveConfigURLs:@[]];
        [self loadConfigURLRows];
        [self reloadConfig];
        [self setSettingsProgress:@"点播数据源验证通过，已保存。"];
        return;
    }
    [self validateLiveURLAndSave:trimmed];
}

// 直播数据源单独详细验证并保存
- (void)validateLiveURLAndSave:(NSString *)liveURL {
    [self.config validateLiveConfigURL:liveURL progress:^(NSString *step) {
        [self setSettingsProgress:step];
        [self showValidationProgress:step forLabel:self.liveValidationResultLabel];
    } completion:^(NSError * _Nullable error) {
        if (error) {
            [self setSettingsProgress:@""];
            [self showValidationFailure:error.localizedDescription forLabel:self.liveValidationResultLabel];
            [self showErrorAlertWithMessage:error.localizedDescription];
            return;
        }
        [self showValidationSuccess:@"✓ 直播数据源验证通过。" forLabel:self.liveValidationResultLabel];
        [self.config saveLiveConfigURLs:@[liveURL]];
        [self loadConfigURLRows];
        [self reloadConfig];
        [self setSettingsProgress:@"直播数据源验证通过，已保存。"];
    }];
}

// 显性验证点播数据源（仅验证，不保存），逐步显示详细验证过程
- (void)validateVODURLAction:(id)sender {
    [self.view.window makeFirstResponder:nil];
    [self setSettingsProgress:@""];
    [self showValidationProgress:@"" forLabel:self.vodValidationResultLabel];

    NSString *vodURL = [self.vodConfigURLField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (vodURL.length == 0) {
        [self showValidationFailure:@"✗ 请先填写点播数据源 URL。" forLabel:self.vodValidationResultLabel];
        [self showErrorAlertWithMessage:@"请先填写点播数据源 URL。"];
        return;
    }

    [self.config validateVODConfigURL:vodURL progress:^(NSString *step) {
        [self setSettingsProgress:step];
        [self showValidationProgress:step forLabel:self.vodValidationResultLabel];
    } completion:^(NSArray<TVLiveSource *> * _Nullable detectedLives, NSError * _Nullable error) {
        if (error) {
            [self setSettingsProgress:@""];
            [self showValidationFailure:[NSString stringWithFormat:@"✗ 验证失败：%@", error.localizedDescription] forLabel:self.vodValidationResultLabel];
            [self showErrorAlertWithMessage:error.localizedDescription];
            return;
        }
        if (detectedLives.count > 0) {
            [self showValidationSuccess:[NSString stringWithFormat:@"✓ 点播数据源验证通过，检测到 %ld 个直播源。", (long)detectedLives.count] forLabel:self.vodValidationResultLabel];
        } else {
            [self showValidationSuccess:@"✓ 点播数据源验证通过（未包含直播数据）。" forLabel:self.vodValidationResultLabel];
        }
    }];
}

// 显性验证直播数据源（仅验证，不保存），逐步显示详细验证过程
- (void)validateLiveURLAction:(id)sender {
    [self.view.window makeFirstResponder:nil];
    [self setSettingsProgress:@""];
    [self showValidationProgress:@"" forLabel:self.liveValidationResultLabel];

    NSString *liveURL = [self.liveConfigURLField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (liveURL.length == 0) {
        [self showValidationFailure:@"✗ 请先填写直播数据源 URL。" forLabel:self.liveValidationResultLabel];
        [self showErrorAlertWithMessage:@"请先填写直播数据源 URL。"];
        return;
    }

    [self.config validateLiveConfigURL:liveURL progress:^(NSString *step) {
        [self setSettingsProgress:step];
        [self showValidationProgress:step forLabel:self.liveValidationResultLabel];
    } completion:^(NSError * _Nullable error) {
        if (error) {
            [self setSettingsProgress:@""];
            [self showValidationFailure:[NSString stringWithFormat:@"✗ 验证失败：%@", error.localizedDescription] forLabel:self.liveValidationResultLabel];
            [self showErrorAlertWithMessage:error.localizedDescription];
            return;
        }
        [self showValidationSuccess:@"✓ 直播数据源验证通过。" forLabel:self.liveValidationResultLabel];
    }];
}

- (void)showErrorAlertWithMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"保存失败";
    alert.informativeText = message ?: @"";
    [alert addButtonWithTitle:@"确定"];
    if (self.view.window) {
        [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
    } else {
        [alert runModal];
    }
}

- (void)showInfoAlertWithMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"提示";
    alert.informativeText = message ?: @"";
    [alert addButtonWithTitle:@"确定"];
    if (self.view.window) {
        [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
    } else {
        [alert runModal];
    }
}

// 该配置包含直播数据源时，弹出列表供用户选择是否保存其中一个
- (void)presentLiveSourcePicker:(NSArray<TVLiveSource *> *)lives completion:(void (^)(TVLiveSource * _Nullable chosenSource))completion {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"该配置包含直播数据源";
    alert.informativeText = @"请选择要保存到直播数据源的地址（选择「不选择」则忽略）：";
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"不选择"];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 440, 26)];
    popup.pullsDown = NO;
    for (TVLiveSource *source in lives) {
        NSString *name = source.name.length > 0 ? source.name : @"未命名直播源";
        NSString *suffix = (source.epg.length > 0) ? @" · 含节目单" : @"";
        [popup addItemWithTitle:[NSString stringWithFormat:@"%@（%@）%@", name, (source.url ?: @""), suffix]];
        [popup.lastItem setRepresentedObject:source];
    }

    // 显示时选中现在已经选择的直播源
    NSString *currentLiveURL = [self.config liveConfigURLs].firstObject;
    if (currentLiveURL.length > 0) {
        for (NSInteger i = 0; i < popup.numberOfItems; i++) {
            NSMenuItem *item = [popup itemAtIndex:i];
            TVLiveSource *source = (TVLiveSource *)item.representedObject;
            if ([source.url isEqualToString:currentLiveURL]) {
                [popup selectItemAtIndex:i];
                break;
            }
        }
    }
    alert.accessoryView = popup;

    void (^handleResponse)(NSModalResponse) = ^(NSModalResponse response) {
        TVLiveSource *chosen = nil;
        if (response == NSAlertFirstButtonReturn) {
            chosen = (TVLiveSource *)popup.selectedItem.representedObject;
        }
        if (completion) completion(chosen);
    };

    if (self.view.window) {
        [alert beginSheetModalForWindow:self.view.window completionHandler:handleResponse];
    } else {
        handleResponse([alert runModal]);
    }
}


@end
