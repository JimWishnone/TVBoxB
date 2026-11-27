#import "MainViewController+Private.h"

@implementation MainViewController (Live)

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
    __block BOOL mergeDone = NO;

    void (^finishMerge)(void) = ^{
        if (mergeDone) return;
        mergeDone = YES;
        self.liveChannels = [self mergeLiveChannels:collected];
        [self rebuildLiveGroupPopup];
        [self applyLiveFilterAndSort];
        [self setStatus:@""];
        [self loadProgramSchedulesForChannels:self.liveChannels];
    };

    for (TVLiveSource *source in targetSources) {
        TVLiveSource *sourceForRequest = source;
        NSURL *url = [NSURL URLWithString:sourceForRequest.url];
        if (!url) {
            remaining--;
            continue;
        }
        [self.config fetchStringFromURL:url completion:^(NSString * _Nullable text, NSError * _Nullable error) {
            if (!error && text.length > 0) {
                for (TVLiveChannel *channel in [TVLiveSourceParser parseLiveChannelsFromText:text]) {
                    NSString *logo = [self liveLogoForChannel:channel source:sourceForRequest];
                    [collected addObject:@{@"channel": channel,
                                           @"sourceName": sourceForRequest.name ?: @"",
                                           @"logo": logo ?: @""}];
                }
            }
            remaining--;
            if (remaining <= 0) {
                finishMerge();
            }
        }];
    }

    if (remaining <= 0) {
        finishMerge();
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!mergeDone) {
            finishMerge();
        }
    });
}

// 当前直播场景使用的 EPG 地址：优先取选中的直播源，否则取第一个携带 epg 的可用直播源
- (NSString *)currentLiveEPGURL {
    TVLiveSource *selected = (TVLiveSource *)self.liveSourcePopup.selectedItem.representedObject;
    if (selected && selected.epg.length > 0) {
        return selected.epg;
    }
    for (TVLiveSource *source in [self availableLiveSources]) {
        if (source.epg.length > 0) {
            return source.epg;
        }
    }
    return nil;
}

// 后台批量拉取各频道的节目单，成功后逐条刷新表格，频道有节目单时显示“节目单”链接
- (void)loadProgramSchedulesForChannels:(NSArray<TVLiveChannel *> *)channels {
    NSString *epgURL = [self currentLiveEPGURL];
    if (epgURL.length == 0) {
        for (TVLiveChannel *channel in channels) {
            channel.programs = @[];
        }
        return;
    }

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (TVLiveChannel *channel in channels) {
        if (channel.name.length > 0 && ![names containsObject:channel.name]) {
            [names addObject:channel.name];
        }
    }
    if (names.count == 0) return;

    NSInteger generation = ++self.liveEPGGeneration;
    [self.config fetchProgramsForChannels:names
                                   epgURL:epgURL
                               completion:^(NSDictionary<NSString *, NSArray<TVLiveProgram *> *> *results) {
        if (generation != self.liveEPGGeneration) return;
        for (TVLiveChannel *channel in channels) {
            NSArray<TVLiveProgram *> *programs = results[channel.name];
            channel.programs = (programs.count > 0) ? programs : @[];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == self.liveEPGGeneration) {
                [self.liveTable reloadData];
            }
        });
    }];
}

// 弹出模态窗体显示某个频道的节目单
- (void)showProgramScheduleForChannel:(TVLiveChannel *)channel {
    NSArray<TVLiveProgram *> *programs = channel.programs ?: @[];
    if (programs.count == 0) return;

    self.programModalItems = programs;

    NSWindow *modal = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 560)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    modal.title = [NSString stringWithFormat:@"%@ · 节目单", channel.name ?: @""];
    modal.releasedWhenClosed = NO;
    self.programModalWindow = modal;

    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 560)];
    modal.contentView = root;

    NSTextField *header = [NSTextField labelWithString:[NSString stringWithFormat:@"%@（共 %lu 条）", channel.name ?: @"", (unsigned long)programs.count]];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.font = [NSFont boldSystemFontOfSize:15];
    header.lineBreakMode = NSLineBreakByTruncatingTail;
    [root addSubview:header];

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.dataSource = self;
    table.delegate = self;
    table.usesAlternatingRowBackgroundColors = YES;
    table.rowHeight = 26;
    table.allowsColumnResizing = YES;

    NSTableColumn *timeColumn = [[NSTableColumn alloc] initWithIdentifier:@"time"];
    timeColumn.title = @"时间";
    timeColumn.width = 110;
    timeColumn.minWidth = 90;
    timeColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;

    NSTableColumn *titleColumn = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    titleColumn.title = @"节目";
    titleColumn.width = 330;
    titleColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;

    [table addTableColumn:timeColumn];
    [table addTableColumn:titleColumn];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = table;
    [root addSubview:scroll];

    NSButton *closeButton = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(programModalCloseAction:)];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    closeButton.bezelStyle = NSBezelStyleRounded;
    closeButton.keyEquivalent = @"\e";
    [root addSubview:closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:root.topAnchor constant:14],
        [header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16],
        [header.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-16],

        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:12],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12],
        [scroll.bottomAnchor constraintEqualToAnchor:closeButton.topAnchor constant:-10],

        [closeButton.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [closeButton.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-12],
    ]];

    self.programTable = table;
    [self.view.window beginSheet:modal completionHandler:^(NSModalResponse returnCode) {
        self.programTable = nil;
        self.programModalItems = nil;
        self.programModalWindow = nil;
    }];
}

- (void)programModalCloseAction:(id)sender {
    if (self.programModalWindow) {
        [self.view.window endSheet:self.programModalWindow];
        [self.programModalWindow orderOut:nil];
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

- (void)liveTableScrolled:(NSNotification *)note {
    [self refreshLiveHoverStates];
}

- (void)refreshLiveHoverStates {
    NSInteger channelColumn = [self.liveTable columnWithIdentifier:@"channel"];
    if (channelColumn < 0) return;
    NSRect visible = self.liveTable.visibleRect;
    NSRange range = [self.liveTable rowsInRect:visible];
    NSInteger end = (NSInteger)(range.location + range.length);
    for (NSInteger row = range.location; row < end; row++) {
        NSView *view = [self.liveTable viewAtColumn:channelColumn row:row makeIfNecessary:NO];
        if ([view isKindOfClass:[TVChannelCellView class]]) {
            [(TVChannelCellView *)view refreshHoverState];
        }
    }
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


@end
