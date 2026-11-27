#import "ConfigManager.h"

@implementation ConfigManager (EPG)

#pragma mark - 节目单（EPG）

// EPG 磁盘缓存目录：~/Library/Caches/TVBox/EPGCache
static NSString *TVBoxEPGCacheDirectory(void) {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        dir = [[caches stringByAppendingPathComponent:@"TVBox"] stringByAppendingPathComponent:@"EPGCache"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return dir;
}

// 节目单缓存有效期：2 小时，过期后重新拉取
static const NSTimeInterval kTVBoxEPGCacheTTL = 2 * 60 * 60;

static NSString *TVBoxEPGCachePath(NSString *epgURL, NSString *channelKey) {
    NSString *hashKey = [NSString stringWithFormat:@"%@|%@", epgURL, channelKey];
    return [TVBoxEPGCacheDirectory() stringByAppendingPathComponent:[TVBoxHexHash(hashKey) stringByAppendingString:@".txt"]];
}

// 读取未过期的缓存文本，未命中或已过期返回 nil
static NSString *TVBoxEPGCachedText(NSString *epgURL, NSString *channelKey) {
    NSString *path = TVBoxEPGCachePath(epgURL, channelKey);
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *modified = attrs[NSFileModificationDate];
    if (modified && [[NSDate date] timeIntervalSinceDate:modified] < kTVBoxEPGCacheTTL) {
        return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    }
    return nil;
}

static void TVBoxEPGStoreText(NSString *text, NSString *epgURL, NSString *channelKey) {
    if (text.length == 0) return;
    [text writeToFile:TVBoxEPGCachePath(epgURL, channelKey) atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)fetchProgramsForChannel:(NSString *)channelName
                        epgURL:(NSString *)epgURL
                    completion:(void (^)(NSArray<TVLiveProgram *> * _Nullable programs))completion {
    if (channelName.length == 0 || epgURL.length == 0) {
        if (completion) completion(@[]);
        return;
    }

    // 命中未过期的本地缓存时直接解析返回，避免重复拉取
    NSString *cachedText = TVBoxEPGCachedText(epgURL, channelName);
    if (cachedText) {
        if (completion) completion([self parseProgramsFromText:cachedText]);
        return;
    }

    NSURL *url = [self epgQueryURLForBase:epgURL channelName:channelName];
    if (!url) {
        if (completion) completion(@[]);
        return;
    }
    [self fetchStringFromURL:url completion:^(NSString * _Nullable text, NSError * _Nullable error) {
        if (error || text.length == 0) {
            if (completion) completion(@[]);
            return;
        }
        TVBoxEPGStoreText(text, epgURL, channelName);
        NSArray<TVLiveProgram *> *programs = [self parseProgramsFromText:text];
        if (programs.count > 0) {
            if (completion) completion(programs);
            return;
        }
        // 原始频道名匹配不到节目单时，尝试规范化频道名（如 “CCTV-1 综合” → “CCTV1”）再查询一次
        NSString *normalized = [self normalizedEPGChannelName:channelName];
        if ([normalized isEqualToString:channelName]) {
            if (completion) completion(@[]);
            return;
        }
        NSURL *retryURL = [self epgQueryURLForBase:epgURL channelName:normalized];
        if (!retryURL) {
            if (completion) completion(@[]);
            return;
        }
        [self fetchStringFromURL:retryURL completion:^(NSString * _Nullable retryText, NSError * _Nullable retryError) {
            NSArray<TVLiveProgram *> *retryPrograms = @[];
            if (!retryError && retryText.length > 0) {
                TVBoxEPGStoreText(retryText, epgURL, normalized);
                retryPrograms = [self parseProgramsFromText:retryText];
            }
            if (completion) completion(retryPrograms);
        }];
    }];
}

// 批量拉取多个频道的节目单：
// 优先尝试一次性请求整份 XMLTV 节目单并按频道分发（大幅减少网络请求）；
// 非 XMLTV（DIYP / 112114 等按频道返回 JSON）时回退到逐频道请求（带本地缓存）。
// 返回字典以“请求时传入的频道名”为键。
- (void)fetchProgramsForChannels:(NSArray<NSString *> *)channelNames
                          epgURL:(NSString *)epgURL
                      completion:(void (^)(NSDictionary<NSString *, NSArray<TVLiveProgram *> *> * _Nonnull results))completion {
    if (channelNames.count == 0 || epgURL.length == 0) {
        if (completion) completion(@{});
        return;
    }

    // 模板地址（含 {name}/{channel}）无法整份拉取，直接走逐频道分支
    if ([epgURL containsString:@"{name}"] || [epgURL containsString:@"{channel}"]) {
        [self fetchProgramsForChannelsIndividually:channelNames epgURL:epgURL completion:completion];
        return;
    }

    // 整份 XMLTV 节目单也做磁盘缓存，键为特殊标记
    NSString *batchKey = @"__ALL__";
    NSString *cachedBatch = TVBoxEPGCachedText(epgURL, batchKey);
    if (cachedBatch) {
        [self distributeProgramsByChannel:cachedBatch channelNames:channelNames completion:completion];
        return;
    }

    NSURL *baseURL = [NSURL URLWithString:epgURL];
    if (!baseURL) {
        [self fetchProgramsForChannelsIndividually:channelNames epgURL:epgURL completion:completion];
        return;
    }
    [self fetchStringFromURL:baseURL completion:^(NSString * _Nullable text, NSError * _Nullable error) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!error && trimmed.length > 0 && [trimmed hasPrefix:@"<"]) {
            // XMLTV 整份节目单：缓存并按频道分发
            TVBoxEPGStoreText(trimmed, epgURL, batchKey);
            [self distributeProgramsByChannel:trimmed channelNames:channelNames completion:completion];
            return;
        }
        [self fetchProgramsForChannelsIndividually:channelNames epgURL:epgURL completion:completion];
    }];
}

