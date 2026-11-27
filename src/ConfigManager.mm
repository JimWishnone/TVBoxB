#import "ConfigManager.h"
#import "TVLiveSourceParser.h"
#import <CoreFoundation/CFStringEncodingExt.h>

NSString * const TVBoxHTTPUserAgent = @"Dalvik/2.1.0 (Linux; U; Android 11; TV Box Build/RP1A.200720.009)";

static NSString * const kUserConfigURLsKey = @"TVBoxUserConfigURLs";
static NSString * const kUserLiveConfigURLsKey = @"TVBoxUserLiveConfigURLs";
static NSString * const kUserLiveEPGURLKey = @"TVBoxUserLiveEPGURL";

// 网络请求最大重试次数：首包失败后最多再尝试 2 次（共 3 次请求）
static const NSInteger TVBoxMaxNetworkRetries = 2;

// 归一化地址作为环检测的访问键：去除首尾空白并统一小写，识别同一地址的不同写法。
static NSString *TVBoxVisitedKey(NSString *urlString) {
    NSString *trimmed = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmed lowercaseString];
}

@interface ConfigManager ()
@property (nonatomic, strong) NSArray<TVSite *> *vodSites;
@property (nonatomic, strong) NSArray<TVLiveSource *> *liveSources;
@property (nonatomic, strong) NSArray<TVParse *> *parses;
@end

@implementation ConfigManager

+ (instancetype)sharedManager {
    static ConfigManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[ConfigManager alloc] init];
    });
    return manager;
}

- (void)loadConfigWithCompletion:(void (^)(NSError * _Nullable))completion {
    NSArray<NSString *> *vodURLs = [self configURLs];
    NSArray<NSString *> *liveURLs = [self liveConfigURLs];

    // 未设置点播数据源时，仅清空点播站点，仍可单独使用专属直播数据源
    if (vodURLs.count == 0) {
        self.vodSites = @[];
        self.parses = @[];
        if (liveURLs.count == 0) {
            self.liveSources = @[];
            if (completion) completion(nil);
            return;
        }
        [self loadLiveConfigFromURLs:liveURLs index:0 visited:[NSMutableSet set] completion:^(NSError * _Nullable liveError) {
            // 直播源加载失败不影响点播（此时无点播源），仍以 nil 结束加载流程
            if (completion) completion(nil);
        }];
        return;
    }

    // 先加载主数据源（点播站点 + 作为回退的直播源 + 解析接口）
    [self loadConfigFromURLs:vodURLs index:0 visited:[NSMutableSet set] completion:^(NSError * _Nullable vodError) {
        if (liveURLs.count == 0) {
            // 未设置专属直播数据源，沿用主数据源中的直播源
            if (completion) completion(vodError);
            return;
        }
        // 设置了专属直播数据源时，用它覆盖主数据源中的直播源
        [self loadLiveConfigFromURLs:liveURLs index:0 visited:[NSMutableSet set] completion:^(NSError * _Nullable liveError) {
            // 直播源加载失败不影响点播，此时仍保留主数据源中的直播源作为回退
            if (completion) completion(nil);
        }];
    }];
}

- (NSArray<NSString *> *)configURLs {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kUserConfigURLsKey];
    NSMutableArray<NSString *> *valid = [NSMutableArray array];
    for (id item in saved) {
        NSString *url = MMString(item);
        NSString *trimmed = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [valid addObject:trimmed];
    }
    return valid;
}

- (void)saveConfigURLs:(NSArray<NSString *> *)urls {
    NSMutableArray<NSString *> *valid = [NSMutableArray array];
    for (NSString *url in urls) {
        NSString *trimmed = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [valid addObject:trimmed];
    }
    if (valid.count > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:valid forKey:kUserConfigURLsKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserConfigURLsKey];
    }
}

- (void)resetConfigURLs {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserConfigURLsKey];
}

- (NSArray<NSString *> *)liveConfigURLs {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kUserLiveConfigURLsKey];
    NSMutableArray<NSString *> *valid = [NSMutableArray array];
    for (id item in saved) {
        NSString *url = MMString(item);
        NSString *trimmed = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [valid addObject:trimmed];
    }
    return valid;
}

- (void)saveLiveConfigURLs:(NSArray<NSString *> *)urls {
    NSMutableArray<NSString *> *valid = [NSMutableArray array];
    for (NSString *url in urls) {
        NSString *trimmed = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [valid addObject:trimmed];
    }
    if (valid.count > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:valid forKey:kUserLiveConfigURLsKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserLiveConfigURLsKey];
    }
}

