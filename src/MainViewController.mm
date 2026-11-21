#import "MainViewController.h"
#import "ConfigManager.h"
#import "PlayerViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

static NSString *const kVODItemIdentifier = @"VODItemIdentifier";
static NSString *const kTVBoxHistoryKey = @"TVBoxHistory";
static NSString *const kTVBoxSearchKeywordsKey = @"TVBoxSearchKeywords";
static const NSUInteger kTVBoxHistoryLimit = 30;
static const NSUInteger kTVBoxSearchKeywordsLimit = 12;

@interface TVPosterImageView : NSImageView
@end
@implementation TVPosterImageView
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}
@end

@interface TVNonInteractiveLabel : NSTextField
@end
@implementation TVNonInteractiveLabel
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}
@end

// 渐变背景视图：使用 CAGradientLayer 绘制上下渐变色，用于增强界面视觉效果。
@interface TVGradientView : NSView
- (instancetype)initWithColors:(NSArray<NSColor *> *)colors;
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

static NSString *TVFirstCharacter(NSString *name) {
    if (name.length == 0) return @"?";
    NSRange range = [name rangeOfComposedCharacterSequenceAtIndex:0];
    return [name substringWithRange:range];
}

static NSImage *TVLetterIcon(NSString *name) {
    NSString *letter = TVFirstCharacter(name);
    NSSize size = NSMakeSize(24, 24);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, size.width, size.height)];
    [[NSColor controlAccentColor] setFill];
    [circle fill];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
    NSSize letterSize = [letter sizeWithAttributes:attrs];
    [letter drawAtPoint:NSMakePoint((size.width - letterSize.width) / 2.0,
                                    (size.height - letterSize.height) / 2.0)
         withAttributes:attrs];
    [image unlockFocus];
    return image;
}

static NSLayoutConstraint *TVSoftMinWidthConstraint(NSLayoutDimension *dimension, CGFloat minimum) {
    NSLayoutConstraint *constraint = [dimension constraintGreaterThanOrEqualToConstant:minimum];
    constraint.priority = NSLayoutPriorityDefaultHigh;
    return constraint;
}

// 降低视图水平方向的内容压缩抗性。fittingSize 以 NSLayoutPriorityFittingSizeCompression(50)
// 作为约束求解优先级，因此压缩抗性必须低于该值，控件的固有宽度才不会锁死窗口最小宽度。
static void TVAllowHorizontalCompression(NSView *view) {
    [view setContentCompressionResistancePriority:(NSLayoutPriorityFittingSizeCompression - 1)
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
}

// 计算两个字符串的编辑距离（Levenshtein），用于搜索结果相似度排序
static NSUInteger TVLevenshteinDistance(NSString *a, NSString *b) {
    NSUInteger lenA = a.length;
    NSUInteger lenB = b.length;
    if (lenA == 0) return lenB;
    if (lenB == 0) return lenA;

    NSUInteger *prev = (NSUInteger *)calloc(lenB + 1, sizeof(NSUInteger));
    NSUInteger *curr = (NSUInteger *)calloc(lenB + 1, sizeof(NSUInteger));
    for (NSUInteger j = 0; j <= lenB; j++) prev[j] = j;

    for (NSUInteger i = 1; i <= lenA; i++) {
        curr[0] = i;
        unichar ca = [a characterAtIndex:i - 1];
        for (NSUInteger j = 1; j <= lenB; j++) {
            unichar cb = [b characterAtIndex:j - 1];
            NSUInteger cost = (ca == cb) ? 0 : 1;
            NSUInteger deletion = prev[j] + 1;
            NSUInteger insertion = curr[j - 1] + 1;
            NSUInteger substitution = prev[j - 1] + cost;
            curr[j] = MIN(MIN(deletion, insertion), substitution);
        }
        NSUInteger *tmp = prev;
        prev = curr;
        curr = tmp;
    }
    NSUInteger result = prev[lenB];
    free(prev);
    free(curr);
    return result;
}

@interface TVLiveIconCell : NSTableCellView
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, copy) NSString *channelKey;
@end

@implementation TVLiveIconCell
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _iconView = [[NSImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_iconView];
        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:24],
            [_iconView.heightAnchor constraintEqualToConstant:24],
        ]];
    }
    return self;
}
@end

@interface VODCollectionItem : NSCollectionViewItem
@property (nonatomic, copy) NSString *posterURLString;
@property (nonatomic, strong) NSImageView *posterView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
- (void)configureWithVideo:(TVVideo *)video;
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
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSImage *image = nil;
        if (!error && data) {
            image = [[NSImage alloc] initWithData:data];
        }
        NSImage *finalImage = image ?: [VODCollectionItem defaultPosterImage];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.posterURLString isEqualToString:urlString]) {
                self.posterView.image = finalImage;
            }
        });
    }];
    [task resume];
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

@interface MainViewController () <NSTableViewDataSource, NSTableViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, NSSearchFieldDelegate>

@property (nonatomic, strong) ConfigManager *config;

@property (nonatomic, strong) NSTableView *sidebar;
@property (nonatomic, strong) NSArray<NSString *> *sidebarItems;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) NSView *dataSourcesView;
@property (nonatomic, strong) NSView *searchView;
@property (nonatomic, strong) NSView *vodView;
@property (nonatomic, strong) NSView *liveView;
@property (nonatomic, strong) NSView *historyView;
@property (nonatomic, strong) NSView *settingsView;
@property (nonatomic, strong) NSView *aboutView;
@property (nonatomic, strong) NSArray<NSView *> *contentViews;
@property (nonatomic, strong) NSArray<NSArray<NSLayoutConstraint *> *> *contentViewPinConstraints;

@property (nonatomic, strong) NSTableView *sourcesTable;
@property (nonatomic, strong) NSArray<NSDictionary *> *sourceRows;
@property (nonatomic, strong) NSMutableSet<NSString *> *unavailableSourceURLs;
@property (nonatomic, strong) NSWindow *checkingPanel;
@property (nonatomic, assign) NSInteger availabilityCheckGeneration;

@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSCollectionView *searchCollectionView;
@property (nonatomic, strong) NSArray<TVVideo *> *searchResults;
@property (nonatomic, strong) NSTimer *searchTimer;
@property (nonatomic, assign) NSInteger searchGeneration;
@property (nonatomic, strong) NSMutableArray<NSString *> *searchKeywords;
@property (nonatomic, strong) NSScrollView *searchKeywordsScroll;
@property (nonatomic, strong) NSView *searchKeywordsBar;
@property (nonatomic, strong) NSLayoutConstraint *searchKeywordsHeightConstraint;

@property (nonatomic, strong) NSPopUpButton *sitePopup;
@property (nonatomic, strong) NSSearchField *vodSearchField;
@property (nonatomic, strong) NSScrollView *categoryScroll;
@property (nonatomic, strong) NSView *categoryContentView;
@property (nonatomic, strong) NSCollectionView *vodCollectionView;
@property (nonatomic, strong) NSScrollView *vodScrollView;
@property (nonatomic, strong) NSArray<TVCategory *> *categories;
@property (nonatomic, strong) NSArray<TVVideo *> *videos;
@property (nonatomic, assign) NSInteger selectedCategoryId;
@property (nonatomic, assign) NSInteger vodPage;
@property (nonatomic, assign) BOOL vodHasMore;
@property (nonatomic, assign) BOOL vodLoadingMore;
@property (nonatomic, copy) NSString *vodSearchKeyword;

@property (nonatomic, strong) NSPopUpButton *liveSourcePopup;
@property (nonatomic, strong) NSPopUpButton *liveGroupPopup;
@property (nonatomic, strong) NSSearchField *liveSearchField;
@property (nonatomic, strong) NSTableView *liveTable;
@property (nonatomic, strong) NSArray<TVLiveChannel *> *liveChannels;
@property (nonatomic, strong) NSArray<TVLiveChannel *> *displayedLiveChannels;
@property (nonatomic, copy) NSSortDescriptor *liveSortDescriptor;

@property (nonatomic, strong) NSTextField *vodConfigURLField;
@property (nonatomic, strong) NSTextField *liveConfigURLField;

@property (nonatomic, strong) NSTableView *historyTable;
@property (nonatomic, strong) NSMutableArray<TVHistoryItem *> *historyItems;
@property (nonatomic, strong) TVHistoryItem *currentHistoryItem;

@property (nonatomic, strong) NSWindow *playerWindow;
@property (nonatomic, strong) NSTextField *statusLabel;

// 视频详情模态窗口（点播列表点击后展示介绍信息与可播放列表）
@property (nonatomic, strong) NSWindow *detailModalWindow;
@property (nonatomic, strong) NSPopUpButton *detailModalLinePopup;
@property (nonatomic, strong) NSPopUpButton *detailModalEpisodePopup;
@property (nonatomic, strong) TVVideo *detailModalVideo;
@property (nonatomic, strong) TVSite *detailModalSite;

@end

@implementation MainViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1080, 700)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.config = [ConfigManager sharedManager];
    self.videos = @[];
    self.searchResults = @[];
    self.liveChannels = @[];
    self.displayedLiveChannels = @[];
    self.sourceRows = @[];
    self.unavailableSourceURLs = [NSMutableSet set];
    self.selectedCategoryId = 0;
    self.historyItems = [NSMutableArray array];

    [self buildUI];
    [self loadHistory];
    [self loadSearchKeywords];
    [self rebuildSearchKeywordsBar];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleReloadConfig:)
                                                 name:@"TVBoxReloadConfig"
                                               object:nil];
    [self reloadConfig];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI 构建

