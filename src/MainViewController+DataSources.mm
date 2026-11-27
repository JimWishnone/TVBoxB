#import "MainViewController+Private.h"

@implementation MainViewController (DataSources)

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
        [self rebuildSites];
        [self rebuildLiveSources];
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
    [self checkDataSourcesAvailabilityInteractive:YES];
}

- (void)checkDataSourcesAvailabilityInteractive:(BOOL)interactive {
    if (interactive) {
        [self showCheckingPanel];
    }
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
        [self rebuildSites];
        [self rebuildLiveSources];
        if (interactive) [self hideCheckingPanel];
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interactive ? 10.0 : 8.0) * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (generation != self.availabilityCheckGeneration) return;
        [self sortUnavailableSourcesToEnd];
        [self rebuildSites];
        [self rebuildLiveSources];
        if (interactive) [self hideCheckingPanel];
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
    NSMutableURLRequest *headRequest = [NSMutableURLRequest requestWithURL:url];
    headRequest.HTTPMethod = @"HEAD";
    headRequest.timeoutInterval = 5.0;
    headRequest.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [headRequest setValue:TVBoxHTTPUserAgent forHTTPHeaderField:@"User-Agent"];
    [headRequest setValue:@"*/*" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *headTask = [[NSURLSession sharedSession] dataTaskWithRequest:headRequest
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable headError) {
            NSInteger statusCode = -1;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                statusCode = ((NSHTTPURLResponse *)response).statusCode;
            }
            if (headError == nil && statusCode >= 200 && statusCode < 300) {
                if (completion) completion(@"可用");
                return;
            }
            if (statusCode == 405) {
                NSMutableURLRequest *getRequest = [NSMutableURLRequest requestWithURL:url];
                getRequest.HTTPMethod = @"GET";
                getRequest.timeoutInterval = 5.0;
                getRequest.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
                [getRequest setValue:TVBoxHTTPUserAgent forHTTPHeaderField:@"User-Agent"];
                [getRequest setValue:@"*/*" forHTTPHeaderField:@"Accept"];

                [[[NSURLSession sharedSession] dataTaskWithRequest:getRequest
                    completionHandler:^(NSData * _Nullable getData, NSURLResponse * _Nullable getResponse, NSError * _Nullable getError) {
                        NSInteger getStatusCode = -1;
                        if ([getResponse isKindOfClass:[NSHTTPURLResponse class]]) {
                            getStatusCode = ((NSHTTPURLResponse *)getResponse).statusCode;
                        }
                        BOOL available = (getError == nil && getStatusCode >= 200 && getStatusCode < 300);
                        if (completion) completion(available ? @"可用" : @"不可用");
                    }] resume];
                return;
            }
            if (completion) completion(@"不可用");
        }];
    [headTask resume];
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


@end