- (void)resetLiveConfigURLs {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserLiveConfigURLsKey];
}

- (NSString *)liveEPGURL {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kUserLiveEPGURLKey];
    return (saved.length > 0) ? saved : nil;
}

- (void)saveLiveEPGURL:(NSString *)url {
    NSString *trimmed = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:kUserLiveEPGURLKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserLiveEPGURLKey];
    }
}

// 验证点播配置 URL：可访问、可解析、且是 TVBox 支持的配置格式。
// 成功时返回该配置中包含的直播源数组（可能为空数组）；失败时返回 error。
- (void)validateVODConfigURL:(NSString *)urlString
                     progress:(TVValidateProgressBlock)progressBlock
                   completion:(void (^)(NSArray<TVLiveSource *> * _Nullable liveSources, NSError * _Nullable error))completion {
    if (progressBlock) progressBlock(@"正在校验点播数据源地址格式…");

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"TVBox"
                                             code:-10
                                         userInfo:@{NSLocalizedDescriptionKey: @"地址格式不正确"}];
        if (completion) completion(nil, error);
        return;
    }

    NSMutableDictionary *collector = [NSMutableDictionary dictionary];
    collector[@"sites"] = [NSMutableArray array];
    collector[@"lives"] = [NSMutableArray array];
    collector[@"parses"] = [NSMutableArray array];

    if (progressBlock) progressBlock(@"正在访问点播数据源…");
    [self collectConfigFromURL:url depth:0 visited:[NSMutableSet set] collector:collector completion:^(NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        if (progressBlock) progressBlock(@"正在解析点播配置内容…");
        NSArray *sites = [self arrayValue:collector[@"sites"]];
        NSArray *lives = [self arrayValue:collector[@"lives"]];

        if (progressBlock) progressBlock(@"正在校验 TVBox 数据格式…");
        // TVBox 支持的格式：至少包含一个苹果 CMS 点播站点或一个直播源
        BOOL hasVodSite = NO;
        for (id item in sites) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *s = (NSDictionary *)item;
            if (MMInteger(s[@"type"]) == 1 && MMString(s[@"api"]).length > 0) {
                hasVodSite = YES;
                break;
            }
        }
        BOOL hasLive = (lives.count > 0);
        if (!hasVodSite && !hasLive) {
            NSError *error = [NSError errorWithDomain:@"TVBox"
                                                 code:-11
                                             userInfo:@{NSLocalizedDescriptionKey: @"该地址不是有效的 TVBox 配置（未找到点播或直播数据源）"}];
            if (completion) completion(nil, error);
            return;
        }

        NSArray<TVLiveSource *> *liveSources = [self parseLiveSourcesFromArray:lives];
        if (completion) completion(liveSources, nil);
    }];
}

// 验证直播视频源 URL：可访问、且能解析出直播数据（JSON 配置的 lives/urls，或 m3u / DIYP 文本）
- (void)validateLiveConfigURL:(NSString *)urlString
                      progress:(TVValidateProgressBlock)progressBlock
                    completion:(void (^)(NSError * _Nullable error))completion {
    if (progressBlock) progressBlock(@"正在校验直播数据源地址格式…");

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"TVBox"
                                             code:-12
                                         userInfo:@{NSLocalizedDescriptionKey: @"地址格式不正确"}];
        if (completion) completion(error);
        return;
    }

    if (progressBlock) progressBlock(@"正在访问直播数据源…");
    [self fetchStringFromURL:url completion:^(NSString * _Nullable text, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(error);
            return;
        }

        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            NSError *emptyError = [NSError errorWithDomain:@"TVBox"
                                                      code:-13
                                                  userInfo:@{NSLocalizedDescriptionKey: @"直播数据源返回内容为空"}];
            if (completion) completion(emptyError);
            return;
        }

        if (progressBlock) progressBlock(@"正在解析直播数据源…");

        // 尝试按 JSON 配置解析（含 lives 数组或多仓 urls）
        NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *dict = nil;
        if (data) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]]) dict = (NSDictionary *)json;
        }

        BOOL valid = NO;
        if (dict) {
            NSArray *lives = [self arrayValue:dict[@"lives"]];
            NSArray *subURLs = [self arrayValue:dict[@"urls"]];
            // 含 lives 数组或 urls 多仓配置即视为有效直播数据
            if (lives.count > 0 || subURLs.count > 0) {
                valid = YES;
            }
        }

        if (!valid) {
            // 非 JSON 配置：按 m3u / DIYP 文本直播源解析
            NSArray<TVLiveChannel *> *channels = [TVLiveSourceParser parseLiveChannelsFromText:trimmed];
            valid = (channels.count > 0);
        }

        if (!valid) {
            NSError *parseError = [NSError errorWithDomain:@"TVBox"
                                                      code:-14
                                                  userInfo:@{NSLocalizedDescriptionKey: @"该地址不是有效的直播数据源（未解析出任何直播数据）"}];
            if (completion) completion(parseError);
            return;
        }

        if (completion) completion(nil);
    }];
}