- (void)buildUI {
    NSView *root = self.view;

    self.sidebarItems = @[@"TVBox数据源列表", @"搜索", @"点播", @"直播", @"历史", @"设置", @"关于"];
    [self buildSidebar];
    self.dataSourcesView = [self buildDataSourcesView];
    self.searchView = [self buildSearchView];
    self.vodView = [self buildVODView];
    self.liveView = [self buildLiveView];
    self.historyView = [self buildHistoryView];
    self.settingsView = [self buildSettingsView];
    self.aboutView = [self buildAboutView];

    self.contentContainer = [[NSView alloc] init];
    self.contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.contentContainer];

    self.contentViews = @[self.dataSourcesView, self.searchView, self.vodView,
                          self.liveView, self.historyView, self.settingsView, self.aboutView];
    NSMutableArray<NSArray<NSLayoutConstraint *> *> *pinSets = [NSMutableArray array];
    for (NSView *view in self.contentViews) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentContainer addSubview:view];
        NSArray<NSLayoutConstraint *> *pins = @[
            [view.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
            [view.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
            [view.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
            [view.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
        ];
        [pinSets addObject:pins];
    }
    self.contentViewPinConstraints = pinSets;

    // 侧边栏使用彩色渐变色背景，提升视觉效果，同时保持默认 macOS 界面风格。
    TVGradientView *sidebarBackground = [[TVGradientView alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:0.80 green:0.86 blue:0.98 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.98 green:0.86 blue:0.96 alpha:1.0],
    ]];
    sidebarBackground.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:sidebarBackground];

    NSScrollView *sidebarScroll = [[NSScrollView alloc] init];
    sidebarScroll.translatesAutoresizingMaskIntoConstraints = NO;
    sidebarScroll.documentView = self.sidebar;
    sidebarScroll.hasVerticalScroller = YES;
    sidebarScroll.drawsBackground = NO;
    [root addSubview:sidebarScroll];

    NSView *separator = [[NSView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.wantsLayer = YES;
    separator.layer.backgroundColor = [NSColor separatorColor].CGColor;
    [root addSubview:separator];

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.font = [NSFont systemFontOfSize:12];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    TVAllowHorizontalCompression(self.statusLabel);
    [root addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [sidebarBackground.topAnchor constraintEqualToAnchor:root.topAnchor],
        [sidebarBackground.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [sidebarBackground.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [sidebarBackground.widthAnchor constraintEqualToConstant:200],

        [sidebarScroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [sidebarScroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [sidebarScroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [sidebarScroll.widthAnchor constraintEqualToConstant:200],

        [separator.topAnchor constraintEqualToAnchor:root.topAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:sidebarScroll.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [separator.widthAnchor constraintEqualToConstant:1],

        [self.contentContainer.topAnchor constraintEqualToAnchor:root.topAnchor],
        [self.contentContainer.leadingAnchor constraintEqualToAnchor:separator.trailingAnchor],
        [self.contentContainer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [self.contentContainer.bottomAnchor constraintEqualToAnchor:self.statusLabel.topAnchor constant:-2],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:12],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-12],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-6],
    ]];

    [self.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self showContentViewAtIndex:0];
}

- (void)buildSidebar {
    self.sidebar = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.sidebar.identifier = @"sidebar";
    self.sidebar.dataSource = self;
    self.sidebar.delegate = self;
    self.sidebar.headerView = nil;
    self.sidebar.rowSizeStyle = NSTableViewRowSizeStyleLarge;
    self.sidebar.style = NSTableViewStyleSourceList;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"sidebar"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [self.sidebar addTableColumn:column];
}

- (NSView *)buildDataSourcesView {
    NSView *container = [[NSView alloc] init];

    NSTextField *title = [NSTextField labelWithString:@"TVBox数据源列表"];
    title.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *refreshButton = [NSButton buttonWithTitle:@"刷新" target:self action:@selector(refreshDataSourcesAction:)];
    refreshButton.bezelStyle = NSBezelStyleRounded;
    refreshButton.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"刷新"];
    refreshButton.imagePosition = NSImageLeading;
    refreshButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.sourcesTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.sourcesTable.identifier = @"sources";
    self.sourcesTable.dataSource = self;
    self.sourcesTable.delegate = self;
    self.sourcesTable.usesAlternatingRowBackgroundColors = YES;
    self.sourcesTable.allowsColumnResizing = YES;
    self.sourcesTable.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    self.sourcesTable.target = self;
    self.sourcesTable.doubleAction = @selector(sourceRowDoubleClicked:);

    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = @"名称";
    nameCol.width = 220;
    nameCol.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    NSTableColumn *typeCol = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeCol.title = @"类型";
    typeCol.width = 80;
    typeCol.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    NSTableColumn *urlCol = [[NSTableColumn alloc] initWithIdentifier:@"url"];
    urlCol.title = @"地址";
    urlCol.width = 520;
    urlCol.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    NSTableColumn *statusCol = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    statusCol.title = @"可用";
    statusCol.width = 80;
    statusCol.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    [self.sourcesTable addTableColumn:nameCol];
    [self.sourcesTable addTableColumn:typeCol];
    [self.sourcesTable addTableColumn:urlCol];
    [self.sourcesTable addTableColumn:statusCol];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = self.sourcesTable;

    [container addSubview:title];
    [container addSubview:refreshButton];
    [container addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],

        [refreshButton.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [refreshButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],

        [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [scroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [scroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
        [scroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12],
    ]];
    return container;
}

- (NSView *)buildSearchView {
    NSView *container = [[NSView alloc] init];

    self.searchField = [[NSSearchField alloc] init];
    self.searchField.placeholderString = @"搜索片名（在所有数据源中）";
    self.searchField.font = [NSFont systemFontOfSize:16];
    self.searchField.controlSize = NSControlSizeLarge;
    self.searchField.delegate = self;
    [self.searchField setTarget:self];
    [self.searchField setAction:@selector(searchAction:)];

    NSButton *searchButton = [NSButton buttonWithTitle:@"搜索" target:self action:@selector(searchAction:)];
    searchButton.bezelStyle = NSBezelStyleRounded;
    searchButton.image = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:@"搜索"];
    searchButton.imagePosition = NSImageLeading;

    NSStackView *toolbar = [NSStackView stackViewWithViews:@[self.searchField, searchButton]];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 8;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    TVAllowHorizontalCompression(self.searchField);
    TVAllowHorizontalCompression(toolbar);

    self.searchCollectionView = [self makeCollectionView];
    NSScrollView *gridScroll = [self makeScrollViewForCollectionView:self.searchCollectionView];

    // 搜索关键词历史条（可点击回填、可删除）
    self.searchKeywordsScroll = [[NSScrollView alloc] init];
    self.searchKeywordsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchKeywordsScroll.hasVerticalScroller = NO;
    self.searchKeywordsScroll.hasHorizontalScroller = YES;
    self.searchKeywordsScroll.autohidesScrollers = YES;
    self.searchKeywordsScroll.drawsBackground = NO;
    self.searchKeywordsBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, 34)];
    self.searchKeywordsScroll.documentView = self.searchKeywordsBar;

    [container addSubview:toolbar];
    [container addSubview:self.searchKeywordsScroll];
    [container addSubview:gridScroll];

    self.searchKeywordsHeightConstraint = [self.searchKeywordsScroll.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [toolbar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [toolbar.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-12],

        TVSoftMinWidthConstraint(self.searchField.widthAnchor, 100),

        [self.searchKeywordsScroll.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:8],
        [self.searchKeywordsScroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [self.searchKeywordsScroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
        self.searchKeywordsHeightConstraint,

        [gridScroll.topAnchor constraintEqualToAnchor:self.searchKeywordsScroll.bottomAnchor constant:8],
        [gridScroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [gridScroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [gridScroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    return container;
}

- (NSView *)buildVODView {
    NSView *container = [[NSView alloc] init];

    NSTextField *siteLabel = [NSTextField labelWithString:@"站点:"];
    self.sitePopup = [[NSPopUpButton alloc] init];
    [self.sitePopup setTarget:self];
    [self.sitePopup setAction:@selector(siteChanged:)];

    self.vodSearchField = [[NSSearchField alloc] init];
    self.vodSearchField.placeholderString = @"在所选数据源中搜索";
    self.vodSearchField.font = [NSFont systemFontOfSize:16];
    self.vodSearchField.controlSize = NSControlSizeLarge;
    [self.vodSearchField setTarget:self];
    [self.vodSearchField setAction:@selector(vodSearchAction:)];

    NSButton *vodSearchButton = [NSButton buttonWithTitle:@"搜索" target:self action:@selector(vodSearchAction:)];
    vodSearchButton.bezelStyle = NSBezelStyleRounded;
    vodSearchButton.image = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:@"搜索"];
    vodSearchButton.imagePosition = NSImageLeading;

    NSStackView *toolbar = [NSStackView stackViewWithViews:@[siteLabel, self.sitePopup, self.vodSearchField, vodSearchButton]];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 8;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    TVAllowHorizontalCompression(self.sitePopup);
    TVAllowHorizontalCompression(self.vodSearchField);
    TVAllowHorizontalCompression(toolbar);

    self.categoryScroll = [[NSScrollView alloc] init];
    self.categoryScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.categoryScroll.hasVerticalScroller = NO;
    self.categoryScroll.hasHorizontalScroller = YES;
    self.categoryScroll.drawsBackground = NO;
    self.categoryContentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, 40)];
    self.categoryScroll.documentView = self.categoryContentView;

    self.vodCollectionView = [self makeCollectionView];
    self.vodScrollView = [self makeScrollViewForCollectionView:self.vodCollectionView];
    NSScrollView *gridScroll = self.vodScrollView;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(vodScrollDidScroll:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:self.vodScrollView.contentView];

    [container addSubview:toolbar];
    [container addSubview:self.categoryScroll];
    [container addSubview:gridScroll];

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [toolbar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [toolbar.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-12],

        TVSoftMinWidthConstraint(self.sitePopup.widthAnchor, 80),
        TVSoftMinWidthConstraint(self.vodSearchField.widthAnchor, 80),

        [self.categoryScroll.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:8],
        [self.categoryScroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.categoryScroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.categoryScroll.heightAnchor constraintEqualToConstant:44],

        [gridScroll.topAnchor constraintEqualToAnchor:self.categoryScroll.bottomAnchor constant:8],
        [gridScroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [gridScroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [gridScroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    return container;
}

- (NSView *)buildLiveView {
    NSView *container = [[NSView alloc] init];

    NSTextField *title = [NSTextField labelWithString:@"直播频道"];
    title.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *reloadButton = [NSButton buttonWithTitle:@"刷新" target:self action:@selector(reloadLiveAction:)];
    reloadButton.bezelStyle = NSBezelStyleRounded;
    reloadButton.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"刷新"];
    reloadButton.imagePosition = NSImageLeading;
    reloadButton.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *sourceLabel = [NSTextField labelWithString:@"直播源:"];
    self.liveSourcePopup = [[NSPopUpButton alloc] init];
    [self.liveSourcePopup setTarget:self];
    [self.liveSourcePopup setAction:@selector(liveSourceChanged:)];

    NSTextField *groupLabel = [NSTextField labelWithString:@"分组:"];
    self.liveGroupPopup = [[NSPopUpButton alloc] init];
    [self.liveGroupPopup setTarget:self];
    [self.liveGroupPopup setAction:@selector(liveGroupChanged:)];
    [self.liveGroupPopup addItemWithTitle:@"全部分组"];

    self.liveSearchField = [[NSSearchField alloc] init];
    self.liveSearchField.placeholderString = @"按频道名称查找";
    self.liveSearchField.font = [NSFont systemFontOfSize:16];
    self.liveSearchField.controlSize = NSControlSizeLarge;
    self.liveSearchField.sendsSearchStringImmediately = YES;
    self.liveSearchField.target = self;
    self.liveSearchField.action = @selector(liveSearchChanged:);

    NSStackView *toolbar = [NSStackView stackViewWithViews:@[sourceLabel, self.liveSourcePopup, groupLabel, self.liveGroupPopup, self.liveSearchField]];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 8;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    TVAllowHorizontalCompression(self.liveSourcePopup);
    TVAllowHorizontalCompression(self.liveGroupPopup);
    TVAllowHorizontalCompression(self.liveSearchField);
    TVAllowHorizontalCompression(toolbar);

    self.liveTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.liveTable.identifier = @"live";
    self.liveTable.dataSource = self;
    self.liveTable.delegate = self;
    self.liveTable.usesAlternatingRowBackgroundColors = YES;
    self.liveTable.rowHeight = 32;
    self.liveTable.target = self;
    self.liveTable.doubleAction = @selector(liveRowDoubleClicked:);
    self.liveTable.allowsColumnResizing = YES;
    self.liveTable.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

    NSTableColumn *iconColumn = [[NSTableColumn alloc] initWithIdentifier:@"icon"];
    iconColumn.title = @"";
    iconColumn.width = 36;
    iconColumn.minWidth = 36;
    iconColumn.maxWidth = 36;
    iconColumn.resizingMask = NSTableColumnNoResizing;

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"channel"];
    nameColumn.title = @"频道";
    nameColumn.width = 320;
    nameColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    nameColumn.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];

    NSTableColumn *groupColumn = [[NSTableColumn alloc] initWithIdentifier:@"group"];
    groupColumn.title = @"分组";
    groupColumn.width = 200;
    groupColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    groupColumn.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:@"group" ascending:YES];

    NSTableColumn *sourceColumn = [[NSTableColumn alloc] initWithIdentifier:@"sources"];
    sourceColumn.title = @"数据源来源";
    sourceColumn.width = 240;
    sourceColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    sourceColumn.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:@"sourceNames" ascending:YES];

    NSTableColumn *linesColumn = [[NSTableColumn alloc] initWithIdentifier:@"lines"];
    linesColumn.title = @"线路";
    linesColumn.width = 80;
    linesColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    linesColumn.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:@"lines.@count" ascending:YES];

    [self.liveTable addTableColumn:iconColumn];
    [self.liveTable addTableColumn:nameColumn];
    [self.liveTable addTableColumn:groupColumn];
    [self.liveTable addTableColumn:sourceColumn];
    [self.liveTable addTableColumn:linesColumn];

    NSScrollView *tableScroll = [[NSScrollView alloc] init];
    tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    tableScroll.hasVerticalScroller = YES;
    tableScroll.autohidesScrollers = YES;
    tableScroll.documentView = self.liveTable;

    [container addSubview:title];
    [container addSubview:reloadButton];
    [container addSubview:toolbar];
    [container addSubview:tableScroll];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],

        [reloadButton.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [reloadButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],

        [toolbar.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [toolbar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [toolbar.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-12],

        TVSoftMinWidthConstraint(self.liveSourcePopup.widthAnchor, 80),
        TVSoftMinWidthConstraint(self.liveGroupPopup.widthAnchor, 60),
        TVSoftMinWidthConstraint(self.liveSearchField.widthAnchor, 80),

        [tableScroll.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:10],
        [tableScroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [tableScroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
        [tableScroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12],
    ]];
    return container;
}

- (NSView *)buildHistoryView {
    NSView *container = [[NSView alloc] init];

    NSTextField *title = [NSTextField labelWithString:@"历史记录"];
    title.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *clearButton = [NSButton buttonWithTitle:@"清空" target:self action:@selector(clearHistoryAction:)];
    clearButton.bezelStyle = NSBezelStyleRounded;
    clearButton.image = [NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:@"清空"];
    clearButton.imagePosition = NSImageLeading;
    clearButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.historyTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.historyTable.identifier = @"history";
    self.historyTable.dataSource = self;
    self.historyTable.delegate = self;
    self.historyTable.usesAlternatingRowBackgroundColors = YES;
    self.historyTable.rowHeight = 36;
    self.historyTable.allowsColumnResizing = YES;
    self.historyTable.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    self.historyTable.target = self;
    self.historyTable.doubleAction = @selector(historyRowDoubleClicked:);

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"名称";
    nameColumn.width = 260;
    nameColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;

    NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeColumn.title = @"类型";
    typeColumn.width = 70;
    typeColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;

    NSTableColumn *detailColumn = [[NSTableColumn alloc] initWithIdentifier:@"detail"];
    detailColumn.title = @"记录详情";
    detailColumn.width = 420;
    detailColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;

    NSTableColumn *progressColumn = [[NSTableColumn alloc] initWithIdentifier:@"progress"];
    progressColumn.title = @"播放进度";
    progressColumn.width = 100;
    progressColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;

    NSTableColumn *dateColumn = [[NSTableColumn alloc] initWithIdentifier:@"date"];
    dateColumn.title = @"播放时间";
    dateColumn.width = 150;
    dateColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;

    [self.historyTable addTableColumn:nameColumn];
    [self.historyTable addTableColumn:typeColumn];
    [self.historyTable addTableColumn:detailColumn];
    [self.historyTable addTableColumn:progressColumn];
    [self.historyTable addTableColumn:dateColumn];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = self.historyTable;

    [container addSubview:title];
    [container addSubview:clearButton];
    [container addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],

        [clearButton.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [clearButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],

        [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [scroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [scroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
        [scroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12],
    ]];
    return container;
}

- (NSView *)buildSettingsView {
    NSView *container = [[NSView alloc] init];

    NSTextField *title = [NSTextField labelWithString:@"设置"];
    title.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *hintLabel = [NSTextField labelWithString:@"视频数据源分为两个部分：点播数据源（主数据源，必填）与直播视频源（专属直播的数据源，选填）。点播数据源仅支持填写一个 URL，保存前会进行可访问、可解析验证；若该地址包含直播数据源，可从中选择一个保存到直播数据源。修改后点击「保存并重新加载」立即生效。"];
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

    // ---- 直播视频源（专属直播的数据源，选填） ----
    NSTextField *liveTitle = [NSTextField labelWithString:@"直播视频源（专属直播的数据源，选填）"];
    liveTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    liveTitle.translatesAutoresizingMaskIntoConstraints = NO;

    self.liveConfigURLField = [NSTextField textFieldWithString:@""];
    self.liveConfigURLField.placeholderString = @"请输入直播视频源 URL（选填）";
    self.liveConfigURLField.font = [NSFont systemFontOfSize:16];
    self.liveConfigURLField.controlSize = NSControlSizeLarge;
    self.liveConfigURLField.translatesAutoresizingMaskIntoConstraints = NO;

    // ---- 保存 ----
    NSButton *saveButton = [NSButton buttonWithTitle:@"保存并重新加载" target:self action:@selector(saveConfigURLAction:)];
    saveButton.bezelStyle = NSBezelStyleRounded;
    saveButton.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle" accessibilityDescription:@"保存"];
    saveButton.imagePosition = NSImageLeading;
    saveButton.translatesAutoresizingMaskIntoConstraints = NO;

    [container addSubview:title];
    [container addSubview:hintLabel];
    [container addSubview:vodTitle];
    [container addSubview:self.vodConfigURLField];
    [container addSubview:liveTitle];
    [container addSubview:self.liveConfigURLField];
    [container addSubview:saveButton];

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
        [self.vodConfigURLField.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],

        [liveTitle.topAnchor constraintEqualToAnchor:self.vodConfigURLField.bottomAnchor constant:20],
        [liveTitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [self.liveConfigURLField.topAnchor constraintEqualToAnchor:liveTitle.bottomAnchor constant:8],
        [self.liveConfigURLField.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [self.liveConfigURLField.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],

        [saveButton.topAnchor constraintEqualToAnchor:self.liveConfigURLField.bottomAnchor constant:16],
        [saveButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
    ]];

    [self loadConfigURLRows];
    return container;
}

- (NSView *)buildAboutView {
    NSView *container = [[NSView alloc] init];

    // 关于页使用彩色渐变色背景，增强视觉冲击力。
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

    NSTextField *version = [NSTextField labelWithString:@"版本 v0.0.1"];
    version.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.85];
    version.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *desc = [NSTextField wrappingLabelWithString:@"基于 macOS 原生界面的视频播放软件，支持视频点播与视频直播功能。\n点播与直播数据均来自 TVbox 官方配置源（official.json）。"];
    desc.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.95];
    desc.translatesAutoresizingMaskIntoConstraints = NO;
    desc.maximumNumberOfLines = 0;
    desc.alignment = NSTextAlignmentCenter;
    desc.preferredMaxLayoutWidth = 280;

    // 版权信息
    NSTextField *copyright = [NSTextField labelWithString:@"版权所有 © 2026 iGruel.com"];
    copyright.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.70];
    copyright.font = [NSFont systemFontOfSize:12];
    copyright.translatesAutoresizingMaskIntoConstraints = NO;

    // 支持邮箱（可点击复制或发送邮件）
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

    // 资助本软件（微信扫码）
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

        [sponsorTitle.topAnchor constraintEqualToAnchor:copyEmailButton.bottomAnchor constant:24],
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

// 使用 Core Image 生成指定字符串的二维码图片。
- (NSImage *)makeQRCodeImageFromString:(NSString *)string size:(CGFloat)size {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *outputImage = filter.outputImage;
    if (!outputImage) {
        return nil;
    }

    CGRect extent = outputImage.extent;
    CGFloat scaleX = size / CGRectGetWidth(extent);
    CGFloat scaleY = size / CGRectGetHeight(extent);
    CIImage *scaled = [outputImage imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)];

    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:scaled fromRect:scaled.extent];
    if (!cgImage) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithCGImage:cgImage size:NSMakeSize(size, size)];
    CGImageRelease(cgImage);
    return image;
}

- (NSCollectionView *)makeCollectionView {
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.itemSize = NSMakeSize(160, 210);
    layout.sectionInset = NSEdgeInsetsMake(12, 12, 12, 12);
    layout.minimumLineSpacing = 12;
    layout.minimumInteritemSpacing = 12;

    NSCollectionView *collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    collectionView.collectionViewLayout = layout;
    collectionView.dataSource = self;
    collectionView.delegate = self;
    collectionView.selectable = YES;
    collectionView.backgroundColors = @[[NSColor windowBackgroundColor]];
    [collectionView registerClass:[VODCollectionItem class] forItemWithIdentifier:kVODItemIdentifier];
    return collectionView;
}

- (NSScrollView *)makeScrollViewForCollectionView:(NSCollectionView *)collectionView {
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = collectionView;
    return scroll;
}

- (void)showContentViewAtIndex:(NSInteger)index {
    for (NSInteger i = 0; i < (NSInteger)self.contentViews.count; i++) {
        BOOL active = (i == index);
        NSView *view = self.contentViews[i];
        view.hidden = !active;
        for (NSLayoutConstraint *constraint in self.contentViewPinConstraints[i]) {
            constraint.active = active;
        }
    }
}

- (NSImage *)sidebarIconForRow:(NSInteger)row {
    NSArray<NSString *> *symbols = @[@"list.bullet",
                                     @"magnifyingglass",
                                     @"play.rectangle",
                                     @"dot.radiowaves.left.and.right",
                                     @"clock",
                                     @"gearshape",
                                     @"info.circle"];
    if (row >= 0 && row < (NSInteger)symbols.count) {
        return [NSImage imageWithSystemSymbolName:symbols[row] accessibilityDescription:self.sidebarItems[row]];
    }
    return nil;
}

#pragma mark - 配置加载

- (void)handleReloadConfig:(NSNotification *)notification {
    [self reloadConfig];
}

- (void)reloadConfig {
    [self setStatus:@"正在加载配置…"];
    [self.config loadConfigWithCompletion:^(NSError * _Nullable error) {
        if (error) {
            [self setStatus:[NSString stringWithFormat:@"配置加载失败：%@", error.localizedDescription]];
            return;
        }
        [self setStatus:@""];
        [self.unavailableSourceURLs removeAllObjects];
        [self rebuildDataSources];
    }];
}

- (NSArray<TVSite *> *)availableVodSites {
    NSMutableArray<TVSite *> *result = [NSMutableArray array];
    for (TVSite *site in self.config.vodSites) {
        if ([self isSourceAvailable:site.api]) {
            [result addObject:site];
        }
    }
    return result;
}

- (NSArray<TVLiveSource *> *)availableLiveSources {
    NSMutableArray<TVLiveSource *> *result = [NSMutableArray array];
    for (TVLiveSource *source in self.config.liveSources) {
        if ([self isSourceAvailable:source.url]) {
            [result addObject:source];
        }
    }
    return result;
}

- (BOOL)isSourceAvailable:(NSString *)urlString {
    if (urlString.length == 0) return NO;
    return ![self.unavailableSourceURLs containsObject:urlString];
}

- (void)rebuildSites {
    [self.sitePopup removeAllItems];
    for (TVSite *site in [self availableVodSites]) {
        [self.sitePopup addItemWithTitle:site.name];
        [self.sitePopup.lastItem setRepresentedObject:site];
    }
    if (self.sitePopup.numberOfItems > 0) {
        [self.sitePopup selectItemAtIndex:0];
        [self loadVODList];
    } else {
        self.videos = @[];
        self.categories = @[];
        [self rebuildCategoryButtons];
        [self.vodCollectionView reloadData];
        [self setStatus:@"暂无可用点播数据源"];
    }
}

- (void)rebuildLiveSources {
    [self.liveSourcePopup removeAllItems];
    [self.liveSourcePopup addItemWithTitle:@"全部数据源（合并）"];
    for (TVLiveSource *source in [self availableLiveSources]) {
        [self.liveSourcePopup addItemWithTitle:source.name];
        [self.liveSourcePopup.lastItem setRepresentedObject:source];
    }
    [self.liveSourcePopup selectItemAtIndex:0];
    [self loadMergedLiveChannels];
}

- (void)rebuildDataSources {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (TVSite *site in self.config.vodSites) {
        [rows addObject:@{@"name": site.name ?: @"", @"type": @"点播", @"url": site.api ?: @"", @"status": @"检查中"}];
    }
    for (TVLiveSource *source in self.config.liveSources) {
        [rows addObject:@{@"name": source.name ?: @"", @"type": @"直播", @"url": source.url ?: @"", @"status": @"检查中"}];
    }
    self.sourceRows = rows;
    [self.sourcesTable reloadData];
    [self checkDataSourcesAvailability];
}

- (void)checkDataSourcesAvailability {
    [self showCheckingPanel];
    self.availabilityCheckGeneration++;
    NSInteger generation = self.availabilityCheckGeneration;

    NSArray<NSDictionary *> *rows = [self.sourceRows copy];
    dispatch_group_t group = dispatch_group_create();

    for (NSDictionary *row in rows) {
        NSString *urlString = row[@"url"];
        dispatch_group_enter(group);
        [self checkDataSourceURL:urlString completion:^(NSString *status) {
            [self updateSourceRowStatus:status forURL:urlString generation:generation];
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (generation != self.availabilityCheckGeneration) return;
        [self sortUnavailableSourcesToEnd];
        [self hideCheckingPanel];
        [self rebuildSites];
        [self rebuildLiveSources];
    });
}

- (void)checkDataSourceURL:(NSString *)urlString completion:(void (^)(NSString *status))completion {
    if (urlString.length == 0) {
        if (completion) completion(@"不可用");
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(@"不可用");
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 10;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *status = (error == nil) ? @"可用" : @"不可用";
        if (completion) completion(status);
    }] resume];
}

- (void)updateSourceRowStatus:(NSString *)status forURL:(NSString *)urlString generation:(NSInteger)generation {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self.availabilityCheckGeneration) return;
        if ([status isEqualToString:@"不可用"]) {
            [self.unavailableSourceURLs addObject:urlString];
        } else {
            [self.unavailableSourceURLs removeObject:urlString];
        }
        NSMutableArray<NSDictionary *> *rows = [self.sourceRows mutableCopy];
        BOOL changed = NO;
        for (NSUInteger i = 0; i < rows.count; i++) {
            NSDictionary *row = rows[i];
            if ([row[@"url"] isEqualToString:urlString]) {
                NSMutableDictionary *updated = [row mutableCopy];
                updated[@"status"] = status;
                rows[i] = updated;
                changed = YES;
            }
        }
        if (changed) {
            self.sourceRows = rows;
            [self.sourcesTable reloadData];
        }
    });
}

- (void)sortUnavailableSourcesToEnd {
    self.sourceRows = [self.sourceRows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL aUnavailable = [a[@"status"] isEqualToString:@"不可用"];
        BOOL bUnavailable = [b[@"status"] isEqualToString:@"不可用"];
        if (aUnavailable == bUnavailable) return NSOrderedSame;
        return aUnavailable ? NSOrderedDescending : NSOrderedAscending;
    }];
}

