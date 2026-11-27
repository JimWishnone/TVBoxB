#import "MainViewController+Private.h"

@implementation MainViewController (VOD)

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
    // 若已存在详情模态窗（例如快速连续点击多个视频），先关闭旧的，
    // 避免多个 sheet 叠加导致按钮 target/action 指向失效。
    NSWindow *existingModal = self.detailModalWindow;
    if (existingModal) {
        self.detailModalWindow = nil;
        if (existingModal.sheetParent) {
            [existingModal.sheetParent endSheet:existingModal returnCode:NSModalResponseCancel];
        } else {
            [existingModal orderOut:nil];
        }
    }

    self.detailModalVideo = detail;
    self.detailModalSite = site;
    // 回填站点信息，供播放器记录“跳过片头片尾”等按站点区分的设置
    detail.sourceSite = site;

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

    // 收藏按钮：空心/填充星形图标切换收藏状态
    NSButton *favoriteButton = [NSButton buttonWithTitle:@"收藏" target:self action:@selector(detailModalFavoriteAction:)];
    favoriteButton.translatesAutoresizingMaskIntoConstraints = NO;
    favoriteButton.bezelStyle = NSBezelStyleRounded;
    favoriteButton.imagePosition = NSImageLeading;
    [root addSubview:favoriteButton];
    self.detailModalFavoriteButton = favoriteButton;

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

        [favoriteButton.topAnchor constraintEqualToAnchor:posterView.bottomAnchor constant:12],
        [favoriteButton.leadingAnchor constraintEqualToAnchor:posterView.leadingAnchor],

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
    [self updateDetailFavoriteButtonState];

    [self.view.window beginSheet:modal completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            [self beginPlaybackFromModal];
        }
        // 仅当详情窗引用仍是当前模态窗时才清空，避免误清新弹出的模态窗
        if (self.detailModalWindow == modal) {
            self.detailModalWindow = nil;
        }
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
    [TVImageLoader loadImageAtURL:urlString completion:^(NSImage * _Nullable image) {
        imageView.image = image ?: [VODCollectionItem defaultPosterImage];
    }];
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


@end