// 加载专属直播数据源：既可以是 JSON 配置（含 lives / urls），也可以是 m3u / DIYP 文本列表
- (void)loadLiveConfigFromURLs:(NSArray<NSString *> *)urls index:(NSInteger)index visited:(NSMutableSet<NSString *> *)visited completion:(void (^)(NSError * _Nullable))completion {
    if (index >= (NSInteger)urls.count) {
        if (completion) {
            completion([NSError errorWithDomain:@"TVBox"
                                           code:-6
                                       userInfo:@{NSLocalizedDescriptionKey: @"直播数据源加载失败，已尝试所有地址"}]);
        }
        return;
    }
    NSString *urlString = urls[index];
    NSString *key = TVBoxVisitedKey(urlString);
    if ([visited containsObject:key]) {
        // 该地址已访问过，跳过以避免多仓循环引用导致无限递归
        [self loadLiveConfigFromURLs:urls index:index + 1 visited:visited completion:completion];
        return;
    }
    [visited addObject:key];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self loadLiveConfigFromURLs:urls index:index + 1 visited:visited completion:completion];
        return;
    }

    [self fetchStringFromURL:url completion:^(NSString * _Nullable text, NSError * _Nullable error) {
        if (error || text.length == 0) {
            [self loadLiveConfigFromURLs:urls index:index + 1 visited:visited completion:completion];
            return;
        }

        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *dict = nil;
        if (data) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]]) dict = (NSDictionary *)json;
        }

        NSMutableArray<TVLiveSource *> *sources = [NSMutableArray array];
        if (dict) {
            // JSON 多仓格式：递归合并子配置中的直播源
            NSArray *subURLs = [self arrayValue:dict[@"urls"]];
            if (subURLs.count > 0) {
                NSMutableArray<NSString *> *flat = [NSMutableArray array];
                for (id item in subURLs) {
                    NSString *u = nil;
                    if ([item isKindOfClass:[NSDictionary class]]) {
                        u = MMString(((NSDictionary *)item)[@"url"]);
                    } else if ([item isKindOfClass:[NSString class]]) {
                        u = (NSString *)item;
                    }
                    NSString *trimmedU = [u stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (trimmedU.length > 0) [flat addObject:trimmedU];
                }
                if (flat.count > 0) {
                    [self loadLiveConfigFromURLs:flat index:0 visited:visited completion:completion];
                    return;
                }
            }
            for (id item in [self arrayValue:dict[@"lives"]]) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    TVLiveSource *source = [self liveSourceFromDictionary:(NSDictionary *)item];
                    if (source.url.length > 0) [sources addObject:source];
                }
            }
        }

        if (sources.count == 0) {
            // 非 JSON 内容：按 m3u / DIYP 文本直播源处理
            TVLiveSource *source = [[TVLiveSource alloc] init];
            source.name = ([url lastPathComponent].length > 0) ? [url lastPathComponent] : @"自定义直播源";
            source.type = 0;
            source.url = urlString;
            source.epg = [self liveEPGURL] ?: @"";
            [sources addObject:source];
        } else {
            // JSON 配置中的直播源：未自带 epg 时回退到用户保存的节目单地址
            NSString *fallbackEPG = [self liveEPGURL];
            if (fallbackEPG.length > 0) {
                for (TVLiveSource *source in sources) {
                    if (source.epg.length == 0) source.epg = fallbackEPG;
                }
            }
        }

        self.liveSources = sources;
        if (completion) completion(nil);
    }];
}