- (void)showCheckingPanel {
    if (self.checkingPanel) return;
    NSWindow *parent = self.view.window;
    if (!parent) return;

    NSWindow *panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 340, 130)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    panel.title = @"检查中";
    panel.releasedWhenClosed = NO;

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 130)];

    NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 76, 24, 24)];
    spinner.style = NSProgressIndicatorStyleSpinning;
    [spinner startAnimation:nil];

    NSTextField *label = [NSTextField labelWithString:@"正在检查数据源可用性，请稍候…"];
    label.font = [NSFont systemFontOfSize:13];
    label.frame = NSMakeRect(56, 80, 270, 20);

    [content addSubview:spinner];
    [content addSubview:label];
    panel.contentView = content;

    self.checkingPanel = panel;
    [parent beginSheet:panel completionHandler:nil];
}

- (void)hideCheckingPanel {
    if (self.checkingPanel) {
        NSWindow *panel = self.checkingPanel;
        self.checkingPanel = nil;
        [self.view.window endSheet:panel];
    }
}

#pragma mark - 点播逻辑

- (void)siteChanged:(NSPopUpButton *)sender {
    self.selectedCategoryId = 0;
    // 更换数据源后首先清理列表，再加载新数据源内容
    self.videos = @[];
    self.categories = @[];
    self.vodPage = 0;
    self.vodHasMore = NO;
    self.vodLoadingMore = NO;
    [self rebuildCategoryButtons];
    [self.vodCollectionView reloadData];
    [self loadVODList];
}

