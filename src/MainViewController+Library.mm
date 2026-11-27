#import "MainViewController+Private.h"

@implementation MainViewController (Library)

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
    if (![self saveHistoryEnabled]) return;
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
    // 仅保留用户设定的条数。
    while (self.historyItems.count > [self historyLimit]) {
        [self.historyItems removeLastObject];
    }
    [self saveHistory];
    [self.historyTable reloadData];
}

- (void)loadHistory {
    [self.historyItems removeAllObjects];
    // 关闭历史记录时不再加载已保存内容
    if (![self saveHistoryEnabled]) {
        [self.historyTable reloadData];
        return;
    }
    NSArray *array = [[NSUserDefaults standardUserDefaults] arrayForKey:kTVBoxHistoryKey];
    if ([array isKindOfClass:[NSArray class]]) {
        for (id obj in array) {
            if ([obj isKindOfClass:[NSDictionary class]]) {
                TVHistoryItem *item = [TVHistoryItem historyItemFromDictionary:(NSDictionary *)obj];
                if (item) [self.historyItems addObject:item];
            }
        }
    }
    // 加载后同样裁剪到用户设定的条数。
    while (self.historyItems.count > [self historyLimit]) {
        [self.historyItems removeLastObject];
    }
    [self.historyTable reloadData];
}

- (void)saveHistory {
    // 关闭历史记录时清除已保存内容
    if (![self saveHistoryEnabled]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kTVBoxHistoryKey];
        return;
    }
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

#pragma mark - 收藏夹

- (TVFavoriteItem *)favoriteItemForVideo:(TVVideo *)video site:(TVSite *)site {
    TVFavoriteItem *item = [[TVFavoriteItem alloc] init];
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
    item.payload = @{@"vodId": @(video.vodId),
                     @"siteKey": site.key ?: @"",
                     @"name": video.name ?: @"",
                     @"typeName": video.typeName ?: @"",
                     @"vodPic": video.vodPic ?: @""};
    return item;
}

- (TVFavoriteItem *)favoriteItemForLiveChannel:(TVLiveChannel *)channel {
    TVFavoriteItem *item = [[TVFavoriteItem alloc] init];
    item.isLive = YES;
    item.title = channel.name ?: @"";
    item.subtitle = channel.group.length > 0 ? [NSString stringWithFormat:@"分组：%@", channel.group] : @"";
    item.posterURL = channel.logo ?: @"";

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

- (NSInteger)favoriteIndexForVideo:(TVVideo *)video site:(TVSite *)site {
    for (NSUInteger i = 0; i < self.favoritesItems.count; i++) {
        TVFavoriteItem *item = self.favoritesItems[i];
        if (!item.isLive &&
            [item.payload[@"siteKey"] isEqualToString:site.key] &&
            [item.payload[@"vodId"] integerValue] == video.vodId) {
            return (NSInteger)i;
        }
    }
    return NSNotFound;
}

- (NSInteger)favoriteIndexForLiveChannel:(TVLiveChannel *)channel {
    for (NSUInteger i = 0; i < self.favoritesItems.count; i++) {
        TVFavoriteItem *item = self.favoritesItems[i];
        if (item.isLive && [item.title isEqualToString:channel.name]) {
            return (NSInteger)i;
        }
    }
    return NSNotFound;
}

- (BOOL)isVideoFavorited:(TVVideo *)video site:(TVSite *)site {
    return [self favoriteIndexForVideo:video site:site] != NSNotFound;
}

- (void)toggleLiveChannelFavorite:(TVLiveChannel *)channel {
    NSInteger index = [self favoriteIndexForLiveChannel:channel];
    if (index == NSNotFound) {
        [self.favoritesItems addObject:[self favoriteItemForLiveChannel:channel]];
    } else {
        [self.favoritesItems removeObjectAtIndex:(NSUInteger)index];
    }
    [self saveFavorites];
    [self.favoritesTable reloadData];
    [self.liveTable reloadData];
}

- (void)detailModalFavoriteAction:(id)sender {
    TVVideo *video = self.detailModalVideo;
    TVSite *site = self.detailModalSite;
    if (!video || !site) return;

    NSInteger index = [self favoriteIndexForVideo:video site:site];
    if (index == NSNotFound) {
        [self.favoritesItems addObject:[self favoriteItemForVideo:video site:site]];
    } else {
        [self.favoritesItems removeObjectAtIndex:(NSUInteger)index];
    }
    [self saveFavorites];
    [self.favoritesTable reloadData];
    [self updateDetailFavoriteButtonState];
}

- (void)updateDetailFavoriteButtonState {
    TVVideo *video = self.detailModalVideo;
    TVSite *site = self.detailModalSite;
    BOOL favorited = (video && site) && [self isVideoFavorited:video site:site];
    self.detailModalFavoriteButton.image = [NSImage imageWithSystemSymbolName:(favorited ? @"star.fill" : @"star")
                                                    accessibilityDescription:nil];
    self.detailModalFavoriteButton.title = favorited ? @"已收藏" : @"收藏";
}

- (void)loadFavorites {
    [self.favoritesItems removeAllObjects];
    NSArray *array = [[NSUserDefaults standardUserDefaults] arrayForKey:kTVBoxFavoritesKey];
    if ([array isKindOfClass:[NSArray class]]) {
        for (id obj in array) {
            if ([obj isKindOfClass:[NSDictionary class]]) {
                TVFavoriteItem *item = [TVFavoriteItem favoriteItemFromDictionary:(NSDictionary *)obj];
                if (item) [self.favoritesItems addObject:item];
            }
        }
    }
    [self.favoritesTable reloadData];
}

- (void)saveFavorites {
    NSMutableArray *array = [NSMutableArray array];
    for (TVFavoriteItem *item in self.favoritesItems) {
        [array addObject:[item toDictionary]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:array forKey:kTVBoxFavoritesKey];
}

- (void)favoriteRowDoubleClicked:(id)sender {
    NSInteger row = self.favoritesTable.clickedRow;
    if (row < 0 || row >= (NSInteger)self.favoritesItems.count) return;
    [self resumeFavoriteItem:self.favoritesItems[(NSUInteger)row]];
}

- (void)removeFavoriteAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.favoritesItems.count) return;
    [self.favoritesItems removeObjectAtIndex:(NSUInteger)index];
    [self saveFavorites];
    [self.favoritesTable reloadData];
    [self.liveTable reloadData];
}