- (void)loadConfigFromURLs:(NSArray<NSString *> *)urls index:(NSInteger)index visited:(NSMutableSet<NSString *> *)visited completion:(void (^)(NSError * _Nullable))completion {
    if (index >= (NSInteger)urls.count) {
        if (completion) {
            completion([NSError errorWithDomain:@"TVBox"
                                           code:-2
                                       userInfo:@{NSLocalizedDescriptionKey: @"配置加载失败，已尝试所有镜像源"}]);
        }
        return;
    }

    NSURL *url = [NSURL URLWithString:urls[index]];

    // 收集器：递归汇总多仓（urls）与单仓配置中的 sites / lives / parses
    NSMutableDictionary *collector = [NSMutableDictionary dictionary];
    collector[@"sites"] = [NSMutableArray array];
    collector[@"lives"] = [NSMutableArray array];
    collector[@"parses"] = [NSMutableArray array];

    [self collectConfigFromURL:url depth:0 visited:visited collector:collector completion:^(NSError * _Nullable error) {
        if (error) {
            [self loadConfigFromURLs:urls index:index + 1 visited:visited completion:completion];
            return;
        }
        [self parseConfig:collector];
        if (completion) completion(nil);
    }];
}

- (void)collectConfigFromURL:(NSURL *)url depth:(NSInteger)depth visited:(NSMutableSet<NSString *> *)visited collector:(NSMutableDictionary *)collector completion:(void (^)(NSError * _Nullable))completion {
    if (depth > 4) {
        if (completion) {
            completion([NSError errorWithDomain:@"TVBox"
                                           code:-3
                                       userInfo:@{NSLocalizedDescriptionKey: @"配置嵌套层级过深"}]);
        }
        return;
    }

    // 多仓循环引用检测：同一地址只访问一次，已访问则跳过该分支，避免无限递归
    NSString *key = TVBoxVisitedKey(url.absoluteString);
    if ([visited containsObject:key]) {
        if (completion) completion(nil);
        return;
    }
    [visited addObject:key];

    [self requestJSONFromURL:url completion:^(id _Nullable json, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        NSDictionary *dict = (NSDictionary *)json;
        NSArray *subURLs = [self arrayValue:dict[@"urls"]];
        if (subURLs.count > 0) {
            // 多仓格式：逐个加载子配置并合并
            [self collectSubConfigURLs:subURLs depth:depth + 1 visited:visited collector:collector completion:completion];
            return;
        }

        [collector[@"sites"] addObjectsFromArray:[self arrayValue:dict[@"sites"]]];
        [collector[@"lives"] addObjectsFromArray:[self arrayValue:dict[@"lives"]]];
        [collector[@"parses"] addObjectsFromArray:[self arrayValue:dict[@"parses"]]];
        if (completion) completion(nil);
    }];
}

- (void)collectSubConfigURLs:(NSArray *)urls depth:(NSInteger)depth visited:(NSMutableSet<NSString *> *)visited collector:(NSMutableDictionary *)collector completion:(void (^)(NSError * _Nullable))completion {
    __block NSInteger remaining = (NSInteger)urls.count;
    __block NSError *firstError = nil;

    if (remaining == 0) {
        if (completion) completion(nil);
        return;
    }

    void (^finishIfNeeded)(void) = ^{
        if (remaining <= 0) {
            BOOL hasAny = ([(NSArray *)collector[@"sites"] count] > 0 ||
                           [(NSArray *)collector[@"lives"] count] > 0);
            NSError *finalError = nil;
            if (!hasAny) {
                finalError = firstError ?: [NSError errorWithDomain:@"TVBox"
                                                               code:-4
                                                           userInfo:@{NSLocalizedDescriptionKey: @"多仓配置加载失败"}];
            }
            if (completion) completion(finalError);
        }
    };

    for (id item in urls) {
        NSString *urlString = nil;
        if ([item isKindOfClass:[NSDictionary class]]) {
            urlString = MMString(((NSDictionary *)item)[@"url"]);
        } else if ([item isKindOfClass:[NSString class]]) {
            urlString = (NSString *)item;
        }

        NSURL *subURL = [NSURL URLWithString:urlString];
        if (!subURL) {
            remaining--;
            finishIfNeeded();
            continue;
        }

        [self collectConfigFromURL:subURL depth:depth visited:visited collector:collector completion:^(NSError * _Nullable err) {
            if (err && !firstError) firstError = err;
            remaining--;
            finishIfNeeded();
        }];
    }
}