- (void)loadVODList {
    self.vodSearchKeyword = @"";
    [self loadVODPage:1 reset:YES];
}

- (void)loadVODPage:(NSInteger)page reset:(BOOL)reset {
    TVSite *site = [self selectedSiteForPopup:self.sitePopup];
    if (!site) {
        self.vodLoadingMore = NO;
        return;
    }
    if (self.vodLoadingMore) return;
    self.vodLoadingMore = YES;

    [self setStatus:[NSString stringWithFormat:@"正在加载「%@」第%ld页…", site.name, (long)page]];

    NSMutableDictionary<NSString *, NSString *> *params = [@{@"ac": @"list", @"pg": [NSString stringWithFormat:@"%ld", (long)page]} mutableCopy];
    if (self.selectedCategoryId > 0) {
        params[@"t"] = [NSString stringWithFormat:@"%ld", (long)self.selectedCategoryId];
    }

    NSURL *url = [self.config vodURLForSite:site params:params];
    [self.config requestJSONFromURL:url completion:^(id _Nullable json, NSError * _Nullable error) {
        self.vodLoadingMore = NO;

        if (error) {
            [self setStatus:[NSString stringWithFormat:@"「%@」加载失败：%@，请切换其他站点", site.name, error.localizedDescription]];
            if (reset) {
                self.categories = @[];
                self.videos = @[];
                self.vodPage = 0;
                self.vodHasMore = NO;
                [self rebuildCategoryButtons];
                [self.vodCollectionView reloadData];
            }
            return;
        }

        NSDictionary *dict = (NSDictionary *)json;
        NSArray<TVVideo *> *newVideos = [self videosFromList:dict[@"list"]];

        NSInteger pageCount = [dict[@"pagecount"] integerValue];
        if (pageCount > 0) {
            self.vodHasMore = (page < pageCount);
        } else {
            self.vodHasMore = (newVideos.count > 0);
        }
        self.vodPage = page;

        if (reset) {
            NSMutableArray<TVCategory *> *categories = [NSMutableArray array];
            for (id item in dict[@"class"]) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    [categories addObject:[TVCategory categoryFromDictionary:(NSDictionary *)item]];
                }
            }
            // 部分站点在带 t 参数请求时不再返回分类，此时沿用已加载的分类，避免分类按钮消失
            if (categories.count > 0) {
                self.categories = categories;
            }
            self.videos = newVideos;
            [self rebuildCategoryButtons];
        } else {
            NSMutableArray<TVVideo *> *combined = [self.videos mutableCopy];
            [combined addObjectsFromArray:newVideos];
            self.videos = combined;
        }
        [self.vodCollectionView reloadData];
        [self setStatus:@""];

        // 部分站点 ac=list 接口不返回 vod_pic，批量补拉详情以补全封面图
        [self fillMissingPostersForVideos:newVideos site:site];

        // 首屏内容不足以填满可视区域时，自动加载下一页
        [self scheduleVODPaginationCheck];
    }];
}

- (void)fillMissingPostersForVideos:(NSArray<TVVideo *> *)videos site:(TVSite *)site {
    if (!site || videos.count == 0) return;

    NSMutableArray<NSString *> *missingIds = [NSMutableArray array];
    for (TVVideo *video in videos) {
        if (video.vodPic.length == 0 && video.vodId > 0) {
            [missingIds addObject:[NSString stringWithFormat:@"%ld", (long)video.vodId]];
        }
    }
    if (missingIds.count == 0) return;

    NSURL *url = [self.config vodURLForSite:site params:@{@"ac": @"detail", @"ids": [missingIds componentsJoinedByString:@","]}];
    [self.config requestJSONFromURL:url completion:^(id _Nullable json, NSError * _Nullable error) {
        if (error || ![json isKindOfClass:[NSDictionary class]]) return;

        NSArray *list = ((NSDictionary *)json)[@"list"];
        if (![list isKindOfClass:[NSArray class]] || list.count == 0) return;

        NSMutableDictionary<NSNumber *, NSString *> *picMap = [NSMutableDictionary dictionary];
        for (id item in list) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSInteger vid = [((NSDictionary *)item)[@"vod_id"] integerValue];
            NSString *pic = ((NSDictionary *)item)[@"vod_pic"];
            if (vid > 0 && [pic isKindOfClass:[NSString class]] && ((NSString *)pic).length > 0) {
                picMap[@(vid)] = pic;
            }
        }
        if (picMap.count == 0) return;

        for (TVVideo *video in videos) {
            NSString *pic = picMap[@(video.vodId)];
            if (pic.length > 0 && video.vodPic.length == 0) {
                video.vodPic = pic;
            }
        }
        [self.vodCollectionView reloadData];
    }];
}

- (void)loadNextVODPage {
    if (self.vodLoadingMore || !self.vodHasMore) return;
    if (self.vodSearchKeyword.length > 0) return;
    if (self.vodPage <= 0) return;
    [self loadVODPage:self.vodPage + 1 reset:NO];
}

- (void)vodScrollDidScroll:(NSNotification *)note {
    NSClipView *clip = (NSClipView *)note.object;
    if (![clip isKindOfClass:[NSClipView class]]) return;

    NSRect visibleRect = clip.documentVisibleRect;
    NSRect documentRect = clip.documentRect;
    if (documentRect.size.height <= 0) return;

    CGFloat distanceFromBottom = documentRect.size.height - NSMaxY(visibleRect);
    if (distanceFromBottom < 200) {
        [self loadNextVODPage];
    }
}

- (void)scheduleVODPaginationCheck {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSClipView *clip = self.vodScrollView.contentView;
        NSRect visibleRect = clip.documentVisibleRect;
        NSRect documentRect = clip.documentRect;
        if (documentRect.size.height <= 0) return;
        if (documentRect.size.height - NSMaxY(visibleRect) < 200) {
            [self loadNextVODPage];
        }
    });
}

- (void)vodSearchAction:(id)sender {
    [self performVODSearch];
}

- (void)performVODSearch {
    TVSite *site = [self selectedSiteForPopup:self.sitePopup];
    if (!site) return;

    NSString *keyword = [self.vodSearchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (keyword.length == 0) {
        [self loadVODList];
        return;
    }

    self.vodSearchKeyword = keyword;
    self.vodPage = 0;
    self.vodHasMore = NO;

    [self setStatus:[NSString stringWithFormat:@"正在「%@」中搜索「%@」…", site.name, keyword]];
    NSURL *url = [self.config vodURLForSite:site params:@{@"ac": @"detail", @"wd": keyword}];
    [self.config requestJSONFromURL:url completion:^(id _Nullable json, NSError * _Nullable error) {
        if (error) {
            [self setStatus:[NSString stringWithFormat:@"搜索失败：%@", error.localizedDescription]];
            return;
        }
        NSMutableArray<TVVideo *> *results = [NSMutableArray array];
        for (id item in ((NSDictionary *)json)[@"list"]) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                TVVideo *video = [TVVideo videoFromDictionary:(NSDictionary *)item];
                video.sourceSite = site;
                [results addObject:video];
            }
        }
        self.videos = results;
        [self.vodCollectionView reloadData];
        [self setStatus:@""];
    }];
}

#pragma mark - 搜索逻辑

- (void)controlTextDidChange:(NSNotification *)notification {
    [self scheduleSearch];
}

- (void)scheduleSearch {
    [self.searchTimer invalidate];
    self.searchTimer = [NSTimer scheduledTimerWithTimeInterval:0.4
                                                        target:self
                                                      selector:@selector(searchTimerFired:)
                                                      userInfo:nil
                                                       repeats:NO];
}

- (void)searchTimerFired:(NSTimer *)timer {
    [self performSearch:nil];
}

- (void)searchAction:(id)sender {
    [self.searchTimer invalidate];
    [self performSearch:nil];
    [self rememberSearchKeyword:[self.searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
}

#pragma mark - 搜索关键词历史

- (void)loadSearchKeywords {
    self.searchKeywords = [NSMutableArray array];
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kTVBoxSearchKeywordsKey];
    if ([saved isKindOfClass:[NSArray class]]) {
        for (id item in saved) {
            if ([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0) {
                [self.searchKeywords addObject:(NSString *)item];
            }
        }
    }
}

// 记录一次搜索关键词（去重、最新在前、限制数量并持久化）
- (void)rememberSearchKeyword:(NSString *)keyword {
    if (keyword.length == 0) return;
    [self.searchKeywords removeObject:keyword];
    [self.searchKeywords insertObject:keyword atIndex:0];
    while (self.searchKeywords.count > kTVBoxSearchKeywordsLimit) {
        [self.searchKeywords removeLastObject];
    }
    [[NSUserDefaults standardUserDefaults] setObject:[self.searchKeywords copy] forKey:kTVBoxSearchKeywordsKey];
    [self rebuildSearchKeywordsBar];
}

// 重新构建关键词历史条
- (void)rebuildSearchKeywordsBar {
    for (NSView *subview in [self.searchKeywordsBar.subviews copy]) {
        [subview removeFromSuperview];
    }

    BOOL hasKeywords = (self.searchKeywords.count > 0);
    self.searchKeywordsScroll.hidden = !hasKeywords;
    self.searchKeywordsHeightConstraint.constant = hasKeywords ? 34 : 0;

    if (!hasKeywords) {
        self.searchKeywordsBar.frame = NSMakeRect(0, 0, 0, 34);
        return;
    }

    const CGFloat barHeight = 34;
    const CGFloat chipHeight = 24;
    const CGFloat spacing = 8;
    const CGFloat deleteWidth = 20;

    CGFloat x = 0;

    // 前缀标签，说明该行内容
    NSTextField *prefix = [NSTextField labelWithString:@"搜索历史："];
    prefix.font = [NSFont systemFontOfSize:12];
    prefix.textColor = [NSColor secondaryLabelColor];
    [prefix sizeToFit];
    CGFloat prefixWidth = prefix.frame.size.width;
    prefix.frame = NSMakeRect(x, (barHeight - prefix.frame.size.height) / 2.0, prefixWidth, prefix.frame.size.height);
    [self.searchKeywordsBar addSubview:prefix];
    x += prefixWidth + spacing;

    for (NSString *keyword in self.searchKeywords) {
        NSButton *chip = [NSButton buttonWithTitle:keyword target:self action:@selector(searchKeywordChipClicked:)];
        chip.bezelStyle = NSBezelStyleRounded;
        chip.controlSize = NSControlSizeSmall;
        chip.font = [NSFont systemFontOfSize:12];
        chip.toolTip = @"点击重新搜索";
        chip.image = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:@"搜索"];
        chip.imagePosition = NSImageLeading;
        [chip sizeToFit];
        CGFloat chipWidth = MAX(chip.fittingSize.width + 12, 40);
        chip.frame = NSMakeRect(x, (barHeight - chipHeight) / 2.0, chipWidth, chipHeight);
        [self.searchKeywordsBar addSubview:chip];

        NSButton *deleteButton = [NSButton buttonWithTitle:keyword target:self action:@selector(searchKeywordDeleteClicked:)];
        deleteButton.title = keyword;
        deleteButton.image = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"删除"];
        deleteButton.imagePosition = NSImageOnly;
        deleteButton.bezelStyle = NSBezelStyleRegularSquare;
        deleteButton.bordered = NO;
        deleteButton.contentTintColor = [NSColor secondaryLabelColor];
        deleteButton.toolTip = @"删除该关键词";
        deleteButton.frame = NSMakeRect(x + chipWidth + 2, (barHeight - deleteWidth) / 2.0, deleteWidth, deleteWidth);
        [self.searchKeywordsBar addSubview:deleteButton];

        x += chipWidth + 2 + deleteWidth + spacing;
    }

    self.searchKeywordsBar.frame = NSMakeRect(0, 0, x, barHeight);
    [self.searchKeywordsScroll reflectScrolledClipView:self.searchKeywordsScroll.contentView];
}

- (void)searchKeywordChipClicked:(id)sender {
    NSString *keyword = [(NSButton *)sender title];
    if (keyword.length == 0) return;
    self.searchField.stringValue = keyword;
    [self.searchTimer invalidate];
    [self performSearch:nil];
    // 点击历史关键词重新搜索，将其移动到历史最前
    [self rememberSearchKeyword:keyword];
}

- (void)searchKeywordDeleteClicked:(id)sender {
    NSString *keyword = [(NSButton *)sender title];
    if (keyword.length == 0) return;
    [self.searchKeywords removeObject:keyword];
    [[NSUserDefaults standardUserDefaults] setObject:[self.searchKeywords copy] forKey:kTVBoxSearchKeywordsKey];
    [self rebuildSearchKeywordsBar];
}

