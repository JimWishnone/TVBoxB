#import "MainViewController+Private.h"
#import <CoreImage/CoreImage.h>

@implementation MainViewController (UI)

#pragma mark - UI 构建

- (void)buildUI {
    NSView *root = self.view;

    self.sidebarItems = @[@"TVBox数据源列表", @"搜索", @"点播", @"直播", @"收藏夹", @"历史", @"设置", @"关于"];
    [self buildSidebar];
    self.dataSourcesView = [self buildDataSourcesView];
    self.searchView = [self buildSearchView];
    self.vodView = [self buildVODView];
    self.liveView = [self buildLiveView];
    self.favoritesView = [self buildFavoritesView];
    self.historyView = [self buildHistoryView];
    self.settingsView = [self buildSettingsView];
    self.aboutView = [self buildAboutView];

    self.contentContainer = [[NSView alloc] init];
    self.contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.contentContainer];

    self.contentViews = @[self.dataSourcesView, self.searchView, self.vodView,
                          self.liveView, self.favoritesView, self.historyView, self.settingsView, self.aboutView];
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

- (NSView *)buildFavoritesView {
    NSView *container = [[NSView alloc] init];

    NSTextField *title = [NSTextField labelWithString:@"收藏夹"];
    title.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *hint = [NSTextField labelWithString:@"拖动调整顺序 · 悬停删除 · 双击播放"];
    hint.font = [NSFont systemFontOfSize:12];
    hint.textColor = [NSColor secondaryLabelColor];
    hint.translatesAutoresizingMaskIntoConstraints = NO;

    self.favoritesTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.favoritesTable.identifier = @"favorites";
    self.favoritesTable.dataSource = self;
    self.favoritesTable.delegate = self;
    self.favoritesTable.usesAlternatingRowBackgroundColors = YES;
    self.favoritesTable.rowHeight = 36;
    self.favoritesTable.allowsColumnResizing = YES;
    self.favoritesTable.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    self.favoritesTable.target = self;
    self.favoritesTable.doubleAction = @selector(favoriteRowDoubleClicked:);
    [self.favoritesTable registerForDraggedTypes:@[kTVBoxFavoriteDragType]];
    [self.favoritesTable setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"名称";
    nameColumn.width = 300;
    nameColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;

    NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeColumn.title = @"类型";
    typeColumn.width = 80;
    typeColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;

    NSTableColumn *detailColumn = [[NSTableColumn alloc] initWithIdentifier:@"detail"];
    detailColumn.title = @"详情";
    detailColumn.width = 420;
    detailColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;

    [self.favoritesTable addTableColumn:nameColumn];
    [self.favoritesTable addTableColumn:typeColumn];
    [self.favoritesTable addTableColumn:detailColumn];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = self.favoritesTable;

    [container addSubview:title];
    [container addSubview:hint];
    [container addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],

        [hint.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [hint.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],

        [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [scroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [scroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
        [scroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12],
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
                                     @"star",
                                     @"clock",
                                     @"gearshape",
                                     @"info.circle"];
    if (row >= 0 && row < (NSInteger)symbols.count) {
        return [NSImage imageWithSystemSymbolName:symbols[row] accessibilityDescription:self.sidebarItems[row]];
    }
    return nil;
}


@end