- (void)parseConfig:(NSDictionary *)dict {
    NSMutableArray<TVSite *> *vodSites = [NSMutableArray array];
    for (id item in [self arrayValue:dict[@"sites"]]) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *s = (NSDictionary *)item;

        TVSite *site = [[TVSite alloc] init];
        site.key = MMString(s[@"key"]);
        site.name = MMString(s[@"name"]);
        site.type = MMInteger(s[@"type"]);
        site.api = MMString(s[@"api"]);
        site.searchable = [s[@"searchable"] boolValue];
        site.filterable = [s[@"filterable"] boolValue];

        if ([s[@"categories"] isKindOfClass:[NSArray class]]) {
            site.categories = (NSArray<NSString *> *)s[@"categories"];
        }

        // 仅保留苹果 CMS 接口站点，原生应用可直接通过 HTTP 接口访问
        if (site.type == 1 && site.api.length > 0) {
            [vodSites addObject:site];
        }
    }
    self.vodSites = vodSites;
    self.liveSources = [self parseLiveSourcesFromArray:[self arrayValue:dict[@"lives"]]];

    NSMutableArray<TVParse *> *parses = [NSMutableArray array];
    for (id item in [self arrayValue:dict[@"parses"]]) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *p = (NSDictionary *)item;

        TVParse *parse = [[TVParse alloc] init];
        parse.name = MMString(p[@"name"]);
        parse.type = MMInteger(p[@"type"]);
        parse.url = MMString(p[@"url"]);
        [parses addObject:parse];
    }
    self.parses = parses;
}

// 从 lives 数组解析直播源（主数据源与专属直播数据源共用）
- (NSArray<TVLiveSource *> *)parseLiveSourcesFromArray:(NSArray *)array {
    NSMutableArray<TVLiveSource *> *lives = [NSMutableArray array];
    for (id item in array) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        TVLiveSource *source = [self liveSourceFromDictionary:(NSDictionary *)item];
        if (source.url.length > 0) {
            [lives addObject:source];
        }
    }
    return lives;
}

- (TVLiveSource *)liveSourceFromDictionary:(NSDictionary *)l {
    TVLiveSource *source = [[TVLiveSource alloc] init];
    source.name = MMString(l[@"name"]);
    source.type = MMInteger(l[@"type"]);
    source.url = MMString(l[@"url"]);
    source.playerType = MMInteger(l[@"playerType"]);
    source.ua = MMString(l[@"ua"]);
    source.epg = MMString(l[@"epg"]);
    source.logo = MMString(l[@"logo"]);
    return source;
}

- (void)requestJSONFromURL:(NSURL *)url completion:(void (^)(id _Nullable, NSError * _Nullable))completion {
    [self requestJSONFromURL:url retryRemaining:2 completion:completion];
}

- (void)requestJSONFromURL:(NSURL *)url retryRemaining:(NSInteger)retryRemaining completion:(void (^)(id _Nullable, NSError * _Nullable))completion {
    [self requestDataFromURL:url retryRemaining:TVBoxMaxNetworkRetries completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError == nil && [json isKindOfClass:[NSDictionary class]]) {
            if (completion) completion(json, nil);
            return;
        }

        // 解析失败时先自动重试：站点防采集拦截（返回网页）通常是偶发的，
        // 稍等片刻再次请求有很大概率成功，可显著降低“加载失败”的出现频率。
        if (jsonError != nil && retryRemaining > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self requestJSONFromURL:url retryRemaining:retryRemaining - 1 completion:completion];
            });
            return;
        }

        NSString *message = @"返回数据格式错误";
        if (jsonError != nil && data.length > 0) {
            // 解析失败时判断是否返回了网页（站点失效/防采集页面），给出更明确的提示
            NSData *headData = [data subdataWithRange:NSMakeRange(0, MIN(data.length, 512))];
            NSString *head = [[NSString alloc] initWithData:headData encoding:NSUTF8StringEncoding] ?: @"";
            NSString *lower = [head lowercaseString];
            if ([lower containsString:@"<html"] || [lower containsString:@"<!doctype"] || [lower containsString:@"<script"]) {
                message = @"站点返回了网页而非数据（可能已失效或被拦截）";
            }
        }
        NSError *resultError = [NSError errorWithDomain:@"TVBox"
                                                   code:-1
                                               userInfo:@{NSLocalizedDescriptionKey: message}];
        if (completion) completion(nil, resultError);
    }];
}

// 统一网络会话：配置首包/整体超时、单域名并发上限、响应缓存与弱网等待。
// 弱网下自动续传并优先命中本地缓存，避免请求直接失败或长时间无响应。
- (NSURLSession *)tvSession {
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 8.0;
        cfg.timeoutIntervalForResource = 12.0;
        cfg.HTTPMaximumConnectionsPerHost = 6;
        cfg.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
        cfg.URLCache = [[NSURLCache alloc] initWithMemoryCapacity:8 * 1024 * 1024
                                                     diskCapacity:64 * 1024 * 1024
                                                         diskPath:@"tvbox-urlcache"];
        cfg.waitsForConnectivity = NO;
        session = [NSURLSession sessionWithConfiguration:cfg];
    });
    return session;
}

