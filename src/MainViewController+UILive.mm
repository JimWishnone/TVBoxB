#import "MainViewController+Private.h"

@implementation MainViewController (UILive)

#pragma mark - 直播页构建

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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(liveTableScrolled:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:tableScroll.contentView];

    return container;
}

@end
