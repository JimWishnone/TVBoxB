#import "MainViewController+Private.h"

@implementation MainViewController (UISettings)

#pragma mark - 设置页构建

- (NSView *)buildSettingsView {
    NSView *container = [[NSView alloc] init];

    NSTextField *title = [NSTextField labelWithString:@"设置"];
    title.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *hintLabel = [NSTextField labelWithString:@"视频数据源分为两个部分：点播数据源（主数据源，必填）与直播视频源（专属直播的数据源，选填）。点播数据源仅支持填写一个 URL，可点击输入框旁的「验证」按钮单独验证，保存前也会进行可访问、可解析验证；若该地址包含直播数据源，可从中选择一个保存到直播数据源。修改后点击「保存并重新加载」立即生效。"];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.font = [NSFont systemFontOfSize:12];
    hintLabel.textColor = [NSColor secondaryLabelColor];
    hintLabel.maximumNumberOfLines = 0;
    hintLabel.lineBreakMode = NSLineBreakByWordWrapping;
    hintLabel.preferredMaxLayoutWidth = 280;

    // ---- 点播数据源（主数据源） ----
    NSTextField *vodTitle = [NSTextField labelWithString:@"点播数据源（主数据源）"];
    vodTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    vodTitle.translatesAutoresizingMaskIntoConstraints = NO;

    self.vodConfigURLField = [NSTextField textFieldWithString:@""];
    self.vodConfigURLField.placeholderString = @"请输入点播数据源 URL，例如 https://…";
    self.vodConfigURLField.font = [NSFont systemFontOfSize:16];
    self.vodConfigURLField.controlSize = NSControlSizeLarge;
    self.vodConfigURLField.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *vodValidateButton = [NSButton buttonWithTitle:@"验证" target:self action:@selector(validateVODURLAction:)];
    vodValidateButton.bezelStyle = NSBezelStyleRounded;
    vodValidateButton.image = [NSImage imageWithSystemSymbolName:@"checkmark.seal" accessibilityDescription:@"验证"];
    vodValidateButton.imagePosition = NSImageLeading;
    vodValidateButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.vodValidationResultLabel = [NSTextField wrappingLabelWithString:@""];
    self.vodValidationResultLabel.font = [NSFont systemFontOfSize:12];
    self.vodValidationResultLabel.textColor = [NSColor secondaryLabelColor];
    self.vodValidationResultLabel.maximumNumberOfLines = 0;
    self.vodValidationResultLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.vodValidationResultLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // ---- 直播视频源（专属直播的数据源，选填） ----
    NSTextField *liveTitle = [NSTextField labelWithString:@"直播视频源（专属直播的数据源，选填）"];
    liveTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    liveTitle.translatesAutoresizingMaskIntoConstraints = NO;

    self.liveConfigURLField = [NSTextField textFieldWithString:@""];
    self.liveConfigURLField.placeholderString = @"请输入直播视频源 URL（选填）";
    self.liveConfigURLField.font = [NSFont systemFontOfSize:16];
    self.liveConfigURLField.controlSize = NSControlSizeLarge;
    self.liveConfigURLField.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *liveValidateButton = [NSButton buttonWithTitle:@"验证" target:self action:@selector(validateLiveURLAction:)];
    liveValidateButton.bezelStyle = NSBezelStyleRounded;
    liveValidateButton.image = [NSImage imageWithSystemSymbolName:@"checkmark.seal" accessibilityDescription:@"验证"];
    liveValidateButton.imagePosition = NSImageLeading;
    liveValidateButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.liveValidationResultLabel = [NSTextField wrappingLabelWithString:@""];
    self.liveValidationResultLabel.font = [NSFont systemFontOfSize:12];
    self.liveValidationResultLabel.textColor = [NSColor secondaryLabelColor];
    self.liveValidationResultLabel.maximumNumberOfLines = 0;
    self.liveValidationResultLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.liveValidationResultLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // ---- 保存 ----
    NSButton *saveButton = [NSButton buttonWithTitle:@"保存并重新加载" target:self action:@selector(saveConfigURLAction:)];
    saveButton.bezelStyle = NSBezelStyleRounded;
    saveButton.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle" accessibilityDescription:@"保存"];
    saveButton.imagePosition = NSImageLeading;
    saveButton.translatesAutoresizingMaskIntoConstraints = NO;

    // ---- 验证进度显示（逐步展示地址格式 / 可访问 / 可解析 / 数据格式校验等详细过程） ----
    self.settingsProgressLabel = [NSTextField wrappingLabelWithString:@""];
    self.settingsProgressLabel.font = [NSFont systemFontOfSize:12];
    self.settingsProgressLabel.textColor = [NSColor secondaryLabelColor];
    self.settingsProgressLabel.maximumNumberOfLines = 0;
    self.settingsProgressLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.settingsProgressLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // ---- 历史记录设置 ----
    NSTextField *historyTitle = [NSTextField labelWithString:@"历史记录"];
    historyTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    historyTitle.translatesAutoresizingMaskIntoConstraints = NO;

    self.historySaveSwitch = [NSButton checkboxWithTitle:@"保存视频播放历史记录" target:self action:@selector(historySaveSwitchChanged:)];
    self.historySaveSwitch.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *historyLimitLabel = [NSTextField labelWithString:@"历史记录保存条数："];
    historyLimitLabel.font = [NSFont systemFontOfSize:13];
    historyLimitLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.historyLimitField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.historyLimitField.font = [NSFont systemFontOfSize:16];
    self.historyLimitField.controlSize = NSControlSizeLarge;
    self.historyLimitField.alignment = NSTextAlignmentCenter;
    self.historyLimitField.delegate = self;
    self.historyLimitField.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *historyLimitUnit = [NSTextField labelWithString:@"条"];
    historyLimitUnit.font = [NSFont systemFontOfSize:13];
    historyLimitUnit.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *playerTitle = [NSTextField labelWithString:@"播放器"];
    playerTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    playerTitle.translatesAutoresizingMaskIntoConstraints = NO;

    self.vlcPlaybackSwitch = [NSButton checkboxWithTitle:@"使用 VLC 视频播放（支持更多视频格式；默认不勾选时使用系统默认播放器）" target:self action:@selector(vlcPlaybackSwitchChanged:)];
    self.vlcPlaybackSwitch.translatesAutoresizingMaskIntoConstraints = NO;

    [container addSubview:title];
    [container addSubview:hintLabel];
    [container addSubview:vodTitle];
    [container addSubview:self.vodConfigURLField];
    [container addSubview:vodValidateButton];
    [container addSubview:self.vodValidationResultLabel];
    [container addSubview:liveTitle];
    [container addSubview:self.liveConfigURLField];
    [container addSubview:liveValidateButton];
    [container addSubview:self.liveValidationResultLabel];
    [container addSubview:saveButton];
    [container addSubview:self.settingsProgressLabel];
    [container addSubview:historyTitle];
    [container addSubview:self.historySaveSwitch];
    [container addSubview:historyLimitLabel];
    [container addSubview:self.historyLimitField];
    [container addSubview:historyLimitUnit];
    [container addSubview:playerTitle];
    [container addSubview:self.vlcPlaybackSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:container.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [hintLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [hintLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [hintLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],

        [vodTitle.topAnchor constraintEqualToAnchor:hintLabel.bottomAnchor constant:18],
        [vodTitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [self.vodConfigURLField.topAnchor constraintEqualToAnchor:vodTitle.bottomAnchor constant:8],
        [self.vodConfigURLField.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [self.vodConfigURLField.trailingAnchor constraintEqualToAnchor:vodValidateButton.leadingAnchor constant:-8],
        [vodValidateButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [vodValidateButton.centerYAnchor constraintEqualToAnchor:self.vodConfigURLField.centerYAnchor],

        [self.vodValidationResultLabel.topAnchor constraintEqualToAnchor:self.vodConfigURLField.bottomAnchor constant:6],
        [self.vodValidationResultLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [self.vodValidationResultLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],

        [liveTitle.topAnchor constraintEqualToAnchor:self.vodValidationResultLabel.bottomAnchor constant:16],
        [liveTitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [self.liveConfigURLField.topAnchor constraintEqualToAnchor:liveTitle.bottomAnchor constant:8],
        [self.liveConfigURLField.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [self.liveConfigURLField.trailingAnchor constraintEqualToAnchor:liveValidateButton.leadingAnchor constant:-8],
        [liveValidateButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [liveValidateButton.centerYAnchor constraintEqualToAnchor:self.liveConfigURLField.centerYAnchor],

        [self.liveValidationResultLabel.topAnchor constraintEqualToAnchor:self.liveConfigURLField.bottomAnchor constant:6],
        [self.liveValidationResultLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [self.liveValidationResultLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],

        [saveButton.topAnchor constraintEqualToAnchor:self.liveValidationResultLabel.bottomAnchor constant:16],
        [saveButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [self.settingsProgressLabel.topAnchor constraintEqualToAnchor:saveButton.bottomAnchor constant:12],
        [self.settingsProgressLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [self.settingsProgressLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],

        [historyTitle.topAnchor constraintEqualToAnchor:self.settingsProgressLabel.bottomAnchor constant:18],
        [historyTitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [self.historySaveSwitch.topAnchor constraintEqualToAnchor:historyTitle.bottomAnchor constant:8],
        [self.historySaveSwitch.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [historyLimitLabel.topAnchor constraintEqualToAnchor:self.historySaveSwitch.bottomAnchor constant:12],
        [historyLimitLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [self.historyLimitField.leadingAnchor constraintEqualToAnchor:historyLimitLabel.trailingAnchor constant:8],
        [self.historyLimitField.centerYAnchor constraintEqualToAnchor:historyLimitLabel.centerYAnchor],
        [self.historyLimitField.widthAnchor constraintEqualToConstant:80],

        [historyLimitUnit.leadingAnchor constraintEqualToAnchor:self.historyLimitField.trailingAnchor constant:6],
        [historyLimitUnit.centerYAnchor constraintEqualToAnchor:self.historyLimitField.centerYAnchor],

        [playerTitle.topAnchor constraintEqualToAnchor:historyLimitLabel.bottomAnchor constant:20],
        [playerTitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [self.vlcPlaybackSwitch.topAnchor constraintEqualToAnchor:playerTitle.bottomAnchor constant:8],
        [self.vlcPlaybackSwitch.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [self.vlcPlaybackSwitch.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
    ]];

    [self loadConfigURLRows];
    [self loadHistorySettings];
    [self loadVLCSetting];
    return container;
}

@end
