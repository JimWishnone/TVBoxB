#import "ConfigManager.h"

static NSString * const kUserConfigURLsKey = @"TVBoxUserConfigURLs";
static NSString * const kUserLiveConfigURLsKey = @"TVBoxUserLiveConfigURLs";
static NSString * const kUserLiveEPGURLKey = @"TVBoxUserLiveEPGURL";

@interface ConfigManager ()
@property (nonatomic, strong) NSArray<TVSite *> *vodSites;
@property (nonatomic, strong) NSArray<TVLiveSource *> *liveSources;
@property (nonatomic, strong) NSArray<TVParse *> *parses;
@end

static NSString *MMString(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return @"";
}

static NSInteger MMInteger(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [value integerValue];
    if ([value isKindOfClass:[NSString class]]) return [value integerValue];
    return 0;
}

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
        [self loadLiveConfigFromURLs:liveURLs index:0 completion:^(NSError * _Nullable liveError) {
            // 直播源加载失败不影响点播（此时无点播源），仍以 nil 结束加载流程
            if (completion) completion(nil);
        }];
        return;
    }

    // 先加载主数据源（点播站点 + 作为回退的直播源 + 解析接口）
    [self loadConfigFromURLs:vodURLs index:0 completion:^(NSError * _Nullable vodError) {
        if (liveURLs.count == 0) {
            // 未设置专属直播数据源，沿用主数据源中的直播源
            if (completion) completion(vodError);
            return;
        }
        // 设置了专属直播数据源时，用它覆盖主数据源中的直播源
        [self loadLiveConfigFromURLs:liveURLs index:0 completion:^(NSError * _Nullable liveError) {
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
    [self collectConfigFromURL:url depth:0 collector:collector completion:^(NSError * _Nullable error) {
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
            NSArray<TVLiveChannel *> *channels = [self parseLiveChannelsFromText:trimmed];
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
- (void)loadLiveConfigFromURLs:(NSArray<NSString *> *)urls index:(NSInteger)index completion:(void (^)(NSError * _Nullable))completion {
    if (index >= (NSInteger)urls.count) {
        if (completion) {
            completion([NSError errorWithDomain:@"TVBox"
                                           code:-6
                                       userInfo:@{NSLocalizedDescriptionKey: @"直播数据源加载失败，已尝试所有地址"}]);
        }
        return;
    }
    NSString *urlString = urls[index];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self loadLiveConfigFromURLs:urls index:index + 1 completion:completion];
        return;
    }

    [self fetchStringFromURL:url completion:^(NSString * _Nullable text, NSError * _Nullable error) {
        if (error || text.length == 0) {
            [self loadLiveConfigFromURLs:urls index:index + 1 completion:completion];
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
                    [self loadLiveConfigFromURLs:flat index:0 completion:completion];
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

- (void)loadConfigFromURLs:(NSArray<NSString *> *)urls index:(NSInteger)index completion:(void (^)(NSError * _Nullable))completion {
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

    [self collectConfigFromURL:url depth:0 collector:collector completion:^(NSError * _Nullable error) {
        if (error) {
            [self loadConfigFromURLs:urls index:index + 1 completion:completion];
            return;
        }
        [self parseConfig:collector];
        if (completion) completion(nil);
    }];
}

- (void)collectConfigFromURL:(NSURL *)url depth:(NSInteger)depth collector:(NSMutableDictionary *)collector completion:(void (^)(NSError * _Nullable))completion {
    if (depth > 4) {
        if (completion) {
            completion([NSError errorWithDomain:@"TVBox"
                                           code:-3
                                       userInfo:@{NSLocalizedDescriptionKey: @"配置嵌套层级过深"}]);
        }
        return;
    }

    [self requestJSONFromURL:url completion:^(id _Nullable json, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        NSDictionary *dict = (NSDictionary *)json;
        NSArray *subURLs = [self arrayValue:dict[@"urls"]];
        if (subURLs.count > 0) {
            // 多仓格式：逐个加载子配置并合并
            [self collectSubConfigURLs:subURLs depth:depth + 1 collector:collector completion:completion];
            return;
        }

        [collector[@"sites"] addObjectsFromArray:[self arrayValue:dict[@"sites"]]];
        [collector[@"lives"] addObjectsFromArray:[self arrayValue:dict[@"lives"]]];
        [collector[@"parses"] addObjectsFromArray:[self arrayValue:dict[@"parses"]]];
        if (completion) completion(nil);
    }];
}

- (void)collectSubConfigURLs:(NSArray *)urls depth:(NSInteger)depth collector:(NSMutableDictionary *)collector completion:(void (^)(NSError * _Nullable))completion {
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

        [self collectConfigFromURL:subURL depth:depth collector:collector completion:^(NSError * _Nullable err) {
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
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 12.0;
    [request setValue:@"okhttp/3.15" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }

        // 检查 HTTP 状态码：站点在临时失效/被拦截时可能返回 200 以外的状态码
        NSInteger statusCode = 200;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            statusCode = ((NSHTTPURLResponse *)response).statusCode;
        }
        if (statusCode < 200 || statusCode >= 300) {
            NSError *statusError = [NSError errorWithDomain:@"TVBox"
                                                       code:statusCode
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"服务器返回状态码 %ld", (long)statusCode]}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, statusError);
            });
            return;
        }

        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError == nil && [json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(json, nil);
            });
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
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, resultError);
        });
    }];
    [task resume];
}