- (void)performSearch:(id)sender {
    NSString *keyword = [self.searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (keyword.length == 0) {
        self.searchResults = @[];
        [self.searchCollectionView reloadData];
        [self setStatus:@""];
        return;
    }

    // 先清除上一次的搜索结果，再进行新的搜索
    self.searchResults = @[];
    [self.searchCollectionView reloadData];

    self.searchGeneration++;
    NSInteger generation = self.searchGeneration;
    NSArray<TVSite *> *sites = [self availableVodSites];

    if (sites.count == 0) {
        self.searchResults = @[];
        [self.searchCollectionView reloadData];
        [self setStatus:@"暂无可用数据源"];
        return;
    }

    [self setStatus:[NSString stringWithFormat:@"正在所有数据源中搜索「%@」…", keyword]];

    __block NSInteger remaining = (NSInteger)sites.count;
    __block NSMutableArray<TVVideo *> *results = [NSMutableArray array];

    for (TVSite *site in sites) {
        TVSite *siteForRequest = site;
        NSURL *url = [self.config vodURLForSite:siteForRequest params:@{@"ac": @"detail", @"wd": keyword}];
        [self.config requestJSONFromURL:url completion:^(id _Nullable json, NSError * _Nullable error) {
            if (!error && [json isKindOfClass:[NSDictionary class]]) {
                id list = ((NSDictionary *)json)[@"list"];
                for (id item in list) {
                    if ([item isKindOfClass:[NSDictionary class]]) {
                        TVVideo *video = [TVVideo videoFromDictionary:(NSDictionary *)item];
                        video.sourceSite = siteForRequest;
                        [results addObject:video];
                    }
                }
            }
            remaining--;
            if (remaining == 0 && generation == self.searchGeneration) {
                // 搜索结果按相似度从高到低排序
                NSArray<TVVideo *> *sorted = [results sortedArrayUsingComparator:^NSComparisonResult(TVVideo *a, TVVideo *b) {
                    double sa = [self searchSimilarityScore:keyword video:a];
                    double sb = [self searchSimilarityScore:keyword video:b];
                    if (sa > sb) return NSOrderedAscending;
                    if (sa < sb) return NSOrderedDescending;
                    return NSOrderedSame;
                }];
                self.searchResults = sorted;
                [self.searchCollectionView reloadData];
                [self setStatus:@""];
            }
        }];
    }
}

// 计算视频标题与关键词的相似度（0~1，越高越相似）
- (double)searchSimilarityScore:(NSString *)keyword video:(TVVideo *)video {
    double nameScore = [self similarityBetweenKeyword:keyword andTitle:video.name];
    double enScore = [self similarityBetweenKeyword:keyword andTitle:video.vodEn];
    return MAX(nameScore, enScore);
}

- (double)similarityBetweenKeyword:(NSString *)keyword andTitle:(NSString *)title {
    if (keyword.length == 0 || title.length == 0) return 0;

    NSString *k = [keyword lowercaseString];
    NSString *t = [title lowercaseString];

    if ([t isEqualToString:k]) return 1.0;

    if ([t hasPrefix:k]) {
        // 前缀匹配：关键词占标题比例越高得分越高
        return 0.9 + 0.09 * ((double)k.length / (double)t.length);
    }

    NSRange range = [t rangeOfString:k];
    if (range.location != NSNotFound) {
        // 包含匹配：关键词出现位置越靠前得分越高
        double positionFactor = 1.0 - ((double)range.location / (double)t.length);
        return 0.6 + 0.3 * positionFactor;
    }

    // 其余情况按编辑距离估算相似度
    NSUInteger maxLen = MAX(k.length, t.length);
    if (maxLen == 0) return 0;
    NSUInteger distance = TVLevenshteinDistance(k, t);
    return MAX(0.0, 1.0 - ((double)distance / (double)maxLen)) * 0.5;
}

- (NSArray<TVVideo *> *)videosFromList:(id)list {
    NSMutableArray<TVVideo *> *videos = [NSMutableArray array];
    for (id item in list) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            [videos addObject:[TVVideo videoFromDictionary:(NSDictionary *)item]];
        }
    }
    return videos;
}

- (TVSite *)selectedSiteForPopup:(NSPopUpButton *)popup {
    return (TVSite *)popup.selectedItem.representedObject;
}

- (void)rebuildCategoryButtons {
    for (NSView *subview in self.categoryContentView.subviews) {
        [subview removeFromSuperview];
    }

    // 找出被引用的“父分类”ID：凡是被其他分类的 type_pid 指向的分类，都是分组目录，
    // 其视频实际存放在子分类下；直接请求这类一级分类通常只返回极少量甚至没有视频。
    NSMutableSet<NSNumber *> *parentIds = [NSMutableSet set];
    for (TVCategory *category in self.categories) {
        if (category.typePid > 0) {
            [parentIds addObject:@(category.typePid)];
        }
    }

    // 只把“叶子”分类（没有子分类的分类）作为可点击的筛选按钮，
    // 这样点击任意分类都能得到该分类下完整的分页视频列表。
    NSMutableArray<TVCategory *> *clickable = [NSMutableArray array];
    for (TVCategory *category in self.categories) {
        if ([parentIds containsObject:@(category.typeId)]) continue;
        [clickable addObject:category];
    }
    // 兜底：若没有任何叶子分类（部分站点只有一级分类），则回退为展示全部分类。
    if (clickable.count == 0) {
        clickable = [self.categories mutableCopy];
    }

    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    [buttons addObject:[self categoryButtonWithTitle:@"全部" typeId:0]];
    for (TVCategory *category in clickable) {
        [buttons addObject:[self categoryButtonWithTitle:category.name typeId:category.typeId]];
    }

    CGFloat x = 8;
    for (NSButton *button in buttons) {
        [button sizeToFit];
        NSSize size = button.frame.size;
        size.width = MAX(size.width + 16, 44);
        button.frame = NSMakeRect(x, 5, size.width, 26);
        x += size.width + 8;
        [self.categoryContentView addSubview:button];
    }
    self.categoryContentView.frame = NSMakeRect(0, 0, x + 8, 40);
    [self updateCategoryButtonStates];
}

- (NSButton *)categoryButtonWithTitle:(NSString *)title typeId:(NSInteger)typeId {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(categoryButtonClicked:)];
    button.bezelStyle = NSBezelStyleRounded;
    button.tag = typeId;
    button.image = [NSImage imageWithSystemSymbolName:(typeId == 0 ? @"square.grid.2x2" : @"film")
                                 accessibilityDescription:title];
    button.imagePosition = NSImageLeading;
    return button;
}

- (void)categoryButtonClicked:(NSButton *)sender {
    self.selectedCategoryId = sender.tag;
    [self updateCategoryButtonStates];
    [self loadVODList];
}

- (void)updateCategoryButtonStates {
    for (NSView *subview in self.categoryContentView.subviews) {
        if ([subview isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)subview;
            button.state = (button.tag == self.selectedCategoryId) ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
}

#pragma mark - 打开视频详情与播放

- (void)openVideo:(TVVideo *)video site:(TVSite *)site {
    if (!site) return;

    [self setStatus:@"正在获取播放信息…"];
    NSURL *url = [self.config vodURLForSite:site
                                     params:@{@"ac": @"detail", @"ids": [NSString stringWithFormat:@"%ld", (long)video.vodId]}];
    [self.config requestJSONFromURL:url completion:^(id _Nullable json, NSError * _Nullable error) {
        if (error) {
            [self setStatus:[NSString stringWithFormat:@"获取播放信息失败：%@", error.localizedDescription]];
            return;
        }
        NSArray *list = ((NSDictionary *)json)[@"list"];
        if (![list isKindOfClass:[NSArray class]] || list.count == 0) {
            [self setStatus:@"未获取到播放信息"];
            return;
        }
        [self setStatus:@""];
        TVVideo *detail = [TVVideo videoFromDictionary:(NSDictionary *)list[0]];
        [self showDetailModalForVideo:detail site:site];
    }];
}

// 用模态窗口显示该视频的介绍信息和可播放的视频列表，并提供播放按钮
- (void)showDetailModalForVideo:(TVVideo *)detail site:(TVSite *)site {
    self.detailModalVideo = detail;
    self.detailModalSite = site;

    NSArray<TVPlaySource *> *sources = [detail playSources];

    NSWindow *modal = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 600)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    modal.title = detail.name ?: @"视频详情";
    modal.releasedWhenClosed = NO;
    self.detailModalWindow = modal;

    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 700, 600)];
    modal.contentView = root;

    // 海报
    NSImageView *posterView = [[NSImageView alloc] init];
    posterView.translatesAutoresizingMaskIntoConstraints = NO;
    posterView.imageScaling = NSImageScaleProportionallyUpOrDown;
    posterView.wantsLayer = YES;
    posterView.layer.cornerRadius = 8;
    posterView.layer.masksToBounds = YES;
    posterView.layer.backgroundColor = [NSColor colorWithWhite:0.86 alpha:1.0].CGColor;
    [root addSubview:posterView];
    [self loadPosterImage:detail.vodPic into:posterView];

    // 标题
    NSTextField *titleLabel = [NSTextField labelWithString:detail.name ?: @""];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont boldSystemFontOfSize:20];
    titleLabel.textColor = [NSColor labelColor];
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [root addSubview:titleLabel];

    // 元信息（类型 · 年代 · 备注 / 导演 / 主演）
    NSTextField *metaLabel = [NSTextField wrappingLabelWithString:[self modalMetaTextForVideo:detail]];
    metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    metaLabel.font = [NSFont systemFontOfSize:12];
    metaLabel.textColor = [NSColor secondaryLabelColor];
    metaLabel.maximumNumberOfLines = 3;
    [root addSubview:metaLabel];

    // 分隔线
    NSView *divider = [[NSView alloc] init];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.wantsLayer = YES;
    divider.layer.backgroundColor = [NSColor separatorColor].CGColor;
    [root addSubview:divider];

    // 简介区标题
    NSTextField *introLabel = [NSTextField labelWithString:@"简介"];
    introLabel.translatesAutoresizingMaskIntoConstraints = NO;
    introLabel.font = [NSFont boldSystemFontOfSize:13];
    introLabel.textColor = [NSColor labelColor];
    [root addSubview:introLabel];

    // 简介内容（可滚动，HTML 解析）
    NSTextView *infoView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
    infoView.editable = NO;
    infoView.drawsBackground = NO;
    infoView.minSize = NSMakeSize(0, 0);
    infoView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    infoView.verticallyResizable = YES;
    infoView.horizontallyResizable = NO;
    infoView.autoresizingMask = NSViewWidthSizable;
    infoView.textContainer.containerSize = NSMakeSize(FLT_MAX, FLT_MAX);
    infoView.textContainer.widthTracksTextView = YES;
    [infoView.textStorage setAttributedString:[self modalDetailTextForVideo:detail]];

    NSScrollView *infoScroll = [[NSScrollView alloc] init];
    infoScroll.translatesAutoresizingMaskIntoConstraints = NO;
    infoScroll.hasVerticalScroller = YES;
    infoScroll.borderType = NSNoBorder;
    infoScroll.drawsBackground = NO;
    infoScroll.documentView = infoView;
    [root addSubview:infoScroll];

    // 可播放列表：线路 + 集数
    NSTextField *lineLabel = [NSTextField labelWithString:@"线路"];
    lineLabel.translatesAutoresizingMaskIntoConstraints = NO;
    lineLabel.font = [NSFont systemFontOfSize:12];
    lineLabel.textColor = [NSColor secondaryLabelColor];
    [root addSubview:lineLabel];

    NSPopUpButton *linePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    linePopup.translatesAutoresizingMaskIntoConstraints = NO;
    for (TVPlaySource *source in sources) {
        [linePopup addItemWithTitle:source.name];
    }
    linePopup.target = self;
    linePopup.action = @selector(detailModalLineChanged:);
    [root addSubview:linePopup];
    self.detailModalLinePopup = linePopup;

    NSTextField *episodeLabel = [NSTextField labelWithString:@"集数"];
    episodeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    episodeLabel.font = [NSFont systemFontOfSize:12];
    episodeLabel.textColor = [NSColor secondaryLabelColor];
    [root addSubview:episodeLabel];

    NSPopUpButton *episodePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    episodePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:episodePopup];
    self.detailModalEpisodePopup = episodePopup;

    NSButton *cancelButton = [NSButton buttonWithTitle:@"取消" target:self action:@selector(detailModalCancelAction:)];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    cancelButton.bezelStyle = NSBezelStyleRounded;
    cancelButton.keyEquivalent = @"\e";
    cancelButton.image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"取消"];
    cancelButton.imagePosition = NSImageLeading;
    [root addSubview:cancelButton];

    NSButton *playButton = [NSButton buttonWithTitle:@"播放" target:self action:@selector(detailModalPlayAction:)];
    playButton.translatesAutoresizingMaskIntoConstraints = NO;
    playButton.bezelStyle = NSBezelStyleRounded;
    playButton.keyEquivalent = @"\r";
    playButton.image = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:@"播放"];
    playButton.imagePosition = NSImageLeading;
    playButton.enabled = (sources.count > 0);
    [root addSubview:playButton];

    [NSLayoutConstraint activateConstraints:@[
        [posterView.topAnchor constraintEqualToAnchor:root.topAnchor constant:20],
        [posterView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [posterView.widthAnchor constraintEqualToConstant:170],
        [posterView.heightAnchor constraintEqualToConstant:238],

        [titleLabel.topAnchor constraintEqualToAnchor:root.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:posterView.trailingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],

        [metaLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],
        [metaLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [metaLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [divider.topAnchor constraintEqualToAnchor:metaLabel.bottomAnchor constant:14],
        [divider.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [divider.heightAnchor constraintEqualToConstant:1],

        [introLabel.topAnchor constraintEqualToAnchor:divider.bottomAnchor constant:12],
        [introLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],

        [infoScroll.topAnchor constraintEqualToAnchor:introLabel.bottomAnchor constant:6],
        [infoScroll.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [infoScroll.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [infoScroll.bottomAnchor constraintEqualToAnchor:linePopup.topAnchor constant:-16],

        [lineLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [lineLabel.centerYAnchor constraintEqualToAnchor:linePopup.centerYAnchor],
        [linePopup.leadingAnchor constraintEqualToAnchor:lineLabel.trailingAnchor constant:8],
        [linePopup.widthAnchor constraintEqualToConstant:150],
        [linePopup.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20],

        [episodeLabel.leadingAnchor constraintEqualToAnchor:linePopup.trailingAnchor constant:16],
        [episodeLabel.centerYAnchor constraintEqualToAnchor:episodePopup.centerYAnchor],
        [episodePopup.leadingAnchor constraintEqualToAnchor:episodeLabel.trailingAnchor constant:8],
        [episodePopup.widthAnchor constraintEqualToConstant:150],
        [episodePopup.bottomAnchor constraintEqualToAnchor:linePopup.bottomAnchor],

        [cancelButton.trailingAnchor constraintEqualToAnchor:playButton.leadingAnchor constant:-10],
        [cancelButton.centerYAnchor constraintEqualToAnchor:playButton.centerYAnchor],
        [cancelButton.widthAnchor constraintEqualToConstant:72],

        [playButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [playButton.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20],
        [playButton.widthAnchor constraintEqualToConstant:120],
    ]];

    [self detailModalLineChanged:linePopup];

    [self.view.window beginSheet:modal completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            [self beginPlaybackFromModal];
        }
        self.detailModalWindow = nil;
    }];
}

- (void)detailModalLineChanged:(NSPopUpButton *)sender {
    NSArray<TVPlaySource *> *sources = [self.detailModalVideo playSources];
    NSInteger index = sender.indexOfSelectedItem;
    [self.detailModalEpisodePopup removeAllItems];
    if (index >= 0 && index < (NSInteger)sources.count) {
        for (TVEpisode *episode in sources[index].episodes) {
            [self.detailModalEpisodePopup addItemWithTitle:episode.name];
        }
    }
    if (self.detailModalEpisodePopup.numberOfItems > 0) {
        [self.detailModalEpisodePopup selectItemAtIndex:0];
    }
}

- (void)detailModalPlayAction:(id)sender {
    NSWindow *sheet = self.detailModalWindow;
    if (sheet.sheetParent) {
        [sheet.sheetParent endSheet:sheet returnCode:NSModalResponseOK];
    }
}

- (void)detailModalCancelAction:(id)sender {
    NSWindow *sheet = self.detailModalWindow;
    if (sheet.sheetParent) {
        [sheet.sheetParent endSheet:sheet returnCode:NSModalResponseCancel];
    }
}

// 点击播放按钮后关闭模态窗口并播放该视频
- (void)beginPlaybackFromModal {
    TVVideo *detail = self.detailModalVideo;
    TVSite *site = self.detailModalSite;
    if (!detail || !site) return;

    NSArray<TVPlaySource *> *sources = [detail playSources];
    NSInteger sourceIndex = self.detailModalLinePopup.indexOfSelectedItem;
    NSInteger episodeIndex = self.detailModalEpisodePopup.indexOfSelectedItem;
    if (sourceIndex < 0 || sourceIndex >= (NSInteger)sources.count) sourceIndex = 0;
    NSArray<TVEpisode *> *episodes = sources.count > 0 ? sources[sourceIndex].episodes : @[];
    if (episodeIndex < 0 || episodeIndex >= (NSInteger)episodes.count) episodeIndex = 0;

    [self presentPlayerWithTitle:detail.name block:^(PlayerViewController *player) {
        [player resumeVideo:detail sourceIndex:sourceIndex episodeIndex:episodeIndex resumeTime:0];
    }];
    self.currentHistoryItem = [self historyItemForVideo:detail site:site];
}

// 构建模态窗口标题下方的元信息文本
- (NSString *)modalMetaTextForVideo:(TVVideo *)video {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSMutableArray<NSString *> *tags = [NSMutableArray array];
    if (video.typeName.length > 0) [tags addObject:video.typeName];
    if (video.vodTime.length > 0) [tags addObject:video.vodTime];
    if (video.remarks.length > 0) [tags addObject:video.remarks];
    if (tags.count > 0) [lines addObject:[tags componentsJoinedByString:@"  ·  "]];
    if (video.vodDirector.length > 0) [lines addObject:[NSString stringWithFormat:@"导演：%@", video.vodDirector]];
    if (video.vodActor.length > 0) [lines addObject:[NSString stringWithFormat:@"主演：%@", video.vodActor]];
    return [lines componentsJoinedByString:@"\n"];
}

// 构建模态窗口中的简介内容（HTML 解析）
- (NSAttributedString *)modalDetailTextForVideo:(TVVideo *)video {
    if (video.vodContent.length > 0) {
        NSAttributedString *html = [self modalHTMLAttributedString:video.vodContent];
        if (html.length > 0) {
            return html;
        }
        return [[NSAttributedString alloc] initWithString:video.vodContent attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:13],
            NSForegroundColorAttributeName: [NSColor labelColor],
        }];
    }
    return [[NSAttributedString alloc] initWithString:@"暂无简介" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
    }];
}

// 异步加载海报图
- (void)loadPosterImage:(NSString *)urlString into:(NSImageView *)imageView {
    imageView.image = [VODCollectionItem defaultPosterImage];
    if (urlString.length == 0) return;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSImage *image = nil;
        if (!error && data) {
            image = [[NSImage alloc] initWithData:data];
        }
        NSImage *finalImage = image ?: [VODCollectionItem defaultPosterImage];
        dispatch_async(dispatch_get_main_queue(), ^{
            imageView.image = finalImage;
        });
    }];
    [task resume];
}