// 底层统一请求：设置超时与 User-Agent，校验 HTTP 状态码，并在网络错误 / 状态码异常时自动重试。
// 点播接口、直播源、EPG 均复用此实现；回调始终在主线程执行。
- (void)requestDataFromURL:(NSURL *)url retryRemaining:(NSInteger)retryRemaining completion:(void (^)(NSData * _Nullable, NSError * _Nullable))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 8.0;
    [request setValue:TVBoxHTTPUserAgent forHTTPHeaderField:@"User-Agent"];

    [[[self tvSession] dataTaskWithRequest:request
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (error) {
                [self retryDataRequestWithError:error url:url retryRemaining:retryRemaining completion:completion];
                return;
            }

            NSInteger statusCode = 200;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                statusCode = ((NSHTTPURLResponse *)response).statusCode;
            }
            if (statusCode < 200 || statusCode >= 300) {
                NSError *statusError = [NSError errorWithDomain:@"TVBox"
                                                           code:statusCode
                                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"服务器返回状态码 %ld", (long)statusCode]}];
                [self retryDataRequestWithError:statusError url:url retryRemaining:retryRemaining completion:completion];
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(data, nil);
            });
        }] resume];
}

// 网络错误 / 状态码异常时：4xx 客户端错误直接失败；其余可恢复错误按指数退避 + 抖动延时重试。
- (void)retryDataRequestWithError:(NSError *)error url:(NSURL *)url retryRemaining:(NSInteger)retryRemaining completion:(void (^)(NSData * _Nullable, NSError * _Nullable))completion {
    // 4xx 为客户端错误（地址无效、无权限等），重试无法修复，快速失败避免无谓等待
    BOOL isClientError = (error.code >= 400 && error.code < 500);
    if (isClientError || retryRemaining <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, error);
        });
        return;
    }

    NSInteger retryIndex = TVBoxMaxNetworkRetries - retryRemaining;
    NSTimeInterval delay = [self backoffDelayForRetryIndex:retryIndex];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self requestDataFromURL:url retryRemaining:retryRemaining - 1 completion:completion];
    });
}

// 指数退避 + 抖动：基础延时 0.5s，随重试次数翻倍，并叠加 ±20% 随机抖动避免集中重试。
- (NSTimeInterval)backoffDelayForRetryIndex:(NSInteger)retryIndex {
    NSTimeInterval base = 0.5;
    NSTimeInterval exponential = base;
    for (NSInteger i = 0; i < retryIndex; i++) {
        exponential *= 2.0;
    }
    double jitterRatio = ((double)arc4random_uniform(100) / 100.0) * 0.4 - 0.2;
    return MAX(0.1, exponential * (1.0 + jitterRatio));
}

- (void)fetchStringFromURL:(NSURL *)url completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    [self requestDataFromURL:url retryRemaining:TVBoxMaxNetworkRetries completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        if (completion) completion([self stringFromResponseData:data], nil);
    }];
}

// 响应数据转字符串：依次尝试 UTF-8、GB18030（中文直播源常见）、Latin-1，兼容不同编码。
- (NSString *)stringFromResponseData:(NSData *)data {
    if (data.length == 0) return @"";
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text) return text;
    NSStringEncoding gb18030 = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    text = [[NSString alloc] initWithData:data encoding:gb18030];
    if (text) return text;
    text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    return text ?: @"";
}

- (NSURL *)vodURLForSite:(TVSite *)site params:(NSDictionary<NSString *, NSString *> *)params {
    NSURLComponents *components = [NSURLComponents componentsWithString:site.api];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];

    // 移除与本次请求参数冲突的已有 query 项，避免出现重复参数
    for (NSURLQueryItem *item in components.queryItems) {
        if (params[item.name] == nil) {
            [items addObject:item];
        }
    }
    for (NSString *key in params) {
        [items addObject:[NSURLQueryItem queryItemWithName:key value:params[key]]];
    }
    components.queryItems = items;
    return components.URL;
}

- (NSArray *)arrayValue:(id)value {
    if ([value isKindOfClass:[NSArray class]]) return value;
    return @[];
}

@end