#import <Foundation/Foundation.h>
#import "Models.h"

NS_ASSUME_NONNULL_BEGIN

// 验证过程的进度回调：用于逐步展示“地址格式 / 可访问 / 可解析 / 数据格式校验”等详细过程
typedef void (^TVValidateProgressBlock)(NSString * _Nullable stepMessage);

@interface ConfigManager : NSObject

@property (nonatomic, readonly) NSArray<TVSite *> *vodSites;
@property (nonatomic, readonly) NSArray<TVLiveSource *> *liveSources;
@property (nonatomic, readonly) NSArray<TVParse *> *parses;

+ (instancetype)sharedManager;

// 拉取并解析配置（兼容 official.json 单仓与 tvbox.json 多仓两种格式），完成回调始终在主线程执行
- (void)loadConfigWithCompletion:(void (^)(NSError * _Nullable error))completion;

// 当前生效的数据源配置地址列表（仅来自用户设置）
- (NSArray<NSString *> *)configURLs;

// 保存用户自定义的数据源配置地址列表
- (void)saveConfigURLs:(NSArray<NSString *> *)urls;

// 清除用户自定义配置
- (void)resetConfigURLs;

// 验证点播配置 URL：可访问、可解析、且是 TVBox 支持的配置格式；
// 验证过程中通过 progressBlock 逐步回调详细进度信息；
// 成功时返回该配置中包含的直播源数组（可能为空数组），失败时返回 error。
- (void)validateVODConfigURL:(NSString *)urlString
                     progress:(nullable TVValidateProgressBlock)progressBlock
                   completion:(void (^)(NSArray<TVLiveSource *> * _Nullable liveSources, NSError * _Nullable error))completion;

// 验证直播视频源 URL：可访问、且能解析出直播数据（JSON 配置的 lives/urls，或 m3u / DIYP 文本）；
// 验证过程中通过 progressBlock 逐步回调详细进度信息，失败时返回 error。
- (void)validateLiveConfigURL:(NSString *)urlString
                      progress:(nullable TVValidateProgressBlock)progressBlock
                    completion:(void (^)(NSError * _Nullable error))completion;

// 直播视频源（专属直播的数据源，选填）地址列表，未设置时返回空数组
- (NSArray<NSString *> *)liveConfigURLs;

// 保存用户自定义的直播数据源地址列表
- (void)saveLiveConfigURLs:(NSArray<NSString *> *)urls;

// 清除用户自定义的直播数据源，恢复使用主数据源中的直播源
- (void)resetLiveConfigURLs;

// 当前直播数据源关联的节目单地址（EPG，选填），未设置时返回 nil
- (nullable NSString *)liveEPGURL;

// 保存直播数据源关联的节目单地址（EPG），传入空字符串则清除
- (void)saveLiveEPGURL:(NSString *)url;

// 发起 JSON 请求，完成回调始终在主线程执行
- (void)requestJSONFromURL:(NSURL *)url completion:(void (^)(id _Nullable json, NSError * _Nullable error))completion;

// 拉取文本内容，完成回调始终在主线程执行
- (void)fetchStringFromURL:(NSURL *)url completion:(void (^)(NSString * _Nullable text, NSError * _Nullable error))completion;

// 根据站点接口与查询参数构造 URL（自动合并、覆盖已有 query 项）
- (NSURL *)vodURLForSite:(TVSite *)site params:(NSDictionary<NSString *, NSString *> *)params;

// 解析直播节目单（支持 m3u 与 DIYP txt 两种格式）
- (NSArray<TVLiveChannel *> *)parseLiveChannelsFromText:(NSString *)text;

// 拉取并解析某个频道的节目单（EPG），支持 DIYP JSON 与 XMLTV XML 两种格式；完成回调始终在主线程执行
- (void)fetchProgramsForChannel:(NSString *)channelName
                        epgURL:(NSString *)epgURL
                    completion:(void (^)(NSArray<TVLiveProgram *> * _Nullable programs))completion;

@end

NS_ASSUME_NONNULL_END