// 以 HTML 格式解释简介内容，支持 <br>、<p>、<b>、<i> 等标签
- (NSAttributedString *)modalHTMLAttributedString:(NSString *)html {
    if (html.length == 0) return nil;
    NSString *wrapped = [NSString stringWithFormat:@"<span style=\"font-size:13px;\">%@</span>", html];
    NSData *data = [wrapped dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;

    NSError *error = nil;
    NSAttributedString *attr = [[NSAttributedString alloc] initWithData:data
                                                                options:@{
        NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
        NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding),
    } documentAttributes:nil error:&error];
    if (error || attr.length == 0) return nil;

    NSMutableAttributedString *normalized = [attr mutableCopy];
    [attr enumerateAttributesInRange:NSMakeRange(0, attr.length)
                             options:0
                          usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attributes, NSRange range, BOOL *stop) {
        NSFont *font = attributes[NSFontAttributeName];
        NSFontManager *fontManager = [NSFontManager sharedFontManager];
        NSFont *newFont = [NSFont systemFontOfSize:13];
        if (font && ([fontManager traitsOfFont:font] & NSBoldFontMask)) {
            newFont = [fontManager convertFont:newFont toHaveTrait:NSBoldFontMask];
        }
        if (font && ([fontManager traitsOfFont:font] & NSItalicFontMask)) {
            newFont = [fontManager convertFont:newFont toHaveTrait:NSItalicFontMask];
        }
        [normalized addAttribute:NSFontAttributeName value:newFont range:range];
        [normalized addAttribute:NSForegroundColorAttributeName value:[NSColor labelColor] range:range];
    }];
    return normalized;
}

#pragma mark - 直播逻辑

- (void)liveSourceChanged:(id)sender {
    [self loadMergedLiveChannels];
}

- (void)liveGroupChanged:(id)sender {
    [self applyLiveFilterAndSort];
}

- (void)reloadLiveAction:(id)sender {
    [self loadMergedLiveChannels];
}

- (void)loadMergedLiveChannels {
    NSArray<TVLiveSource *> *sources = [self availableLiveSources];
    if (sources.count == 0) {
        self.liveChannels = @[];
        self.displayedLiveChannels = @[];
        [self rebuildLiveGroupPopup];
        [self.liveTable reloadData];
        [self setStatus:@"暂无直播源"];
        return;
    }

    NSMutableArray<TVLiveSource *> *targetSources = [NSMutableArray array];
    NSInteger selectedIndex = self.liveSourcePopup.indexOfSelectedItem;
    TVLiveSource *selected = (TVLiveSource *)self.liveSourcePopup.selectedItem.representedObject;
    if (selectedIndex > 0 && selected) {
        [targetSources addObject:selected];
    } else {
        [targetSources addObjectsFromArray:sources];
    }

    if (targetSources.count == 0) {
        self.liveChannels = @[];
        self.displayedLiveChannels = @[];
        [self rebuildLiveGroupPopup];
        [self.liveTable reloadData];
        [self setStatus:@""];
        return;
    }

    [self setStatus:@"正在加载并合并直播源…"];
    __block NSInteger remaining = (NSInteger)targetSources.count;
    __block NSMutableArray<NSDictionary *> *collected = [NSMutableArray array];

    for (TVLiveSource *source in targetSources) {
        TVLiveSource *sourceForRequest = source;
        NSURL *url = [NSURL URLWithString:sourceForRequest.url];
        if (!url) {
            remaining--;
            continue;
        }
        [self.config fetchStringFromURL:url completion:^(NSString * _Nullable text, NSError * _Nullable error) {
            if (!error && text.length > 0) {
                for (TVLiveChannel *channel in [self.config parseLiveChannelsFromText:text]) {
                    NSString *logo = [self liveLogoForChannel:channel source:sourceForRequest];
                    [collected addObject:@{@"channel": channel,
                                           @"sourceName": sourceForRequest.name ?: @"",
                                           @"logo": logo ?: @""}];
                }
            }
            remaining--;
            if (remaining <= 0) {
                self.liveChannels = [self mergeLiveChannels:collected];
                [self rebuildLiveGroupPopup];
                [self applyLiveFilterAndSort];
                [self setStatus:@""];
            }
        }];
    }
}

- (void)liveSearchChanged:(id)sender {
    [self applyLiveFilterAndSort];
}

- (void)applyLiveFilterAndSort {
    NSArray<TVLiveChannel *> *list = self.liveChannels ?: @[];

    NSString *query = [self.liveSearchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length > 0) {
        list = [list filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            TVLiveChannel *channel = (TVLiveChannel *)evaluatedObject;
            return [channel.name rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
        }]];
    }

    // 按分组名称过滤：选中“全部分组”时不过滤，否则仅显示该分组下的频道。
    NSString *groupName = self.liveGroupPopup.selectedItem.representedObject;
    if (groupName.length > 0) {
        list = [list filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            TVLiveChannel *channel = (TVLiveChannel *)evaluatedObject;
            return [channel.group isEqualToString:groupName];
        }]];
    }

    if (self.liveSortDescriptor) {
        list = [list sortedArrayUsingDescriptors:@[self.liveSortDescriptor]];
    }

    self.displayedLiveChannels = list;
    [self.liveTable reloadData];
    [self sizeLiveTableColumnsToFit];
}