// 将整份 XMLTV 节目单按请求的频道名分发，返回以频道名为键的结果字典
- (void)distributeProgramsByChannel:(NSString *)xml
                       channelNames:(NSArray<NSString *> *)channelNames
                         completion:(void (^)(NSDictionary<NSString *, NSArray<TVLiveProgram *> *> * _Nonnull results))completion {
    NSDictionary<NSString *, NSArray<TVLiveProgram *> *> *byChannel = [self parseXMLTVProgramsByChannel:xml];
    NSMutableDictionary<NSString *, NSArray<TVLiveProgram *> *> *results = [NSMutableDictionary dictionary];
    for (NSString *name in channelNames) {
        NSArray<TVLiveProgram *> *programs = byChannel[name];
        if (!programs) programs = byChannel[[self normalizedEPGChannelName:name]];
        results[name] = programs ?: @[];
    }
    if (completion) completion(results);
}

// 逐频道拉取（非 XMLTV 源的回退路径），带并发限制，结果以频道名为键
- (void)fetchProgramsForChannelsIndividually:(NSArray<NSString *> *)channelNames
                                      epgURL:(NSString *)epgURL
                                  completion:(void (^)(NSDictionary<NSString *, NSArray<TVLiveProgram *> *> * _Nonnull results))completion {
    dispatch_queue_t bgQueue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_async(bgQueue, ^{
        dispatch_group_t group = dispatch_group_create();
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(4);
        NSMutableDictionary<NSString *, NSArray<TVLiveProgram *> *> *results = [NSMutableDictionary dictionary];
        for (NSString *name in channelNames) {
            dispatch_group_enter(group);
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            [self fetchProgramsForChannel:name epgURL:epgURL completion:^(NSArray<TVLiveProgram *> * _Nullable programs) {
                results[name] = programs ?: @[];
                dispatch_semaphore_signal(semaphore);
                dispatch_group_leave(group);
            }];
        }
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(results);
        });
    });
}

