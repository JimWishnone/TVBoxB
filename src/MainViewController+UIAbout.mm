#import "MainViewController+Private.h"

@implementation MainViewController (UIAbout)

#pragma mark - 关于页构建

- (NSView *)buildAboutView {
    NSView *container = [[NSView alloc] init];

    TVGradientView *background = [[TVGradientView alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:0.28 green:0.45 blue:0.96 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.58 green:0.38 blue:0.96 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.94 green:0.38 blue:0.62 alpha:1.0],
    ]];
    background.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:background];

    NSTextField *title = [NSTextField labelWithString:@"TVBoxB"];
    title.font = [NSFont systemFontOfSize:28 weight:NSFontWeightBold];
    title.textColor = [NSColor whiteColor];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *version = [NSTextField labelWithString:[NSString stringWithFormat:@"版本 v%@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.0.0"]];
    version.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.85];
    version.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *desc = [NSTextField wrappingLabelWithString:@"基于 macOS 原生界面的视频播放软件，支持视频点播与视频直播功能。\n点播与直播数据均来自 TVbox 官方配置源（official.json）。"];
    desc.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.95];
    desc.translatesAutoresizingMaskIntoConstraints = NO;
    desc.maximumNumberOfLines = 0;
    desc.alignment = NSTextAlignmentCenter;
    desc.preferredMaxLayoutWidth = 280;

    NSTextField *copyright = [NSTextField labelWithString:@"版权所有 © 2026 iGruel.com"];
    copyright.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.70];
    copyright.font = [NSFont systemFontOfSize:12];
    copyright.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *email = [NSTextField labelWithString:@"技术支持邮箱：ibmos_2@163.com"];
    email.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.90];
    email.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *copyEmailButton = [NSButton buttonWithTitle:@"复制" target:self action:@selector(copySupportEmailAction:)];
    copyEmailButton.bezelStyle = NSBezelStyleRounded;
    copyEmailButton.image = [NSImage imageWithSystemSymbolName:@"doc.on.doc" accessibilityDescription:@"复制"];
    copyEmailButton.imagePosition = NSImageLeading;
    copyEmailButton.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *sendEmailButton = [NSButton buttonWithTitle:@"发送邮件" target:self action:@selector(sendSupportEmailAction:)];
    sendEmailButton.bezelStyle = NSBezelStyleRounded;
    sendEmailButton.image = [NSImage imageWithSystemSymbolName:@"envelope" accessibilityDescription:@"发送邮件"];
    sendEmailButton.imagePosition = NSImageLeading;
    sendEmailButton.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *vlcTitle = [NSTextField labelWithString:@"VLC 技术支持"];
    vlcTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    vlcTitle.textColor = [NSColor whiteColor];
    vlcTitle.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *vlcDesc = [NSTextField wrappingLabelWithString:@"本软件集成了 VideoLAN 开源的 libVLC 作为可选的视频播放引擎，以支持更多视频格式。\nlibVLC 由 VideoLAN 团队开发，采用 GNU Lesser General Public License v2.1 许可发布。\n详见 https://www.videolan.org/vlc/libvlc.html"];
    vlcDesc.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.85];
    vlcDesc.font = [NSFont systemFontOfSize:12];
    vlcDesc.alignment = NSTextAlignmentCenter;
    vlcDesc.maximumNumberOfLines = 0;
    vlcDesc.preferredMaxLayoutWidth = 340;
    vlcDesc.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *sponsorTitle = [NSTextField labelWithString:@"资助本软件"];
    sponsorTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    sponsorTitle.textColor = [NSColor whiteColor];
    sponsorTitle.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *sponsorDesc = [NSTextField wrappingLabelWithString:@"本软件免费开放使用。如果你觉得它给你带来便利，欢迎自愿赞助。赞助没有强制回报，仅作为对开发者的支持。\n你的赞助将助力持续维护、修复问题、开发新功能，基础功能不会因为未赞助而受限。"];
    sponsorDesc.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.95];
    sponsorDesc.font = [NSFont systemFontOfSize:13];
    sponsorDesc.alignment = NSTextAlignmentCenter;
    sponsorDesc.maximumNumberOfLines = 0;
    sponsorDesc.preferredMaxLayoutWidth = 340;
    sponsorDesc.translatesAutoresizingMaskIntoConstraints = NO;

    NSImage *qrImage = [self makeQRCodeImageFromString:@"wxp://f2f0-2JekJo3N4tu0w0wgTfT6mhZWPS6nUPqvEdleDRmLoe_elQPPWMFoZyn0MxfI5eI" size:150];

    NSImageView *qrCodeView = [[NSImageView alloc] init];
    qrCodeView.image = qrImage;
    qrCodeView.imageScaling = NSImageScaleProportionallyUpOrDown;
    qrCodeView.wantsLayer = YES;
    qrCodeView.layer.backgroundColor = [NSColor whiteColor].CGColor;
    qrCodeView.layer.cornerRadius = 10;
    qrCodeView.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *sponsor = [NSTextField labelWithString:@"请使用微信扫码资助本软件"];
    sponsor.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.90];
    sponsor.translatesAutoresizingMaskIntoConstraints = NO;

    [container addSubview:title];
    [container addSubview:version];
    [container addSubview:desc];
    [container addSubview:copyright];
    [container addSubview:email];
    [container addSubview:copyEmailButton];
    [container addSubview:sendEmailButton];
    [container addSubview:vlcTitle];
    [container addSubview:vlcDesc];
    [container addSubview:sponsorTitle];
    [container addSubview:sponsorDesc];
    [container addSubview:qrCodeView];
    [container addSubview:sponsor];

    [NSLayoutConstraint activateConstraints:@[
        [background.topAnchor constraintEqualToAnchor:container.topAnchor],
        [background.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [background.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [background.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [title.topAnchor constraintEqualToAnchor:container.topAnchor constant:60],
        [title.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],

        [version.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [version.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],

        [desc.topAnchor constraintEqualToAnchor:version.bottomAnchor constant:20],
        [desc.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:40],
        [desc.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-40],

        [copyright.topAnchor constraintEqualToAnchor:desc.bottomAnchor constant:20],
        [copyright.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],

        [email.topAnchor constraintEqualToAnchor:copyright.bottomAnchor constant:8],
        [email.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],

        [copyEmailButton.topAnchor constraintEqualToAnchor:email.bottomAnchor constant:6],
        [copyEmailButton.trailingAnchor constraintEqualToAnchor:container.centerXAnchor constant:-4],
        [sendEmailButton.topAnchor constraintEqualToAnchor:email.bottomAnchor constant:6],
        [sendEmailButton.leadingAnchor constraintEqualToAnchor:container.centerXAnchor constant:4],

        [vlcTitle.topAnchor constraintEqualToAnchor:copyEmailButton.bottomAnchor constant:20],
        [vlcTitle.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],

        [vlcDesc.topAnchor constraintEqualToAnchor:vlcTitle.bottomAnchor constant:6],
        [vlcDesc.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:40],
        [vlcDesc.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-40],

        [sponsorTitle.topAnchor constraintEqualToAnchor:vlcDesc.bottomAnchor constant:18],
        [sponsorTitle.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],

        [sponsorDesc.topAnchor constraintEqualToAnchor:sponsorTitle.bottomAnchor constant:8],
        [sponsorDesc.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:40],
        [sponsorDesc.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-40],

        [qrCodeView.topAnchor constraintEqualToAnchor:sponsorDesc.bottomAnchor constant:12],
        [qrCodeView.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [qrCodeView.widthAnchor constraintEqualToConstant:150],
        [qrCodeView.heightAnchor constraintEqualToConstant:150],

        [sponsor.topAnchor constraintEqualToAnchor:qrCodeView.bottomAnchor constant:8],
        [sponsor.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
    ]];
    return container;
}

@end