// 依据当前合并后的直播频道列表重建“分组”下拉选项，第一个选项固定为“全部分组”。
- (void)rebuildLiveGroupPopup {
    NSString *previousGroup = self.liveGroupPopup.selectedItem.representedObject;

    NSMutableOrderedSet<NSString *> *groups = [NSMutableOrderedSet orderedSet];
    for (TVLiveChannel *channel in self.liveChannels) {
        NSString *group = [channel.group stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (group.length > 0) {
            [groups addObject:group];
        }
    }
    NSArray<NSString *> *sorted = [groups.array sortedArrayUsingSelector:@selector(localizedStandardCompare:)];

    [self.liveGroupPopup removeAllItems];
    [self.liveGroupPopup addItemWithTitle:@"全部分组"];
    for (NSString *group in sorted) {
        [self.liveGroupPopup addItemWithTitle:group];
        [self.liveGroupPopup.lastItem setRepresentedObject:group];
    }

    // 尽量恢复上次选中的分组；若该分组已不存在则回到“全部分组”。
    NSInteger restoreIndex = 0;
    if (previousGroup.length > 0) {
        NSInteger idx = [self.liveGroupPopup indexOfItemWithRepresentedObject:previousGroup];
        if (idx >= 0) {
            restoreIndex = idx;
        }
    }
    [self.liveGroupPopup selectItemAtIndex:restoreIndex];
}

// 根据当前直播列表的数据内容（频道名/分组/数据源来源/线路数）自动计算每列宽度，
// 使标题与内容完整显示而不被截断，并随数据变化自动伸缩。
- (void)sizeLiveTableColumnsToFit {
    NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize:13]};
    NSMutableDictionary<NSString *, NSNumber *> *maxWidths = [NSMutableDictionary dictionary];

    // 初始值取表头标题宽度
    for (NSTableColumn *column in self.liveTable.tableColumns) {
        NSString *identifier = column.identifier;
        if ([identifier isEqualToString:@"icon"]) continue;
        CGFloat headerWidth = [column.title sizeWithAttributes:attrs].width + 28;
        maxWidths[identifier] = @(headerWidth);
    }

    for (TVLiveChannel *channel in self.displayedLiveChannels) {
        [self bumpLiveColumnWidth:maxWidths key:@"channel" text:channel.name attrs:attrs];
        [self bumpLiveColumnWidth:maxWidths key:@"group" text:channel.group attrs:attrs];
        [self bumpLiveColumnWidth:maxWidths key:@"sources" text:channel.sourceNames attrs:attrs];
        [self bumpLiveColumnWidth:maxWidths key:@"lines"
                            text:[NSString stringWithFormat:@"%lu 线路", (unsigned long)channel.lines.count]
                           attrs:attrs];
    }

    // 限制单列最大宽度，避免个别超长名称把某列撑得过宽
    NSDictionary<NSString *, NSNumber *> *maxCaps = @{
        @"channel": @420,
        @"group": @260,
        @"sources": @380,
        @"lines": @120,
    };

    for (NSTableColumn *column in self.liveTable.tableColumns) {
        NSString *identifier = column.identifier;
        if ([identifier isEqualToString:@"icon"]) continue;
        NSNumber *width = maxWidths[identifier];
        if (width) {
            CGFloat finalWidth = MAX([width doubleValue], 60);
            NSNumber *cap = maxCaps[identifier];
            if (cap) {
                finalWidth = MIN(finalWidth, cap.doubleValue);
            }
            column.width = finalWidth;
        }
    }
}

- (void)bumpLiveColumnWidth:(NSMutableDictionary<NSString *, NSNumber *> *)maxWidths
                        key:(NSString *)key
                       text:(NSString *)text
                      attrs:(NSDictionary *)attrs {
    if (text.length == 0) return;
    CGFloat width = [text sizeWithAttributes:attrs].width + 28;
    NSNumber *existing = maxWidths[key];
    if (!existing || width > existing.doubleValue) {
        maxWidths[key] = @(width);
    }
}

- (NSString *)liveLogoForChannel:(TVLiveChannel *)channel source:(TVLiveSource *)source {
    NSString *logo = channel.logo;
    if (logo.length == 0) {
        logo = source.logo;
    }
    if (logo.length == 0) return @"";

    // 直播源配置中的 logo 通常为模板（如 https://epg.112114.xyz/logo/{name}.png），
    // 需要用频道名替换占位符，否则图片无法加载。
    if ([logo containsString:@"{name}"]) {
        NSString *encoded = [channel.name stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
        logo = [logo stringByReplacingOccurrencesOfString:@"{name}" withString:(encoded ?: channel.name)];
    }
    return logo;
}

- (NSArray<TVLiveChannel *> *)mergeLiveChannels:(NSArray<NSDictionary *> *)collected {
    // 先按频道名分组，保留每个频道的出现顺序
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *grouped = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];

    for (NSDictionary *entry in collected) {
        TVLiveChannel *channel = entry[@"channel"];
        NSString *key = channel.name ?: @"";
        if (key.length == 0) continue;

        NSMutableArray *list = grouped[key];
        if (!list) {
            list = [NSMutableArray array];
            grouped[key] = list;
            [order addObject:key];
        }
        [list addObject:@{@"sourceName": entry[@"sourceName"] ?: @"",
                          @"url": channel.url ?: @"",
                          @"group": channel.group ?: @"",
                          @"logo": entry[@"logo"] ?: @""}];
    }

    NSMutableArray<TVLiveChannel *> *result = [NSMutableArray array];
    for (NSString *key in order) {
        NSArray<NSDictionary *> *list = grouped[key];

        TVLiveChannel *target = [[TVLiveChannel alloc] init];
        target.name = key;

        // 统计每个数据源在该频道下出现的次数，用于生成“数据源+线路”完整名称
        NSMutableDictionary<NSString *, NSNumber *> *sourceLineCount = [NSMutableDictionary dictionary];
        for (NSDictionary *e in list) {
            NSString *sn = e[@"sourceName"];
            sourceLineCount[sn] = @([sourceLineCount[sn] integerValue] + 1);
        }

        NSMutableArray<TVLiveLine *> *lines = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSNumber *> *sourceSeen = [NSMutableDictionary dictionary];
        for (NSDictionary *e in list) {
            NSString *sn = e[@"sourceName"];
            NSString *url = e[@"url"];
            NSInteger count = [sourceLineCount[sn] integerValue];
            NSInteger seen = [sourceSeen[sn] integerValue] + 1;
            sourceSeen[sn] = @(seen);

            TVLiveLine *line = [[TVLiveLine alloc] init];
            line.sourceName = sn;
            line.url = url;
            if (count > 1) {
                line.name = [NSString stringWithFormat:@"%@ · 线路%ld", sn, (long)seen];
            } else {
                line.name = sn;
            }
            [lines addObject:line];

            if (target.group.length == 0 && [e[@"group"] length] > 0) target.group = e[@"group"];
            if (target.logo.length == 0 && [e[@"logo"] length] > 0) target.logo = e[@"logo"];
            if (target.url.length == 0) target.url = url;
        }
        target.lines = lines;
        [result addObject:target];
    }
    return result;
}

- (void)sourceRowDoubleClicked:(id)sender {
    NSInteger row = self.sourcesTable.clickedRow;
    if (row < 0 || row >= (NSInteger)self.sourceRows.count) return;
    NSDictionary *sourceRow = self.sourceRows[row];
    NSString *url = sourceRow[@"url"];
    if (url.length == 0) return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:url forType:NSPasteboardTypeString];
    [self setStatus:[NSString stringWithFormat:@"已复制数据源地址：%@", url]];
}

- (void)liveRowDoubleClicked:(id)sender {
    NSInteger row = self.liveTable.clickedRow;
    if (row < 0 || row >= (NSInteger)self.displayedLiveChannels.count) return;
    TVLiveChannel *channel = self.displayedLiveChannels[row];
    [self presentPlayerWithTitle:channel.name block:^(PlayerViewController *player) {
        [player playLiveChannels:self.displayedLiveChannels atIndex:row];
    }];
    self.currentHistoryItem = [self historyItemForLiveChannel:channel];
}

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
}

- (void)loadConfigURLRows {
    NSArray<NSString *> *vodURLs = [self.config configURLs];
    self.vodConfigURLField.stringValue = vodURLs.count > 0 ? vodURLs.firstObject : @"";
    NSArray<NSString *> *liveURLs = [self.config liveConfigURLs];
    self.liveConfigURLField.stringValue = liveURLs.count > 0 ? liveURLs.firstObject : @"";
}

