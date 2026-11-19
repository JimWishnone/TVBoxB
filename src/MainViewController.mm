#import "MainViewController.h"
#import "ConfigManager.h"
#import "PlayerViewController.h"

static NSString *const kVODItemIdentifier = @"VODItemIdentifier";
static NSString *const kTVBoxHistoryKey = @"TVBoxHistory";
static const NSUInteger kTVBoxHistoryLimit = 30;

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
    self.posterView.layer.backgroundColor = [NSColor colorWithWhite:0.86 alpha:1.0].CGColor;

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
        [[NSColor colorWithWhite:0.88 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, 0, size.width, size.height));
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

@property (nonatomic, strong) NSTableView *settingsTable;
@property (nonatomic, strong) NSMutableArray<NSString *> *configURLRows;
@property (nonatomic, strong) NSTableView *liveSettingsTable;
@property (nonatomic, strong) NSMutableArray<NSString *> *liveConfigURLRows;

@property (nonatomic, strong) NSTableView *historyTable;
@property (nonatomic, strong) NSMutableArray<TVHistoryItem *> *historyItems;
@property (nonatomic, strong) TVHistoryItem *currentHistoryItem;

@property (nonatomic, strong) NSWindow *playerWindow;
@property (nonatomic, strong) NSTextField *statusLabel;

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
    self.configURLRows = [NSMutableArray array];
    self.liveConfigURLRows = [NSMutableArray array];
    self.selectedCategoryId = 0;
    self.historyItems = [NSMutableArray array];

    [self buildUI];
    [self loadHistory];

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

    NSArray<NSView *> *contentViews = @[self.dataSourcesView, self.searchView, self.vodView,
                                        self.liveView, self.historyView, self.settingsView, self.aboutView];
    for (NSView *view in contentViews) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentContainer addSubview:view];
        [NSLayoutConstraint activateConstraints:@[
            [view.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
            [view.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
            [view.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
            [view.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
        ]];
    }

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
    [root addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
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

    self.searchCollectionView = [self makeCollectionView];
    NSScrollView *gridScroll = [self makeScrollViewForCollectionView:self.searchCollectionView];

    [container addSubview:toolbar];
    [container addSubview:gridScroll];

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [toolbar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [toolbar.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-12],

        [self.searchField.widthAnchor constraintEqualToConstant:260],

        [gridScroll.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:10],
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

        [self.sitePopup.widthAnchor constraintGreaterThanOrEqualToConstant:180],
        [self.vodSearchField.widthAnchor constraintEqualToConstant:200],

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

    NSTextField *sourceLabel = [NSTextField labelWithString:@"直播源:"];
    self.liveSourcePopup = [[NSPopUpButton alloc] init];
    [self.liveSourcePopup setTarget:self];
    [self.liveSourcePopup setAction:@selector(liveSourceChanged:)];

    NSTextField *groupLabel = [NSTextField labelWithString:@"分组:"];
    self.liveGroupPopup = [[NSPopUpButton alloc] init];
    [self.liveGroupPopup setTarget:self];
    [self.liveGroupPopup setAction:@selector(liveGroupChanged:)];
    [self.liveGroupPopup addItemWithTitle:@"全部分组"];

    NSButton *reloadButton = [NSButton buttonWithTitle:@"刷新" target:self action:@selector(reloadLiveAction:)];
    reloadButton.bezelStyle = NSBezelStyleRounded;
    reloadButton.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"刷新"];
    reloadButton.imagePosition = NSImageLeading;

    self.liveSearchField = [[NSSearchField alloc] init];
    self.liveSearchField.placeholderString = @"按频道名称查找";
    self.liveSearchField.sendsSearchStringImmediately = YES;
    self.liveSearchField.target = self;
    self.liveSearchField.action = @selector(liveSearchChanged:);

    NSStackView *toolbar = [NSStackView stackViewWithViews:@[title, sourceLabel, self.liveSourcePopup, groupLabel, self.liveGroupPopup, reloadButton, self.liveSearchField]];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 12;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;

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

    [container addSubview:toolbar];
    [container addSubview:tableScroll];

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [toolbar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [toolbar.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-12],

        [self.liveSourcePopup.widthAnchor constraintGreaterThanOrEqualToConstant:220],
        [self.liveGroupPopup.widthAnchor constraintGreaterThanOrEqualToConstant:120],
        [self.liveSearchField.widthAnchor constraintGreaterThanOrEqualToConstant:160],

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

    NSTextField *hintLabel = [NSTextField labelWithString:@"视频数据源分为两个部分：点播数据源（主数据源，必填）与直播视频源（专属直播的数据源，选填）。直接点击地址单元格即可编辑，修改后点击「保存并重新加载」立即生效。"];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.font = [NSFont systemFontOfSize:12];
    hintLabel.textColor = [NSColor secondaryLabelColor];
    hintLabel.maximumNumberOfLines = 2;
    hintLabel.lineBreakMode = NSLineBreakByWordWrapping;

    // ---- 点播数据源（主数据源） ----
    NSTextField *vodTitle = [NSTextField labelWithString:@"点播数据源（主数据源）"];
    vodTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    vodTitle.translatesAutoresizingMaskIntoConstraints = NO;

    self.settingsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.settingsTable.identifier = @"settings";
    self.settingsTable.dataSource = self;
    self.settingsTable.delegate = self;
    self.settingsTable.usesAlternatingRowBackgroundColors = YES;
    self.settingsTable.rowHeight = 32;
    self.settingsTable.intercellSpacing = NSMakeSize(0, 4);
    self.settingsTable.allowsMultipleSelection = NO;
    self.settingsTable.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

    NSTableColumn *urlColumn = [[NSTableColumn alloc] initWithIdentifier:@"url"];
    urlColumn.title = @"数据源配置地址";
    urlColumn.width = 720;
    urlColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    [self.settingsTable addTableColumn:urlColumn];

    NSScrollView *vodTableScroll = [[NSScrollView alloc] init];
    vodTableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    vodTableScroll.hasVerticalScroller = YES;
    vodTableScroll.autohidesScrollers = YES;
    vodTableScroll.borderType = NSBezelBorder;
    vodTableScroll.documentView = self.settingsTable;

    NSButton *addButton = [NSButton buttonWithTitle:@"添加" target:self action:@selector(addConfigURLAction:)];
    addButton.bezelStyle = NSBezelStyleRounded;
    addButton.image = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"添加"];
    addButton.imagePosition = NSImageLeading;

    NSButton *deleteButton = [NSButton buttonWithTitle:@"删除" target:self action:@selector(deleteConfigURLAction:)];
    deleteButton.bezelStyle = NSBezelStyleRounded;
    deleteButton.image = [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"删除"];
    deleteButton.imagePosition = NSImageLeading;

    NSButton *resetButton = [NSButton buttonWithTitle:@"恢复默认" target:self action:@selector(resetConfigURLAction:)];
    resetButton.bezelStyle = NSBezelStyleRounded;
    resetButton.image = [NSImage imageWithSystemSymbolName:@"arrow.counterclockwise" accessibilityDescription:@"恢复默认"];
    resetButton.imagePosition = NSImageLeading;

    NSStackView *vodButtonBar = [NSStackView stackViewWithViews:@[addButton, deleteButton, resetButton]];
    vodButtonBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    vodButtonBar.spacing = 12;
    vodButtonBar.translatesAutoresizingMaskIntoConstraints = NO;

    // ---- 直播视频源（专属直播的数据源，选填） ----
    NSTextField *liveTitle = [NSTextField labelWithString:@"直播视频源（专属直播的数据源，选填）"];
    liveTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    liveTitle.translatesAutoresizingMaskIntoConstraints = NO;

    self.liveSettingsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.liveSettingsTable.identifier = @"liveSettings";
    self.liveSettingsTable.dataSource = self;
    self.liveSettingsTable.delegate = self;
    self.liveSettingsTable.usesAlternatingRowBackgroundColors = YES;
    self.liveSettingsTable.rowHeight = 32;
    self.liveSettingsTable.intercellSpacing = NSMakeSize(0, 4);
    self.liveSettingsTable.allowsMultipleSelection = NO;
    self.liveSettingsTable.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

    NSTableColumn *liveURLColumn = [[NSTableColumn alloc] initWithIdentifier:@"url"];
    liveURLColumn.title = @"直播数据源配置地址";
    liveURLColumn.width = 720;
    liveURLColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    [self.liveSettingsTable addTableColumn:liveURLColumn];

    NSScrollView *liveTableScroll = [[NSScrollView alloc] init];
    liveTableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    liveTableScroll.hasVerticalScroller = YES;
    liveTableScroll.autohidesScrollers = YES;
    liveTableScroll.borderType = NSBezelBorder;
    liveTableScroll.documentView = self.liveSettingsTable;

    NSButton *addLiveButton = [NSButton buttonWithTitle:@"添加" target:self action:@selector(addLiveConfigURLAction:)];
    addLiveButton.bezelStyle = NSBezelStyleRounded;
    addLiveButton.image = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"添加"];
    addLiveButton.imagePosition = NSImageLeading;

    NSButton *deleteLiveButton = [NSButton buttonWithTitle:@"删除" target:self action:@selector(deleteLiveConfigURLAction:)];
    deleteLiveButton.bezelStyle = NSBezelStyleRounded;
    deleteLiveButton.image = [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"删除"];
    deleteLiveButton.imagePosition = NSImageLeading;

    NSButton *clearLiveButton = [NSButton buttonWithTitle:@"清空" target:self action:@selector(clearLiveConfigURLAction:)];
    clearLiveButton.bezelStyle = NSBezelStyleRounded;
    clearLiveButton.image = [NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:@"清空"];
    clearLiveButton.imagePosition = NSImageLeading;

    NSStackView *liveButtonBar = [NSStackView stackViewWithViews:@[addLiveButton, deleteLiveButton, clearLiveButton]];
    liveButtonBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    liveButtonBar.spacing = 12;
    liveButtonBar.translatesAutoresizingMaskIntoConstraints = NO;

    // ---- 保存 ----
    NSButton *saveButton = [NSButton buttonWithTitle:@"保存并重新加载" target:self action:@selector(saveConfigURLAction:)];
    saveButton.bezelStyle = NSBezelStyleRounded;
    saveButton.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle" accessibilityDescription:@"保存"];
    saveButton.imagePosition = NSImageLeading;
    saveButton.translatesAutoresizingMaskIntoConstraints = NO;

    [container addSubview:title];
    [container addSubview:hintLabel];
    [container addSubview:vodTitle];
    [container addSubview:vodTableScroll];
    [container addSubview:vodButtonBar];
    [container addSubview:liveTitle];
    [container addSubview:liveTableScroll];
    [container addSubview:liveButtonBar];
    [container addSubview:saveButton];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:container.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [hintLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [hintLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [hintLabel.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-16],

        [vodTitle.topAnchor constraintEqualToAnchor:hintLabel.bottomAnchor constant:18],
        [vodTitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [vodTableScroll.topAnchor constraintEqualToAnchor:vodTitle.bottomAnchor constant:8],
        [vodTableScroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [vodTableScroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [vodTableScroll.heightAnchor constraintEqualToConstant:160],

        [vodButtonBar.topAnchor constraintEqualToAnchor:vodTableScroll.bottomAnchor constant:10],
        [vodButtonBar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [vodButtonBar.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-16],

        [liveTitle.topAnchor constraintEqualToAnchor:vodButtonBar.bottomAnchor constant:20],
        [liveTitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [liveTableScroll.topAnchor constraintEqualToAnchor:liveTitle.bottomAnchor constant:8],
        [liveTableScroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [liveTableScroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [liveTableScroll.heightAnchor constraintEqualToConstant:160],

        [liveButtonBar.topAnchor constraintEqualToAnchor:liveTableScroll.bottomAnchor constant:10],
        [liveButtonBar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [liveButtonBar.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-16],

        [saveButton.topAnchor constraintEqualToAnchor:liveButtonBar.bottomAnchor constant:16],
        [saveButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
    ]];

    [self loadConfigURLRows];
    return container;
}

- (NSView *)buildAboutView {
    NSView *container = [[NSView alloc] init];

    NSTextField *title = [NSTextField labelWithString:@"TVBoxB"];
    title.font = [NSFont systemFontOfSize:28 weight:NSFontWeightBold];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *version = [NSTextField labelWithString:@"版本 v0.0.1"];
    version.textColor = [NSColor secondaryLabelColor];
    version.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *desc = [NSTextField wrappingLabelWithString:@"基于 macOS 原生界面的视频播放软件，支持视频点播与视频直播功能。\n点播与直播数据均来自 TVbox 官方配置源（official.json）。"];
    desc.translatesAutoresizingMaskIntoConstraints = NO;
    desc.maximumNumberOfLines = 0;
    desc.alignment = NSTextAlignmentCenter;

    [container addSubview:title];
    [container addSubview:version];
    [container addSubview:desc];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:container.topAnchor constant:80],
        [title.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],

        [version.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [version.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],

        [desc.topAnchor constraintEqualToAnchor:version.bottomAnchor constant:20],
        [desc.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:40],
        [desc.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-40],
    ]];
    return container;
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
    NSArray<NSView *> *views = @[self.dataSourcesView, self.searchView, self.vodView,
                                 self.liveView, self.historyView, self.settingsView, self.aboutView];
    for (NSInteger i = 0; i < (NSInteger)views.count; i++) {
        views[i].hidden = (i != index);
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
}

- (void)performSearch:(id)sender {
    NSString *keyword = [self.searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (keyword.length == 0) {
        self.searchResults = @[];
        [self.searchCollectionView reloadData];
        [self setStatus:@""];
        return;
    }

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
                self.searchResults = results;
                [self.searchCollectionView reloadData];
                [self setStatus:@""];
            }
        }];
    }
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
        [self presentPlayerWithTitle:detail.name block:^(PlayerViewController *player) {
            [player playVideo:detail];
        }];
        self.currentHistoryItem = [self historyItemForVideo:detail site:site];
    }];
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
    [self.configURLRows removeAllObjects];
    [self.configURLRows addObjectsFromArray:[self.config configURLs]];
    [self.liveConfigURLRows removeAllObjects];
    [self.liveConfigURLRows addObjectsFromArray:[self.config liveConfigURLs]];
    [self.settingsTable reloadData];
    [self.liveSettingsTable reloadData];
}

- (void)addConfigURLAction:(id)sender {
    [self.configURLRows addObject:@""];
    [self.settingsTable reloadData];
    NSInteger row = (NSInteger)self.configURLRows.count - 1;
    [self.settingsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self.settingsTable scrollRowToVisible:row];
}

- (void)deleteConfigURLAction:(id)sender {
    NSInteger row = self.settingsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.configURLRows.count) return;
    [self.configURLRows removeObjectAtIndex:(NSUInteger)row];
    [self.settingsTable reloadData];
}

- (void)addLiveConfigURLAction:(id)sender {
    [self.liveConfigURLRows addObject:@""];
    [self.liveSettingsTable reloadData];
    NSInteger row = (NSInteger)self.liveConfigURLRows.count - 1;
    [self.liveSettingsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self.liveSettingsTable scrollRowToVisible:row];
}

- (void)deleteLiveConfigURLAction:(id)sender {
    NSInteger row = self.liveSettingsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.liveConfigURLRows.count) return;
    [self.liveConfigURLRows removeObjectAtIndex:(NSUInteger)row];
    [self.liveSettingsTable reloadData];
}

- (void)clearLiveConfigURLAction:(id)sender {
    [self.liveConfigURLRows removeAllObjects];
    [self.liveSettingsTable reloadData];
}

- (void)resetConfigURLAction:(id)sender {
    [self.config resetConfigURLs];
    [self.config resetLiveConfigURLs];
    [self loadConfigURLRows];
    [self reloadConfig];
}

- (void)saveConfigURLAction:(id)sender {
    // 结束当前编辑，确保已输入内容提交到数据模型
    [self.view.window makeFirstResponder:nil];
    [self.config saveConfigURLs:self.configURLRows];
    [self.config saveLiveConfigURLs:self.liveConfigURLRows];
    [self loadConfigURLRows];
    [self reloadConfig];
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
    if (tableView == self.settingsTable) return (NSInteger)self.configURLRows.count;
    if (tableView == self.liveSettingsTable) return (NSInteger)self.liveConfigURLRows.count;
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

    if (tableView == self.settingsTable || tableView == self.liveSettingsTable) {
        NSString *identifier = (tableView == self.settingsTable) ? @"SettingsCell" : @"LiveSettingsCell";
        NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = identifier;
            NSTextField *textField = [NSTextField textFieldWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.font = [NSFont systemFontOfSize:13];
            textField.editable = YES;
            textField.delegate = self;
            [cell addSubview:textField];
            cell.textField = textField;
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        NSArray<NSString *> *rows = (tableView == self.settingsTable) ? self.configURLRows : self.liveConfigURLRows;
        if (row < (NSInteger)rows.count) {
            cell.textField.stringValue = rows[row];
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

#pragma mark - NSControlTextEditingDelegate

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *textField = notification.object;

    NSInteger row = [self.settingsTable rowForView:textField];
    if (row >= 0 && row < (NSInteger)self.configURLRows.count) {
        self.configURLRows[(NSUInteger)row] = textField.stringValue ?: @"";
        return;
    }

    row = [self.liveSettingsTable rowForView:textField];
    if (row >= 0 && row < (NSInteger)self.liveConfigURLRows.count) {
        self.liveConfigURLRows[(NSUInteger)row] = textField.stringValue ?: @"";
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

@end