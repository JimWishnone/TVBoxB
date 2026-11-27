#import "TVVideoCardViews.h"
#import "Models.h"
#import "TVImageLoader.h"
#import <QuartzCore/QuartzCore.h>

@implementation TVPosterImageView
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}
@end

@implementation TVNonInteractiveLabel
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}
@end

@implementation TVGradientView {
    CAGradientLayer *_gradient;
}

- (instancetype)initWithColors:(NSArray<NSColor *> *)colors {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.wantsLayer = YES;
        _gradient = [CAGradientLayer layer];
        NSMutableArray<id> *cgColors = [NSMutableArray array];
        for (NSColor *color in colors) {
            [cgColors addObject:(id)color.CGColor];
        }
        _gradient.colors = cgColors;
        _gradient.startPoint = CGPointMake(0.5, 1.0);
        _gradient.endPoint = CGPointMake(0.5, 0.0);
        [self.layer addSublayer:_gradient];
    }
    return self;
}

- (void)layout {
    [super layout];
    _gradient.frame = self.bounds;
}

@end

@implementation VODCollectionItem

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 160, 210)];
    root.wantsLayer = YES;
    root.layer.cornerRadius = 6;

    self.posterView = [[TVPosterImageView alloc] init];
    self.posterView.translatesAutoresizingMaskIntoConstraints = NO;
    self.posterView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.posterView.wantsLayer = YES;
    self.posterView.layer.cornerRadius = 6;
    self.posterView.layer.masksToBounds = YES;
    self.posterView.layer.backgroundColor = [NSColor clearColor].CGColor;

    self.titleLabel = [[TVNonInteractiveLabel alloc] initWithFrame:NSZeroRect];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.editable = NO;
    self.titleLabel.selectable = NO;
    self.titleLabel.bordered = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.subtitleLabel = [[TVNonInteractiveLabel alloc] initWithFrame:NSZeroRect];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.editable = NO;
    self.subtitleLabel.selectable = NO;
    self.subtitleLabel.bordered = NO;
    self.subtitleLabel.drawsBackground = NO;
    self.subtitleLabel.font = [NSFont systemFontOfSize:11];
    self.subtitleLabel.textColor = [NSColor secondaryLabelColor];
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.subtitleLabel.maximumNumberOfLines = 2;
    self.subtitleLabel.usesSingleLineMode = NO;
    self.subtitleLabel.cell.wraps = YES;
    self.subtitleLabel.cell.truncatesLastVisibleLine = YES;

    [root addSubview:self.posterView];
    [root addSubview:self.titleLabel];
    [root addSubview:self.subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.posterView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [self.posterView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [self.posterView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [self.posterView.heightAnchor constraintEqualToConstant:150],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.posterView.bottomAnchor constant:6],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:2],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-2],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:2],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-2],
    ]];

    self.view = root;
}

- (void)configureWithVideo:(TVVideo *)video {
    self.titleLabel.stringValue = video.name ?: @"";

    if (video.sourceSite) {
        // 搜索结果：数据源名称 + 共X集，分两行显示
        NSString *sourceName = video.sourceSite.name ?: @"";
        NSInteger total = [video totalEpisodeCount];
        NSString *episodeText = (total > 0) ? [NSString stringWithFormat:@"共%ld集", (long)total] : @"集数未知";
        self.subtitleLabel.stringValue = [NSString stringWithFormat:@"%@\n%@", sourceName, episodeText];
    } else {
        // 点播列表：备注 / 分类
        self.subtitleLabel.stringValue = video.remarks.length > 0 ? video.remarks : (video.typeName ?: @"");
    }

    [self setPosterURL:video.vodPic];
}

+ (NSImage *)defaultPosterImage {
    static NSImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSSize size = NSMakeSize(160, 150);
        image = [[NSImage alloc] initWithSize:size];
        [image lockFocus];
        NSImage *symbol = [NSImage imageWithSystemSymbolName:@"film" accessibilityDescription:@"默认图片"];
        if (symbol) {
            NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:42 weight:NSFontWeightRegular];
            symbol = [symbol imageWithSymbolConfiguration:config];
            NSSize symbolSize = symbol.size;
            NSRect rect = NSMakeRect((size.width - symbolSize.width) / 2.0,
                                     (size.height - symbolSize.height) / 2.0,
                                     symbolSize.width,
                                     symbolSize.height);
            [[NSColor colorWithWhite:0.55 alpha:1.0] set];
            [symbol drawInRect:rect];
        }
        [image unlockFocus];
    });
    return image;
}

- (void)setPosterURL:(NSString *)urlString {
    self.posterURLString = urlString;
    self.posterView.image = [VODCollectionItem defaultPosterImage];

    if (urlString.length == 0) return;
    [TVImageLoader loadImageAtURL:urlString completion:^(NSImage * _Nullable image) {
        if ([self.posterURLString isEqualToString:urlString]) {
            self.posterView.image = image ?: [VODCollectionItem defaultPosterImage];
        }
    }];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    if (selected) {
        self.view.layer.borderWidth = 3.0;
        self.view.layer.borderColor = [NSColor controlAccentColor].CGColor;
    } else {
        self.view.layer.borderWidth = 0.0;
    }
}

@end