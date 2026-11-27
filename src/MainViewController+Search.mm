#import "MainViewController+Private.h"

@implementation MainViewController (Search)

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


@end