// 解析整份 XMLTV 节目单并按频道分发：返回以“频道显示名（含规范化别名）”为键的节目单字典
- (NSDictionary<NSString *, NSArray<TVLiveProgram *> *> *)parseXMLTVProgramsByChannel:(NSString *)xml {
    NSError *error = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&error];
    if (!document) return @{};

    // 频道 id → 显示名列表
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *idToNames = [NSMutableDictionary dictionary];
    NSArray<NSXMLElement *> *channelNodes = [document nodesForXPath:@"//channel" error:&error];
    for (NSXMLElement *channel in channelNodes) {
        NSString *cid = [channel attributeForName:@"id"].stringValue;
        if (cid.length == 0) continue;
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSXMLElement *dn in [channel elementsForName:@"display-name"]) {
            if (dn.stringValue.length > 0) [names addObject:dn.stringValue];
        }
        if (names.count > 0) idToNames[cid] = names;
    }

    // 频道 id → 节目单
    NSMutableDictionary<NSString *, NSMutableArray<TVLiveProgram *> *> *byId = [NSMutableDictionary dictionary];
    NSArray<NSXMLElement *> *programmeNodes = [document nodesForXPath:@"//programme" error:&error];
    for (NSXMLElement *programme in programmeNodes) {
        NSString *cid = [programme attributeForName:@"channel"].stringValue;
        if (cid.length == 0) continue;
        NSString *title = @"";
        for (NSXMLElement *tn in [programme elementsForName:@"title"]) {
            if (tn.stringValue.length > 0) {
                title = tn.stringValue;
                break;
            }
        }
        if (title.length == 0) continue;
        TVLiveProgram *program = [[TVLiveProgram alloc] init];
        program.title = title;
        program.startTime = [self hhmmFromISO8601:[programme attributeForName:@"start"].stringValue];
        program.endTime = [self hhmmFromISO8601:[programme attributeForName:@"stop"].stringValue];
        NSMutableArray<TVLiveProgram *> *list = byId[cid];
        if (!list) {
            list = [NSMutableArray array];
            byId[cid] = list;
        }
        [list addObject:program];
    }

    // 展平为 显示名（含规范化别名）→ 节目单，便于按频道名匹配
    NSMutableDictionary<NSString *, NSArray<TVLiveProgram *> *> *result = [NSMutableDictionary dictionary];
    for (NSString *cid in byId) {
        NSArray<TVLiveProgram *> *programs = byId[cid];
        NSArray<NSString *> *names = idToNames[cid];
        if (names.count == 0) {
            result[cid] = programs;
            continue;
        }
        for (NSString *name in names) {
            result[name] = programs;
            NSString *norm = [self normalizedEPGChannelName:name];
            if (![norm isEqualToString:name]) result[norm] = programs;
        }
    }
    return result;
}

// 规范化频道名以提高 EPG 匹配率：央视系 “CCTV-1 综合” → “CCTV1”，其余去除空格
- (NSString *)normalizedEPGChannelName:(NSString *)name {
    NSString *clean = [name stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (clean.length == 0) return name;

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"CCTV[-\\s]*(\\d+\\+?|\\d+K)" options:NSRegularExpressionCaseInsensitive error:&error];
    NSTextCheckingResult *match = [regex firstMatchInString:clean options:0 range:NSMakeRange(0, clean.length)];
    if (match && match.numberOfRanges > 1) {
        NSString *body = [clean substringWithRange:[match rangeAtIndex:1]];
        return [@"CCTV" stringByAppendingString:body];
    }
    return clean;
}

