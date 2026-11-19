#import "Models.h"

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

static BOOL MMBool(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
    if ([value isKindOfClass:[NSString class]]) return [value boolValue];
    return NO;
}

@implementation TVCategory

+ (instancetype)categoryFromDictionary:(NSDictionary *)dict {
    TVCategory *category = [[TVCategory alloc] init];
    category.typeId = MMInteger(dict[@"type_id"]);
    category.typePid = MMInteger(dict[@"type_pid"]);
    category.name = MMString(dict[@"type_name"]);
    return category;
}

@end

@implementation TVEpisode
@end

@implementation TVPlaySource
@end

@implementation TVVideo

+ (instancetype)videoFromDictionary:(NSDictionary *)dict {
    TVVideo *video = [[TVVideo alloc] init];
    video.vodId = MMInteger(dict[@"vod_id"]);
    video.name = MMString(dict[@"vod_name"]);
    video.typeId = MMInteger(dict[@"type_id"]);
    video.typeName = MMString(dict[@"type_name"]);
    video.remarks = MMString(dict[@"vod_remarks"]);
    video.vodPic = MMString(dict[@"vod_pic"]);
    video.vodEn = MMString(dict[@"vod_en"]);
    video.vodTime = MMString(dict[@"vod_time"]);
    video.vodActor = MMString(dict[@"vod_actor"]);
    video.vodDirector = MMString(dict[@"vod_director"]);
    video.vodContent = MMString(dict[@"vod_content"]);
    video.vodPlayFrom = MMString(dict[@"vod_play_from"]);
    video.vodPlayUrl = MMString(dict[@"vod_play_url"]);
    return video;
}

- (NSArray<TVPlaySource *> *)playSources {
    NSString *playUrl = self.vodPlayUrl ?: @"";
    if (playUrl.length == 0) return @[];

    // 多条线路使用 "$$$" 分隔，线路名称使用 "," 分隔；
    // 个别站点（如非凡资源）的 vod_play_from 也使用 "$$$" 分隔，做兼容处理
    NSArray<NSString *> *groups = [playUrl componentsSeparatedByString:@"$$$"];
    NSArray<NSString *> *names = @[];
    if (self.vodPlayFrom.length > 0) {
        if ([self.vodPlayFrom containsString:@"$$$"]) {
            names = [self.vodPlayFrom componentsSeparatedByString:@"$$$"];
        } else {
            names = [self.vodPlayFrom componentsSeparatedByString:@","];
        }
    }

    NSMutableArray<TVPlaySource *> *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < groups.count; i++) {
        NSString *group = groups[i];
        if (group.length == 0) continue;

        TVPlaySource *source = [[TVPlaySource alloc] init];
        if (i < names.count && names[i].length > 0) {
            source.name = names[i];
        } else {
            source.name = [NSString stringWithFormat:@"线路%lu", (unsigned long)(i + 1)];
        }

        NSArray<NSString *> *episodesRaw = [group componentsSeparatedByString:@"#"];
        NSMutableArray<TVEpisode *> *episodes = [NSMutableArray array];
        for (NSString *raw in episodesRaw) {
            NSString *episodeName;
            NSString *episodeURL;
            NSRange dollar = [raw rangeOfString:@"$"];
            if (dollar.location != NSNotFound) {
                episodeName = [raw substringToIndex:dollar.location];
                episodeURL = [raw substringFromIndex:NSMaxRange(dollar)];
            } else {
                episodeName = [NSString stringWithFormat:@"第%lu集", (unsigned long)(episodes.count + 1)];
                episodeURL = raw;
            }
            episodeURL = [episodeURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (episodeURL.length == 0) continue;

            TVEpisode *episode = [[TVEpisode alloc] init];
            episode.name = episodeName;
            episode.url = episodeURL;
            [episodes addObject:episode];
        }
        source.episodes = episodes;
        [result addObject:source];
    }
    return result;
}

- (NSInteger)totalEpisodeCount {
    NSInteger count = 0;
    for (TVPlaySource *source in self.playSources) {
        count += (NSInteger)source.episodes.count;
    }
    if (count > 0) return count;

    // 播放地址为空时，从备注中提取集数（如 "全38集"、"更新至第25集"、"共40集"）
    NSString *remarks = self.remarks ?: @"";
    if (remarks.length == 0) return 0;

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\s*集" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:remarks options:0 range:NSMakeRange(0, remarks.length)];
    if (match && match.numberOfRanges > 1) {
        NSString *num = [remarks substringWithRange:[match rangeAtIndex:1]];
        return [num integerValue];
    }
    return 0;
}

@end

@implementation TVSite
@end

@implementation TVLiveSource
@end

@implementation TVLiveLine
@end

@implementation TVLiveChannel

- (NSString *)sourceNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (TVLiveLine *line in self.lines) {
        NSString *name = line.sourceName.length > 0 ? line.sourceName : @"";
        if (name.length > 0 && ![names containsObject:name]) {
            [names addObject:name];
        }
    }
    return [names componentsJoinedByString:@"、"];
}

@end

@implementation TVParse
@end

@implementation TVHistoryItem

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"isLive"] = @(self.isLive);
    dict[@"title"] = self.title ?: @"";
    dict[@"subtitle"] = self.subtitle ?: @"";
    dict[@"posterURL"] = self.posterURL ?: @"";
    dict[@"episodeName"] = self.episodeName ?: @"";
    dict[@"sourceIndex"] = @(self.sourceIndex);
    dict[@"episodeIndex"] = @(self.episodeIndex);
    dict[@"playbackTime"] = @(self.playbackTime);
    dict[@"date"] = @(self.date ? self.date.timeIntervalSince1970 : 0);
    if (self.payload && [NSJSONSerialization isValidJSONObject:self.payload]) {
        dict[@"payload"] = self.payload;
    } else {
        dict[@"payload"] = @{};
    }
    return dict;
}

+ (instancetype)historyItemFromDictionary:(NSDictionary *)dict {
    TVHistoryItem *item = [[TVHistoryItem alloc] init];
    item.isLive = [dict[@"isLive"] boolValue];
    item.title = MMString(dict[@"title"]);
    item.subtitle = MMString(dict[@"subtitle"]);
    item.posterURL = MMString(dict[@"posterURL"]);
    item.episodeName = MMString(dict[@"episodeName"]);
    item.sourceIndex = MMInteger(dict[@"sourceIndex"]);
    item.episodeIndex = MMInteger(dict[@"episodeIndex"]);
    item.playbackTime = [dict[@"playbackTime"] doubleValue];
    double dateValue = [dict[@"date"] doubleValue];
    item.date = dateValue > 0 ? [NSDate dateWithTimeIntervalSince1970:dateValue] : [NSDate date];
    id payload = dict[@"payload"];
    item.payload = [payload isKindOfClass:[NSDictionary class]] ? payload : @{};
    return item;
}

@end