- (void)saveConfigURLAction:(id)sender {
    // 结束当前编辑，确保已输入内容提交
    [self.view.window makeFirstResponder:nil];

    NSString *vodURL = [self.vodConfigURLField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *liveURL = [self.liveConfigURLField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // 未填写点播数据源时，仅保存直播数据源
    if (vodURL.length == 0) {
        [self.config saveConfigURLs:@[]];
        [self.config saveLiveConfigURLs:(liveURL.length > 0 ? @[liveURL] : @[])];
        [self loadConfigURLRows];
        [self reloadConfig];
        return;
    }

    // 点播数据源必须经过可访问、可解析、TVBox 格式验证后才能保存
    [self setStatus:@"正在验证点播数据源…"];
    [self.config validateVODConfigURL:vodURL completion:^(NSArray<TVLiveSource *> * _Nullable detectedLives, NSError * _Nullable error) {
        if (error) {
            [self setStatus:@""];
            [self showErrorAlertWithMessage:error.localizedDescription];
            return;
        }
        [self setStatus:@""];
        [self.config saveConfigURLs:@[vodURL]];

        // 该配置包含直播数据源时，提供列表供用户选择是否保存
        if (detectedLives.count > 0) {
            [self presentLiveSourcePicker:detectedLives completion:^(NSString * _Nullable chosenURL) {
                NSString *finalLive = chosenURL.length > 0 ? chosenURL : liveURL;
                [self.config saveLiveConfigURLs:(finalLive.length > 0 ? @[finalLive] : @[])];
                [self loadConfigURLRows];
                [self reloadConfig];
            }];
        } else {
            // 不包含直播数据：提示用户，并不从该地址保存直播数据源；仅保存用户手动填写的专属直播数据源
            [self showInfoAlertWithMessage:@"该点播数据源地址不包含直播数据，未从该地址保存直播数据源。"];
            [self.config saveLiveConfigURLs:(liveURL.length > 0 ? @[liveURL] : @[])];
            [self loadConfigURLRows];
            [self reloadConfig];
        }
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
- (void)presentLiveSourcePicker:(NSArray<TVLiveSource *> *)lives completion:(void (^)(NSString * _Nullable chosenURL))completion {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"该配置包含直播数据源";
    alert.informativeText = @"请选择要保存到直播数据源的地址（选择「不选择」则忽略）：";
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"不选择"];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 440, 26)];
    popup.pullsDown = NO;
    for (TVLiveSource *source in lives) {
        NSString *name = source.name.length > 0 ? source.name : @"未命名直播源";
        [popup addItemWithTitle:[NSString stringWithFormat:@"%@（%@）", name, (source.url ?: @"")]];
        [popup.lastItem setRepresentedObject:source.url];
    }
    alert.accessoryView = popup;

    void (^handleResponse)(NSModalResponse) = ^(NSModalResponse response) {
        NSString *chosen = nil;
        if (response == NSAlertFirstButtonReturn) {
            chosen = (NSString *)popup.selectedItem.representedObject;
        }
        if (completion) completion(chosen);
    };

    if (self.view.window) {
        [alert beginSheetModalForWindow:self.view.window completionHandler:handleResponse];
    } else {
        handleResponse([alert runModal]);
    }
}

#pragma mark - 历史记录

- (TVHistoryItem *)historyItemForVideo:(TVVideo *)video site:(TVSite *)site {
    TVHistoryItem *item = [[TVHistoryItem alloc] init];
    item.isLive = NO;
    item.title = video.name ?: @"";

    NSArray<TVPlaySource *> *sources = [video playSources];
    NSString *sourceName = @"";
    NSString *episodeName = @"";
    if (sources.count > 0) {
        sourceName = sources[0].name ?: @"";
        if (sources[0].episodes.count > 0) {
            episodeName = sources[0].episodes[0].name ?: @"";
        }
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (video.typeName.length > 0) [parts addObject:video.typeName];
    if (sourceName.length > 0) [parts addObject:sourceName];
    if (episodeName.length > 0) [parts addObject:episodeName];
    item.subtitle = [parts componentsJoinedByString:@" · "];
    item.posterURL = video.vodPic ?: @"";
    item.episodeName = episodeName;
    item.sourceIndex = 0;
    item.episodeIndex = 0;
    item.playbackTime = 0;
    item.date = [NSDate date];
    item.payload = @{@"vodId": @(video.vodId),
                     @"siteKey": site.key ?: @"",
                     @"name": video.name ?: @"",
                     @"typeName": video.typeName ?: @"",
                     @"vodPic": video.vodPic ?: @""};
    return item;
}

- (TVHistoryItem *)historyItemForLiveChannel:(TVLiveChannel *)channel {
    TVHistoryItem *item = [[TVHistoryItem alloc] init];
    item.isLive = YES;
    item.title = channel.name ?: @"";
    item.subtitle = channel.group.length > 0 ? [NSString stringWithFormat:@"分组：%@", channel.group] : @"";
    item.posterURL = channel.logo ?: @"";
    item.episodeName = @"";
    item.sourceIndex = 0;
    item.episodeIndex = 0;
    item.playbackTime = 0;
    item.date = [NSDate date];

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
    return item;
}

// 把当前正在播放的内容写入历史（用于关闭窗口或切换内容前落盘）。
- (void)finalizeCurrentHistory {
    if (!self.currentHistoryItem) return;
    PlayerViewController *player = (PlayerViewController *)self.playerWindow.contentViewController;
    if ([player isKindOfClass:[PlayerViewController class]]) {
        // 同步播放器当前状态，记录集数、线路、频道与播放时间等完整数据。
        [player syncPlaybackStateToHistoryItem:self.currentHistoryItem];
    }
    self.currentHistoryItem.date = [NSDate date];
    [self insertHistoryItem:self.currentHistoryItem];
    self.currentHistoryItem = nil;
}

- (void)insertHistoryItem:(TVHistoryItem *)item {
    if (!item || item.title.length == 0) return;
    // 去重：同一类型、同一名称、同一集数的记录只保留最新一条。
    for (NSInteger i = (NSInteger)self.historyItems.count - 1; i >= 0; i--) {
        TVHistoryItem *existing = self.historyItems[(NSUInteger)i];
        BOOL sameTitle = [existing.title isEqualToString:item.title];
        BOOL sameEpisode = [existing.episodeName isEqualToString:(item.episodeName ?: @"")];
        if (existing.isLive == item.isLive && sameTitle && sameEpisode) {
            [self.historyItems removeObjectAtIndex:(NSUInteger)i];
        }
    }
    [self.historyItems insertObject:item atIndex:0];
    // 仅保留最近 30 条播放记录。
    while (self.historyItems.count > kTVBoxHistoryLimit) {
        [self.historyItems removeLastObject];
    }
    [self saveHistory];
    [self.historyTable reloadData];
}

- (void)loadHistory {
    [self.historyItems removeAllObjects];
    NSArray *array = [[NSUserDefaults standardUserDefaults] arrayForKey:kTVBoxHistoryKey];
    if ([array isKindOfClass:[NSArray class]]) {
        for (id obj in array) {
            if ([obj isKindOfClass:[NSDictionary class]]) {
                TVHistoryItem *item = [TVHistoryItem historyItemFromDictionary:(NSDictionary *)obj];
                if (item) [self.historyItems addObject:item];
            }
        }
    }
    // 加载后同样裁剪到最近 30 条。
    while (self.historyItems.count > kTVBoxHistoryLimit) {
        [self.historyItems removeLastObject];
    }
    [self.historyTable reloadData];
}

- (void)saveHistory {
    NSMutableArray *array = [NSMutableArray array];
    for (TVHistoryItem *item in self.historyItems) {
        [array addObject:[item toDictionary]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:array forKey:kTVBoxHistoryKey];
}

- (void)clearHistoryAction:(id)sender {
    [self.historyItems removeAllObjects];
    [self saveHistory];
    [self.historyTable reloadData];
}

- (void)historyRowDoubleClicked:(id)sender {
    NSInteger row = self.historyTable.clickedRow;
    if (row < 0 || row >= (NSInteger)self.historyItems.count) return;
    [self resumeHistoryItem:self.historyItems[(NSUInteger)row]];
}

- (void)resumeHistoryItem:(TVHistoryItem *)item {
    if (!item) return;

    if (item.isLive) {
        TVLiveChannel *channel = [self liveChannelFromHistoryItem:item];
        if (channel.name.length == 0) return;
        [self presentPlayerWithTitle:channel.name block:^(PlayerViewController *player) {
            [player playLiveChannel:channel];
        }];
        self.currentHistoryItem = item;
        return;
    }

    // 点播：按站点与 vodId 重新获取播放信息后继续播放。
    NSString *siteKey = item.payload[@"siteKey"];
    NSInteger vodId = [item.payload[@"vodId"] integerValue];
    if (siteKey.length == 0 || vodId == 0) return;

    TVSite *site = nil;
    for (TVSite *s in self.config.vodSites) {
        if ([s.key isEqualToString:siteKey]) {
            site = s;
            break;
        }
    }
    if (!site) {
        [self setStatus:@"历史记录对应的数据源已不可用"];
        return;
    }

    NSInteger sourceIndex = item.sourceIndex;
    NSInteger episodeIndex = item.episodeIndex;
    NSTimeInterval resumeTime = item.playbackTime;

    [self setStatus:@"正在恢复播放…"];
    NSURL *url = [self.config vodURLForSite:site params:@{@"ac": @"detail", @"ids": [NSString stringWithFormat:@"%ld", (long)vodId]}];
    [self.config requestJSONFromURL:url completion:^(id _Nullable json, NSError * _Nullable error) {
        if (error) {
            [self setStatus:[NSString stringWithFormat:@"恢复播放失败：%@", error.localizedDescription]];
            return;
        }
        NSArray *list = ((NSDictionary *)json)[@"list"];
        if (![list isKindOfClass:[NSArray class]] || list.count == 0) {
            [self setStatus:@"恢复播放失败：未获取到播放信息"];
            return;
        }
        [self setStatus:@""];
        TVVideo *detail = [TVVideo videoFromDictionary:(NSDictionary *)list[0]];
        [self presentPlayerWithTitle:detail.name block:^(PlayerViewController *player) {
            [player resumeVideo:detail sourceIndex:sourceIndex episodeIndex:episodeIndex resumeTime:resumeTime];
        }];
        self.currentHistoryItem = item;
    }];
}

- (TVLiveChannel *)liveChannelFromHistoryItem:(TVHistoryItem *)item {
    TVLiveChannel *channel = [[TVLiveChannel alloc] init];
    channel.name = item.payload[@"name"] ?: (item.title ?: @"");
    channel.group = item.payload[@"group"] ?: @"";
    channel.logo = item.payload[@"logo"] ?: @"";
    channel.url = item.payload[@"url"] ?: @"";

    NSMutableArray<TVLiveLine *> *lines = [NSMutableArray array];
    for (id obj in item.payload[@"lines"]) {
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *d = (NSDictionary *)obj;
        TVLiveLine *line = [[TVLiveLine alloc] init];
        line.sourceName = d[@"sourceName"] ?: @"";
        line.name = d[@"name"] ?: @"";
        line.url = d[@"url"] ?: @"";
        [lines addObject:line];
    }
    channel.lines = lines;
    return channel;
}

- (NSString *)formatPlaybackTime:(NSTimeInterval)seconds {
    if (seconds <= 0) return @"未播放";
    NSInteger total = (NSInteger)seconds;
    NSInteger h = total / 3600;
    NSInteger m = (total % 3600) / 60;
    NSInteger s = total % 60;
    if (h > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

- (NSString *)formatHistoryDate:(NSDate *)date {
    if (!date) return @"";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    return [formatter stringFromDate:date];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.sidebar) return (NSInteger)self.sidebarItems.count;
    if (tableView == self.liveTable) return (NSInteger)self.displayedLiveChannels.count;
    if (tableView == self.sourcesTable) return (NSInteger)self.sourceRows.count;
    if (tableView == self.historyTable) return (NSInteger)self.historyItems.count;
    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.sidebar) {
        NSString *identifier = @"SidebarCell";
        NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = identifier;
            NSImageView *imageView = [[NSImageView alloc] init];
            imageView.translatesAutoresizingMaskIntoConstraints = NO;
            imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
            [cell addSubview:imageView];
            cell.imageView = imageView;
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.font = [NSFont systemFontOfSize:13];
            [cell addSubview:textField];
            cell.textField = textField;
            [NSLayoutConstraint activateConstraints:@[
                [imageView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
                [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [imageView.widthAnchor constraintEqualToConstant:18],
                [imageView.heightAnchor constraintEqualToConstant:18],
                [textField.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor constant:6],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        if (row < (NSInteger)self.sidebarItems.count) {
            cell.textField.stringValue = self.sidebarItems[row];
            cell.imageView.image = [self sidebarIconForRow:row];
        }
        return cell;
    }

    if (tableView == self.sourcesTable) {
        NSString *identifier = [@"Source-" stringByAppendingString:tableColumn.identifier];
        NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = identifier;
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [cell addSubview:textField];
            cell.textField = textField;
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        if (row < (NSInteger)self.sourceRows.count) {
            NSDictionary *sourceRow = self.sourceRows[row];
            if ([tableColumn.identifier isEqualToString:@"status"]) {
                NSString *status = sourceRow[@"status"] ?: @"检查中";
                cell.textField.stringValue = status;
                if ([status isEqualToString:@"可用"]) {
                    cell.textField.textColor = [NSColor systemGreenColor];
                } else if ([status isEqualToString:@"不可用"]) {
                    cell.textField.textColor = [NSColor systemRedColor];
                } else {
                    cell.textField.textColor = [NSColor secondaryLabelColor];
                }
            } else {
                cell.textField.stringValue = sourceRow[tableColumn.identifier] ?: @"";
                cell.textField.textColor = [NSColor labelColor];
            }
        }
        return cell;
    }

    if (tableView == self.historyTable) {
        NSString *identifier = [@"History-" stringByAppendingString:tableColumn.identifier];
        NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = identifier;
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            [cell addSubview:textField];
            cell.textField = textField;
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        if (row < (NSInteger)self.historyItems.count) {
            TVHistoryItem *item = self.historyItems[row];
            NSString *colID = tableColumn.identifier;
            if ([colID isEqualToString:@"name"]) {
                cell.textField.stringValue = item.title ?: @"";
            } else if ([colID isEqualToString:@"type"]) {
                cell.textField.stringValue = item.isLive ? @"直播" : @"点播";
            } else if ([colID isEqualToString:@"detail"]) {
                cell.textField.stringValue = item.subtitle ?: @"";
            } else if ([colID isEqualToString:@"progress"]) {
                cell.textField.stringValue = [self formatPlaybackTime:item.playbackTime];
            } else if ([colID isEqualToString:@"date"]) {
                cell.textField.stringValue = [self formatHistoryDate:item.date];
            }
        }
        return cell;
    }

    if (tableView == self.liveTable && [tableColumn.identifier isEqualToString:@"icon"]) {
        TVLiveIconCell *cell = [tableView makeViewWithIdentifier:@"icon" owner:self];
        if (!cell) {
            cell = [[TVLiveIconCell alloc] initWithFrame:NSMakeRect(0, 0, 36, 32)];
            cell.identifier = @"icon";
        }
        if (row < (NSInteger)self.displayedLiveChannels.count) {
            TVLiveChannel *channel = self.displayedLiveChannels[row];
            cell.channelKey = channel.name;
            cell.iconView.image = TVLetterIcon(channel.name);
            [self loadLiveLogoForChannel:channel intoCell:cell];
        }
        return cell;
    }

    NSString *identifier = tableColumn.identifier;
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = identifier;
        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:textField];
        cell.textField = textField;
        [NSLayoutConstraint activateConstraints:@[
            [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    if (row < (NSInteger)self.displayedLiveChannels.count) {
        TVLiveChannel *channel = self.displayedLiveChannels[row];
        if ([identifier isEqualToString:@"channel"]) {
            cell.textField.stringValue = channel.name ?: @"";
        } else if ([identifier isEqualToString:@"group"]) {
            cell.textField.stringValue = channel.group ?: @"";
        } else if ([identifier isEqualToString:@"sources"]) {
            cell.textField.stringValue = channel.sourceNames ?: @"";
        } else if ([identifier isEqualToString:@"lines"]) {
            cell.textField.stringValue = [NSString stringWithFormat:@"%lu 线路", (unsigned long)channel.lines.count];
        }
    }
    return cell;
}

- (void)loadLiveLogoForChannel:(TVLiveChannel *)channel intoCell:(TVLiveIconCell *)cell {
    NSURL *url = [NSURL URLWithString:channel.logo];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 10.0;
    [request setValue:@"okhttp/3.15" forHTTPHeaderField:@"User-Agent"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSImage *image = nil;
            if (!error && data) {
                image = [[NSImage alloc] initWithData:data];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (image && [cell.channelKey isEqualToString:channel.name]) {
                    cell.iconView.image = image;
                }
            });
        }] resume];
}

#pragma mark - NSTableViewDelegate

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors {
    if (tableView != self.liveTable) return;
    self.liveSortDescriptor = tableView.sortDescriptors.firstObject;
    [self applyLiveFilterAndSort];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tableView = notification.object;
    if (tableView == self.sidebar) {
        NSInteger row = tableView.selectedRow;
        if (row >= 0) {
            [self showContentViewAtIndex:row];
        }
    }
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (collectionView == self.vodCollectionView) return (NSInteger)self.videos.count;
    if (collectionView == self.searchCollectionView) return (NSInteger)self.searchResults.count;
    return 0;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    VODCollectionItem *item = (VODCollectionItem *)[collectionView makeItemWithIdentifier:kVODItemIdentifier forIndexPath:indexPath];

    NSArray<TVVideo *> *sourceArray = nil;
    if (collectionView == self.vodCollectionView) sourceArray = self.videos;
    if (collectionView == self.searchCollectionView) sourceArray = self.searchResults;

    if (sourceArray && indexPath.item < (NSInteger)sourceArray.count) {
        [item configureWithVideo:sourceArray[indexPath.item]];
    }
    return item;
}

#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (!indexPath) return;

    if (collectionView == self.vodCollectionView) {
        if (indexPath.item < (NSInteger)self.videos.count) {
            [self openVideo:self.videos[indexPath.item] site:[self selectedSiteForPopup:self.sitePopup]];
        }
    } else if (collectionView == self.searchCollectionView) {
        if (indexPath.item < (NSInteger)self.searchResults.count) {
            TVVideo *video = self.searchResults[indexPath.item];
            [self openVideo:video site:video.sourceSite];
        }
    }
}

#pragma mark - 工具

- (void)setStatus:(NSString *)text {
    self.statusLabel.stringValue = text ?: @"";
}

#pragma mark - 关于（邮箱操作）

- (void)copySupportEmailAction:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:@"ibmos_2@163.com" forType:NSPasteboardTypeString];
    [self setStatus:@"邮箱地址 ibmos_2@163.com 已复制到剪贴板"];
}

- (void)sendSupportEmailAction:(id)sender {
    NSURL *url = [NSURL URLWithString:@"mailto:ibmos_2@163.com"];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

@end