- (TVLiveChannel *)liveChannelFromPayload:(NSDictionary *)payload fallbackTitle:(NSString *)title {
    TVLiveChannel *channel = [[TVLiveChannel alloc] init];
    channel.name = payload[@"name"] ?: (title ?: @"");
    channel.group = payload[@"group"] ?: @"";
    channel.logo = payload[@"logo"] ?: @"";
    channel.url = payload[@"url"] ?: @"";

    NSMutableArray<TVLiveLine *> *lines = [NSMutableArray array];
    for (id obj in payload[@"lines"]) {
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

- (void)resumeFavoriteItem:(TVFavoriteItem *)item {
    if (!item) return;

    if (item.isLive) {
        TVLiveChannel *channel = [self liveChannelFromPayload:item.payload fallbackTitle:item.title];
        if (channel.name.length == 0) return;
        [self presentPlayerWithTitle:channel.name block:^(PlayerViewController *player) {
            [player playLiveChannel:channel];
        }];
        return;
    }

    // 点播：按站点与 vodId 重新获取播放信息后播放。
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
        [self setStatus:@"收藏的视频对应的数据源已不可用"];
        return;
    }

    [self setStatus:@"正在获取播放信息…"];
    NSURL *url = [self.config vodURLForSite:site params:@{@"ac": @"detail", @"ids": [NSString stringWithFormat:@"%ld", (long)vodId]}];
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
        detail.sourceSite = site;
        [self presentPlayerWithTitle:detail.name block:^(PlayerViewController *player) {
            [player resumeVideo:detail sourceIndex:0 episodeIndex:0 resumeTime:0];
        }];
    }];
}

#pragma mark - 收藏夹拖拽排序

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    if (tableView != self.favoritesTable) return nil;
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setString:[NSString stringWithFormat:@"%ld", (long)row] forType:kTVBoxFavoriteDragType];
    return pbItem;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    if (tableView != self.favoritesTable) return NSDragOperationNone;
    if (dropOperation == NSTableViewDropOn) {
        [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    }
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
    if (tableView != self.favoritesTable) return NO;
    NSString *sourceString = [[info draggingPasteboard] stringForType:kTVBoxFavoriteDragType];
    if (sourceString.length == 0) return NO;

    NSInteger sourceRow = sourceString.integerValue;
    if (sourceRow < 0 || sourceRow >= (NSInteger)self.favoritesItems.count) return NO;

    TVFavoriteItem *item = self.favoritesItems[(NSUInteger)sourceRow];
    [self.favoritesItems removeObjectAtIndex:(NSUInteger)sourceRow];

    NSInteger destinationRow = row;
    if (destinationRow > (NSInteger)self.favoritesItems.count) {
        destinationRow = (NSInteger)self.favoritesItems.count;
    }
    [self.favoritesItems insertObject:item atIndex:(NSUInteger)destinationRow];

    [self saveFavorites];
    [self.favoritesTable reloadData];
    return YES;
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
        detail.sourceSite = site;
        [self presentPlayerWithTitle:detail.name block:^(PlayerViewController *player) {
            [player resumeVideo:detail sourceIndex:sourceIndex episodeIndex:episodeIndex resumeTime:resumeTime];
        }];
        self.currentHistoryItem = item;
    }];
}

- (TVLiveChannel *)liveChannelFromHistoryItem:(TVHistoryItem *)item {
    return [self liveChannelFromPayload:item.payload fallbackTitle:item.title];
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


@end
