#import "TVBoxVLCPlayerView.h"
#import <vlc/vlc.h>
#import <dlfcn.h>

static NSString * const kTVBoxVLCExternalPath = @"/Applications/VLC.app";

static BOOL kTVBoxVLCUseBundled = NO;
static NSString *kTVBoxVLCLibPath = nil;
static NSString *kTVBoxVLCPluginsPath = nil;
static NSString *kTVBoxVLCDataPath = nil;

static void TVBoxVLCResolvePaths(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSString *bundledLib = [[NSBundle mainBundle] pathForResource:@"Frameworks/vlc/lib" ofType:nil];
        NSString *bundledPlugins = [[NSBundle mainBundle] pathForResource:@"Frameworks/vlc/plugins" ofType:nil];
        NSString *bundledShare = [[NSBundle mainBundle] pathForResource:@"Frameworks/vlc/share" ofType:nil];

        if (bundledLib && bundledPlugins && bundledShare
            && [fm fileExistsAtPath:bundledLib]
            && [fm fileExistsAtPath:bundledPlugins]
            && [fm fileExistsAtPath:bundledShare]) {
            kTVBoxVLCUseBundled = YES;
            kTVBoxVLCLibPath = bundledLib;
            kTVBoxVLCPluginsPath = bundledPlugins;
            kTVBoxVLCDataPath = [[NSBundle mainBundle] pathForResource:@"Frameworks/vlc" ofType:nil];
            NSLog(@"[TVBoxVLC] Using bundled VLC at %@", kTVBoxVLCLibPath);
        } else if ([fm fileExistsAtPath:kTVBoxVLCExternalPath]) {
            kTVBoxVLCUseBundled = NO;
            kTVBoxVLCLibPath = [kTVBoxVLCExternalPath stringByAppendingPathComponent:@"Contents/MacOS/lib"];
            kTVBoxVLCPluginsPath = [kTVBoxVLCExternalPath stringByAppendingPathComponent:@"Contents/MacOS/plugins"];
            kTVBoxVLCDataPath = [kTVBoxVLCExternalPath stringByAppendingPathComponent:@"Contents/MacOS"];
            NSLog(@"[TVBoxVLC] Using external VLC at %@", kTVBoxVLCExternalPath);
        } else {
            NSLog(@"[TVBoxVLC] ERROR: No VLC found (neither bundled nor /Applications/VLC.app)");
        }
    });
}

static libvlc_instance_t *_vlcInstance = nil;
static dispatch_once_t _vlcInitOnce;

static void TVBoxVLCLogCallback(void *data, int level, const vlc_log_t *ctx, const char *fmt, char *args) {
    char msg[1024];
    vsnprintf(msg, sizeof(msg), fmt, args);
    NSLog(@"[VLC libvlc] %s", msg);
}

static void TVBoxVLCPlayerEventCallback(const struct libvlc_event_t *event, void *data) {
    TVBoxVLCPlayerView *self = (__bridge TVBoxVLCPlayerView *)data;
    if (!self) return;
    switch (event->type) {
        case libvlc_MediaPlayerEncounteredError:
            NSLog(@"[TVBoxVLC] MediaPlayerEncounteredError");
            if (self.onPlaybackError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.onPlaybackError();
                });
            }
            break;
        case libvlc_MediaPlayerEndReached:
            NSLog(@"[TVBoxVLC] MediaPlayerEndReached");
            break;
        case libvlc_MediaPlayerStopped:
            NSLog(@"[TVBoxVLC] MediaPlayerStopped");
            break;
        case libvlc_MediaPlayerPlaying:
            NSLog(@"[TVBoxVLC] MediaPlayerPlaying");
            break;
        case libvlc_MediaPlayerPaused:
            NSLog(@"[TVBoxVLC] MediaPlayerPaused");
            break;
        default:
            break;
    }
}

static void TVBoxVLCInitInstance(void) {
    dispatch_once(&_vlcInitOnce, ^{
        TVBoxVLCResolvePaths();

        setenv("VLC_PLUGIN_PATH", [kTVBoxVLCPluginsPath cStringUsingEncoding:NSUTF8StringEncoding], 1);
        setenv("VLC_DATA_PATH", [kTVBoxVLCDataPath cStringUsingEncoding:NSUTF8StringEncoding], 1);
        setenv("VLC_LIB_PATH", [kTVBoxVLCLibPath cStringUsingEncoding:NSUTF8StringEncoding], 1);

        const char *args[] = {
            "--no-video-title-show",
            "--no-osd",
            "--no-skip-frames",
            "--verbose=3",
        };

        _vlcInstance = libvlc_new(sizeof(args) / sizeof(args[0]), args);
        if (_vlcInstance) {
            libvlc_log_set(_vlcInstance, TVBoxVLCLogCallback, NULL);
            NSLog(@"[TVBoxVLC] VLC instance created OK at %p", _vlcInstance);
        } else {
            NSLog(@"[TVBoxVLC] FAILED to create VLC instance!");
        }
    });
}

