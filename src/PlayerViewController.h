#import <Cocoa/Cocoa.h>
#import "Models.h"

@interface PlayerViewController : NSViewController

- (void)playVideo:(TVVideo *)video;
- (void)resumeVideo:(TVVideo *)video sourceIndex:(NSInteger)sourceIndex episodeIndex:(NSInteger)episodeIndex resumeTime:(NSTimeInterval)resumeTime;
- (void)playLiveChannel:(TVLiveChannel *)channel;
- (void)playLiveChannels:(NSArray<TVLiveChannel *> *)channels atIndex:(NSInteger)index;
- (void)stop;
- (NSTimeInterval)currentPlaybackTime;
// 将当前播放状态（集数、线路、频道、播放时间等）同步到历史记录条目
- (void)syncPlaybackStateToHistoryItem:(TVHistoryItem *)item;

@end