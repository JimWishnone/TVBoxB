#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TVBoxVLCPlayerView : NSView

@property (nonatomic, readonly) BOOL initialized;
@property (nonatomic, assign) float rate;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, copy, nullable) void (^onPlaybackError)(void);
@property (nonatomic, copy, nullable) void (^onPlaybackEnded)(void);
@property (nonatomic, copy, nullable) void (^onPlaybackStateChanged)(BOOL paused);

+ (BOOL)vlcAvailable;
+ (BOOL)checkVLCCapable;

- (instancetype)initWithFrame:(NSRect)frame;

- (void)playURL:(NSString *)urlString;
- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToTime:(NSTimeInterval)seconds;
- (NSTimeInterval)currentTime;
- (NSTimeInterval)duration;
- (void)setRate:(float)rate;
- (void)dealloc;

@end

NS_ASSUME_NONNULL_END