@interface TVBoxVLCPlayerView ()
@property (nonatomic, assign) libvlc_media_player_t *player;
@property (nonatomic, assign) libvlc_media_t *media;
@property (nonatomic, assign) BOOL outputBound;
@property (nonatomic, assign) BOOL eventsDetached;
@end

@implementation TVBoxVLCPlayerView {
    float _rate;
    BOOL _paused;
}

+ (BOOL)vlcAvailable {
    TVBoxVLCResolvePaths();
    BOOL libOK = [[NSFileManager defaultManager] fileExistsAtPath:kTVBoxVLCLibPath];
    BOOL pluginsOK = [[NSFileManager defaultManager] fileExistsAtPath:kTVBoxVLCPluginsPath];
    BOOL ok = libOK && pluginsOK;
    NSLog(@"[TVBoxVLC] vlcAvailable: lib=%@ plugins=%@ ok=%d", kTVBoxVLCLibPath, kTVBoxVLCPluginsPath, ok);
    return ok;
}

+ (BOOL)checkVLCCapable {
    TVBoxVLCResolvePaths();
    if (!kTVBoxVLCLibPath || !kTVBoxVLCPluginsPath) {
        NSLog(@"[TVBoxVLC] checkVLCCapable FAIL: no VLC paths resolved");
        return NO;
    }

    setenv("VLC_PLUGIN_PATH", [kTVBoxVLCPluginsPath UTF8String], 1);
    setenv("VLC_DATA_PATH", [kTVBoxVLCDataPath UTF8String], 1);
    setenv("VLC_LIB_PATH", [kTVBoxVLCLibPath UTF8String], 1);

    const char *args[] = {
        "--no-video-title-show",
        "--no-osd",
        "--no-skip-frames",
    };

    libvlc_instance_t *inst = libvlc_new(sizeof(args) / sizeof(args[0]), args);
    if (!inst) {
        NSLog(@"[TVBoxVLC] checkVLCCapable FAIL: libvlc_new returned NULL");
        return NO;
    }

    NSLog(@"[TVBoxVLC] checkVLCCapable OK: libvlc instance created at %p", inst);
    libvlc_release(inst);
    return YES;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.layer.backgroundColor = [NSColor blackColor].CGColor;
        _paused = YES;
        _rate = 1.0f;

        NSLog(@"[TVBoxVLC] initWithFrame: %@", NSStringFromRect(frame));

        if (![TVBoxVLCPlayerView vlcAvailable]) {
            NSLog(@"[TVBoxVLC] VLC not available");
            return self;
        }

        TVBoxVLCInitInstance();
        if (_vlcInstance) {
            _player = libvlc_media_player_new(_vlcInstance);
            NSLog(@"[TVBoxVLC] media_player created at %p", _player);

            libvlc_event_manager_t *em = libvlc_media_player_event_manager(_player);
            libvlc_event_attach(em, libvlc_MediaPlayerEncounteredError, TVBoxVLCPlayerEventCallback, (__bridge void *)self);
            libvlc_event_attach(em, libvlc_MediaPlayerPlaying, TVBoxVLCPlayerEventCallback, (__bridge void *)self);
            libvlc_event_attach(em, libvlc_MediaPlayerStopped, TVBoxVLCPlayerEventCallback, (__bridge void *)self);
            libvlc_event_attach(em, libvlc_MediaPlayerEndReached, TVBoxVLCPlayerEventCallback, (__bridge void *)self);
            libvlc_event_attach(em, libvlc_MediaPlayerPaused, TVBoxVLCPlayerEventCallback, (__bridge void *)self);
            NSLog(@"[TVBoxVLC] event listeners attached");
        } else {
            NSLog(@"[TVBoxVLC] FAILED: VLC instance is NULL");
        }
    }
    return self;
}

- (BOOL)initialized {
    return _player != NULL;
}