- (void)fetchStringFromURL:(NSURL *)url completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 12.0;
    [request setValue:@"okhttp/3.15" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) {
            text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(text, nil);
        });
    }];
    [task resume];
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

- (NSArray<TVLiveChannel *> *)parseLiveChannelsFromText:(NSString *)text {
    if (text.length == 0) return @[];
    NSMutableArray<TVLiveChannel *> *channels = [NSMutableArray array];

    BOOL isM3U = ([text containsString:@"#EXTM3U"] || [text containsString:@"#EXTINF"]);
    if (isM3U) {
        [self parseM3U:text intoChannels:channels];
    } else {
        [self parseDIYPText:text intoChannels:channels];
    }
    return channels;
}

- (void)parseM3U:(NSString *)text intoChannels:(NSMutableArray<TVLiveChannel *> *)channels {
    NSString *currentName = nil;
    NSString *currentGroup = @"";
    NSString *currentLogo = @"";

    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *raw in lines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;

        if ([line hasPrefix:@"#EXTINF"]) {
            currentGroup = [self attributeValue:@"group-title" inLine:line];
            currentLogo = [self attributeValue:@"tvg-logo" inLine:line];
            NSRange comma = [line rangeOfString:@"," options:NSBackwardsSearch];
            if (comma.location != NSNotFound) {
                currentName = [[line substringFromIndex:NSMaxRange(comma)]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        } else if ([line hasPrefix:@"#"]) {
            continue;
        } else if (currentName.length > 0 && ([line hasPrefix:@"http://"] || [line hasPrefix:@"https://"])) {
            TVLiveChannel *channel = [[TVLiveChannel alloc] init];
            channel.name = currentName;
            channel.url = line;
            channel.group = currentGroup;
            channel.logo = currentLogo;
            [channels addObject:channel];
            currentName = nil;
        }
    }
}

- (void)parseDIYPText:(NSString *)text intoChannels:(NSMutableArray<TVLiveChannel *> *)channels {
    NSString *currentGroup = @"";

    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *raw in lines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;

        if ([line hasSuffix:@",#genre#"]) {
            currentGroup = [line stringByReplacingOccurrencesOfString:@",#genre#" withString:@""];
            continue;
        }

        NSRange comma = [line rangeOfString:@","];
        if (comma.location == NSNotFound) continue;

        NSString *name = [[line substringToIndex:comma.location]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *url = [[line substringFromIndex:NSMaxRange(comma)]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (name.length > 0 && ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"])) {
            TVLiveChannel *channel = [[TVLiveChannel alloc] init];
            channel.name = name;
            channel.url = url;
            channel.group = currentGroup;
            channel.logo = @"";
            [channels addObject:channel];
        }
    }
}

- (NSString *)attributeValue:(NSString *)attribute inLine:(NSString *)line {
    NSString *pattern = [NSString stringWithFormat:@"%@=\"([^\"]*)\"", attribute];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (match && match.numberOfRanges > 1) {
        return [line substringWithRange:[match rangeAtIndex:1]];
    }
    return @"";
}

- (NSArray *)arrayValue:(id)value {
    if ([value isKindOfClass:[NSArray class]]) return value;
    return @[];
}

#pragma mark - 节目单（EPG）

- (void)fetchProgramsForChannel:(NSString *)channelName
                        epgURL:(NSString *)epgURL
                    completion:(void (^)(NSArray<TVLiveProgram *> * _Nullable programs))completion {
    if (channelName.length == 0 || epgURL.length == 0) {
        if (completion) completion(@[]);
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
            NSArray<TVLiveProgram *> *retryPrograms = (retryError || retryText.length == 0) ? @[] : [self parseProgramsFromText:retryText];
            if (completion) completion(retryPrograms ?: @[]);
        }];
    }];
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