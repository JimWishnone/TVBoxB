#import <Foundation/Foundation.h>
#import "Models.h"

NS_ASSUME_NONNULL_BEGIN

@interface ConfigManager : NSObject

@property (nonatomic, readonly) NSArray<TVSite *> *vodSites;
@property (nonatomic, readonly) NSArray<TVLiveSource *> *liveSources;
@property (nonatomic, readonly) NSArray<TVParse *> *parses;

+ (instancetype)sharedManager;

// 拉取并解析配置（兼容 official.json 单仓与 tvbox.json 多仓两种格式），完成回调始终在主线程执行
- (void)loadConfigWithCompletion:(void (^)(NSError * _Nullable error))completion;

// 当前生效的数据源配置地址列表（优先使用用户设置，未设置时使用内置镜像）
- (NSArray<NSString *> *)configURLs;

// 保存用户自定义的数据源配置地址列表
- (void)saveConfigURLs:(NSArray<NSString *> *)urls;

// 清除用户自定义配置，恢复内置默认镜像地址
- (void)resetConfigURLs;

// 直播视频源（专属直播的数据源，选填）地址列表，未设置时返回空数组
- (NSArray<NSString *> *)liveConfigURLs;

// 保存用户自定义的直播数据源地址列表
- (void)saveLiveConfigURLs:(NSArray<NSString *> *)urls;

// 清除用户自定义的直播数据源，恢复使用主数据源中的直播源
- (void)resetLiveConfigURLs;

// 发起 JSON 请求，完成回调始终在主线程执行
- (void)requestJSONFromURL:(NSURL *)url completion:(void (^)(id _Nullable json, NSError * _Nullable error))completion;

// 拉取文本内容，完成回调始终在主线程执行
- (void)fetchStringFromURL:(NSURL *)url completion:(void (^)(NSString * _Nullable text, NSError * _Nullable error))completion;

// 根据站点接口与查询参数构造 URL（自动合并、覆盖已有 query 项）
- (NSURL *)vodURLForSite:(TVSite *)site params:(NSDictionary<NSString *, NSString *> *)params;

// 解析直播节目单（支持 m3u 与 DIYP txt 两种格式）
- (NSArray<TVLiveChannel *> *)parseLiveChannelsFromText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END