- (void)detachEventListenersIfNeeded {
    if (!_player || _eventsDetached) return;
    libvlc_event_manager_t *em = libvlc_media_player_event_manager(_player);
    libvlc_event_detach(em, libvlc_MediaPlayerEncounteredError, TVBoxVLCPlayerEventCallback, (__bridge void *)self);
    libvlc_event_detach(em, libvlc_MediaPlayerPlaying, TVBoxVLCPlayerEventCallback, (__bridge void *)self);
    libvlc_event_detach(em, libvlc_MediaPlayerStopped, TVBoxVLCPlayerEventCallback, (__bridge void *)self);
    libvlc_event_detach(em, libvlc_MediaPlayerEndReached, TVBoxVLCPlayerEventCallback, (__bridge void *)self);
    libvlc_event_detach(em, libvlc_MediaPlayerPaused, TVBoxVLCPlayerEventCallback, (__bridge void *)self);
    _eventsDetached = YES;
}

- (void)dealloc {
    [self detachEventListenersIfNeeded];
    if (_media) {
        libvlc_media_release(_media);
        _media = NULL;
    }
    if (_player) {
        libvlc_media_player_stop(_player);
        libvlc_media_player_release(_player);
        _player = NULL;
    }
}

- (void)bindVideoOutputIfNeeded {
    if (!_player || _outputBound) return;
    if (NSIsEmptyRect(self.frame)) {
        NSLog(@"[TVBoxVLC] bindVideoOutputIfNeeded: SKIP (empty frame %@)", NSStringFromRect(self.frame));
        return;
    }

    NSLog(@"[TVBoxVLC] libvlc_media_player_set_nsobject player=%p view=%p", _player, (__bridge void *)self);
    libvlc_media_player_set_nsobject(_player, (__bridge void *)self);
    _outputBound = YES;
}

- (void)playURL:(NSString *)urlString {
    NSLog(@"[TVBoxVLC] playURL: %@", urlString);

    if (!_player) {
        NSLog(@"[TVBoxVLC] ERROR: _player is NULL");
        return;
    }
    if (urlString.length == 0) {
        NSLog(@"[TVBoxVLC] ERROR: empty URL");
        return;
    }

    [self bindVideoOutputIfNeeded];

    if (_media) {
        libvlc_media_release(_media);
        _media = NULL;
    }
    libvlc_media_player_stop(_player);

    const char *urlCstr = [urlString cStringUsingEncoding:NSUTF8StringEncoding];
    _media = libvlc_media_new_location(_vlcInstance, urlCstr);
    NSLog(@"[TVBoxVLC] libvlc_media_new_location -> media=%p", _media);
    if (!_media) {
        NSLog(@"[TVBoxVLC] ERROR: failed to create media from URL");
        return;
    }

    libvlc_media_player_set_media(_player, _media);
    libvlc_media_player_set_video_title_display(_player, libvlc_position_disable, 0);

    int rc = libvlc_media_player_play(_player);
    NSLog(@"[TVBoxVLC] libvlc_media_player_play -> rc=%d state=%d", rc, libvlc_media_player_get_state(_player));

    self.paused = NO;
}

- (void)play {
    if (!_player) return;
    libvlc_media_player_play(_player);
    self.paused = NO;
}

- (void)pause {
    if (!_player) return;
    libvlc_media_player_pause(_player);
    self.paused = YES;
}

- (void)stop {
    if (!_player) return;
    libvlc_media_player_stop(_player);
    self.paused = YES;
}

- (void)seekToTime:(NSTimeInterval)seconds {
    if (!_player) return;
    libvlc_media_player_set_time(_player, (libvlc_time_t)(seconds * 1000));
}

- (NSTimeInterval)currentTime {
    if (!_player) return 0;
    libvlc_time_t t = libvlc_media_player_get_time(_player);
    if (t == -1) return 0;
    return (NSTimeInterval)t / 1000.0;
}

- (NSTimeInterval)duration {
    if (!_player) return 0;
    libvlc_time_t t = libvlc_media_player_get_length(_player);
    if (t == -1) return 0;
    return (NSTimeInterval)t / 1000.0;
}

- (void)setRate:(float)rate {
    if (!_player) return;
    _rate = rate;
    libvlc_media_player_set_rate(_player, rate);
}

- (float)rate {
    if (!_player) return _rate;
    return libvlc_media_player_get_rate(_player);
}

- (void)layout {
    [super layout];
    NSLog(@"[TVBoxVLC] layout frame=%@", NSStringFromRect(self.frame));
    [self bindVideoOutputIfNeeded];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    NSLog(@"[TVBoxVLC] viewDidMoveToWindow window=%@ frame=%@", self.window, NSStringFromRect(self.frame));
    if (self.window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"[TVBoxVLC] async frame=%@", NSStringFromRect(self.frame));
            [self bindVideoOutputIfNeeded];
        });
    }
}

@end