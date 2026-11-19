#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TVSite;

// 视频分类
@interface TVCategory : NSObject
@property (nonatomic, assign) NSInteger typeId;
@property (nonatomic, assign) NSInteger typePid;
@property (nonatomic, copy) NSString *name;
+ (instancetype)categoryFromDictionary:(NSDictionary *)dict;
@end

// 单集播放地址
@interface TVEpisode : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *url;
@end

// 一条播放线路（播放源），包含多个剧集
@interface TVPlaySource : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSArray<TVEpisode *> *episodes;
@end

// 点播视频条目
@interface TVVideo : NSObject
@property (nonatomic, assign) NSInteger vodId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger typeId;
@property (nonatomic, copy) NSString *typeName;
@property (nonatomic, copy) NSString *remarks;
@property (nonatomic, copy) NSString *vodPic;
@property (nonatomic, copy) NSString *vodEn;
@property (nonatomic, copy) NSString *vodTime;
@property (nonatomic, copy) NSString *vodActor;
@property (nonatomic, copy) NSString *vodDirector;
@property (nonatomic, copy) NSString *vodContent;
@property (nonatomic, copy) NSString *vodPlayFrom;
@property (nonatomic, copy) NSString *vodPlayUrl;
// 该视频所属的数据源（搜索跨站点时记录来源）
@property (nonatomic, strong, nullable) TVSite *sourceSite;

+ (instancetype)videoFromDictionary:(NSDictionary *)dict;
- (NSArray<TVPlaySource *> *)playSources;
// 计算总集数（优先解析播放地址，其次从备注中提取）
- (NSInteger)totalEpisodeCount;
@end

// 点播站点（仅保留可直接访问的苹果 CMS 接口站，type == 1）
@interface TVSite : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, copy) NSString *api;
@property (nonatomic, assign) BOOL searchable;
@property (nonatomic, assign) BOOL filterable;
@property (nonatomic, strong) NSArray<NSString *> *categories;
@end

// 直播源配置
@interface TVLiveSource : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) NSInteger playerType;
@property (nonatomic, copy) NSString *ua;
@property (nonatomic, copy) NSString *epg;
@property (nonatomic, copy) NSString *logo;
@end

// 直播线路（同一频道在不同“数据源+线路”下的播放地址）
@interface TVLiveLine : NSObject
@property (nonatomic, copy) NSString *sourceName; // 数据源名称
@property (nonatomic, copy) NSString *name;       // 完整线路名称（数据源 + 线路序号）
@property (nonatomic, copy) NSString *url;
@end

// 直播频道
@interface TVLiveChannel : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *group;
@property (nonatomic, copy) NSString *logo;
// 合并后的多线路（不同数据源为不同线路）
@property (nonatomic, strong) NSArray<TVLiveLine *> *lines;
// 该频道合并线路对应的数据源名称（去重后拼接，用于列表展示与排序）
@property (nonatomic, readonly) NSString *sourceNames;
@end

// 解析接口
@interface TVParse : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, copy) NSString *url;
@end

// 历史播放记录（点播或直播）
@interface TVHistoryItem : NSObject
@property (nonatomic, assign) BOOL isLive;                 // YES 直播，NO 点播
@property (nonatomic, copy) NSString *title;               // 名称（片名 / 频道名）
@property (nonatomic, copy) NSString *subtitle;            // 副标题（数据源 + 集数 / 分组等）
@property (nonatomic, copy) NSString *posterURL;           // 海报 / 频道图标
@property (nonatomic, copy) NSString *episodeName;         // 第几集名称（点播）
@property (nonatomic, assign) NSInteger sourceIndex;       // 播放源 / 线路索引
@property (nonatomic, assign) NSInteger episodeIndex;      // 集数索引
@property (nonatomic, assign) NSTimeInterval playbackTime; // 当时的播放时间（秒）
@property (nonatomic, strong) NSDate *date;                // 播放时间
@property (nonatomic, strong) NSDictionary *payload;       // 用于继续播放的完整数据

- (NSDictionary *)toDictionary;
+ (nullable instancetype)historyItemFromDictionary:(NSDictionary *)dict;
@end

NS_ASSUME_NONNULL_END