// 根据 EPG 基础地址与频道名构造查询 URL：优先支持 {name}/{channel}/{date} 占位符，否则追加 ch= 查询参数
- (NSURL *)epgQueryURLForBase:(NSString *)base channelName:(NSString *)name {
    if (base.length == 0) return nil;
    NSString *encoded = [name stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: name;

    // 当天日期，用于替换 {date} 占位符
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *today = [formatter stringFromDate:[NSDate date]];

    NSString *urlString = base;
    if ([urlString containsString:@"{name}"] || [urlString containsString:@"{channel}"]) {
        urlString = [urlString stringByReplacingOccurrencesOfString:@"{name}" withString:encoded];
        urlString = [urlString stringByReplacingOccurrencesOfString:@"{channel}" withString:encoded];
        urlString = [urlString stringByReplacingOccurrencesOfString:@"{date}" withString:today];
        return [NSURL URLWithString:urlString];
    }

    NSString *separator = [urlString containsString:@"?"] ? @"&" : @"?";
    urlString = [NSString stringWithFormat:@"%@%@ch=%@", urlString, separator, encoded];
    urlString = [urlString stringByReplacingOccurrencesOfString:@"{date}" withString:today];
    return [NSURL URLWithString:urlString];
}

// 解析 EPG 文本：支持 XMLTV（XML）与 DIYP / 112114 等 JSON 两种格式
- (NSArray<TVLiveProgram *> *)parseProgramsFromText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return @[];

    // XMLTV：以 XML 标签开头
    if ([trimmed hasPrefix:@"<"]) {
        return [self parseProgramsFromXMLTV:trimmed];
    }

    NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (json) {
        return [self parseProgramsFromJSON:json];
    }

    // 部分接口（如 112114）返回“频道名 + JSON”两段文本，取其中 JSON 片段
    NSRange braceRange = [trimmed rangeOfString:@"{"];
    if (braceRange.location != NSNotFound) {
        NSString *jsonSubstring = [trimmed substringFromIndex:braceRange.location];
        NSData *subData = [jsonSubstring dataUsingEncoding:NSUTF8StringEncoding];
        id subJSON = [NSJSONSerialization JSONObjectWithData:subData options:0 error:nil];
        if (subJSON) {
            return [self parseProgramsFromJSON:subJSON];
        }
    }
    return @[];
}

- (NSArray<TVLiveProgram *> *)parseProgramsFromJSON:(id)json {
    NSArray *items = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in @[@"epg_data", @"data", @"epg", @"programs", @"list", @"program"]) {
            id value = json[key];
            if ([value isKindOfClass:[NSArray class]]) {
                items = value;
                break;
            }
        }
    } else if ([json isKindOfClass:[NSArray class]]) {
        items = (NSArray *)json;
    }
    if (!items) return @[];

    NSMutableArray<TVLiveProgram *> *programs = [NSMutableArray array];
    for (id item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *d = (NSDictionary *)item;
        NSString *title = MMString(d[@"title"]);
        if (title.length == 0) continue;
        // 过滤“暂未提供节目预告”等占位内容，避免误判为有效节目单
        if ([title containsString:@"暂未提供"] || [title containsString:@"精彩节目"]) continue;
        NSString *start = MMString(d[@"start"]);
        if (start.length == 0) start = MMString(d[@"startTime"]);
        NSString *end = MMString(d[@"end"]);
        if (end.length == 0) end = MMString(d[@"endTime"]);

        TVLiveProgram *program = [[TVLiveProgram alloc] init];
        program.title = title;
        program.startTime = start ?: @"";
        program.endTime = end ?: @"";
        [programs addObject:program];
    }
    return programs;
}

- (NSArray<TVLiveProgram *> *)parseProgramsFromXMLTV:(NSString *)xml {
    NSError *error = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&error];
    if (!document) return @[];

    NSArray<NSXMLElement *> *programmeNodes = [document nodesForXPath:@"//programme" error:&error];
    if (!programmeNodes || programmeNodes.count == 0) return @[];

    NSMutableArray<TVLiveProgram *> *programs = [NSMutableArray array];
    for (NSXMLElement *programme in programmeNodes) {
        NSString *title = @"";
        for (NSXMLElement *titleNode in [programme elementsForName:@"title"]) {
            if (titleNode.stringValue.length > 0) {
                title = titleNode.stringValue;
                break;
            }
        }
        if (title.length == 0) continue;

        NSString *start = [programme attributeForName:@"start"].stringValue;
        NSString *stop = [programme attributeForName:@"stop"].stringValue;

        TVLiveProgram *program = [[TVLiveProgram alloc] init];
        program.title = title;
        program.startTime = [self hhmmFromISO8601:start];
        program.endTime = [self hhmmFromISO8601:stop];
        [programs addObject:program];
    }
    return programs;
}

// 将 XMLTV 的 yyyyMMddHHmmss 时间串转换为 HH:mm
- (NSString *)hhmmFromISO8601:(NSString *)value {
    if (value.length >= 12) {
        NSString *hh = [value substringWithRange:NSMakeRange(8, 2)];
        NSString *mm = [value substringWithRange:NSMakeRange(10, 2)];
        return [NSString stringWithFormat:@"%@:%@", hh, mm];
    }
    return value ?: @"";
}

@end
