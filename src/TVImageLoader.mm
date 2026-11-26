#import "TVImageLoader.h"
#import "Models.h"
#import "ConfigManager.h"

static NSCache<NSString *, NSImage *> *TVImageMemoryCache(void) {
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 600;
    });
    return cache;
}

static NSString *TVImageDiskDirectory(void) {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        dir = [[caches stringByAppendingPathComponent:@"TVBox"] stringByAppendingPathComponent:@"ImageCache"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return dir;
}

static NSString *TVImageDiskPath(NSString *urlString) {
    return [TVImageDiskDirectory() stringByAppendingPathComponent:[TVBoxHexHash(urlString) stringByAppendingString:@".img"]];
}

@implementation TVImageLoader {
    dispatch_queue_t _inFlightQueue;
    NSMutableDictionary<NSString *, NSMutableArray<void (^)(NSImage * _Nullable)> *> *_inFlight;
}

+ (instancetype)sharedLoader {
    static TVImageLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TVImageLoader alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _inFlightQueue = dispatch_queue_create("com.tvbox.imageloader.inflight", DISPATCH_QUEUE_SERIAL);
        _inFlight = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (void)loadImageAtURL:(NSString *)urlString
            completion:(void (^)(NSImage * _Nullable image))completion {
    [[TVImageLoader sharedLoader] loadImageAtURL:urlString completion:completion];
}

- (void)loadImageAtURL:(NSString *)urlString
            completion:(void (^)(NSImage * _Nullable image))completion {
    if (urlString.length == 0) {
        if (completion) completion(nil);
        return;
    }

    NSCache<NSString *, NSImage *> *cache = TVImageMemoryCache();
    NSImage *cached = [cache objectForKey:urlString];
    if (cached) {
        if (completion) completion(cached);
        return;
    }

    NSData *diskData = [NSData dataWithContentsOfFile:TVImageDiskPath(urlString)];
    if (diskData) {
        NSImage *diskImage = [[NSImage alloc] initWithData:diskData];
        if (diskImage) {
            [cache setObject:diskImage forKey:urlString];
            if (completion) completion(diskImage);
            return;
        }
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(nil);
        return;
    }

    __block BOOL shouldStartRequest = NO;
    dispatch_sync(_inFlightQueue, ^{
        NSMutableArray<void (^)(NSImage * _Nullable)> *waiters = self->_inFlight[urlString];
        if (waiters) {
            if (completion) [waiters addObject:[completion copy]];
            shouldStartRequest = NO;
        } else {
            waiters = [NSMutableArray array];
            if (completion) [waiters addObject:[completion copy]];
            self->_inFlight[urlString] = waiters;
            shouldStartRequest = YES;
        }
    });

    if (!shouldStartRequest) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 10.0;
    [request setValue:TVBoxHTTPUserAgent forHTTPHeaderField:@"User-Agent"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSImage *image = nil;
            if (!error && data) {
                image = [[NSImage alloc] initWithData:data];
            }
            if (image) {
                [cache setObject:image forKey:urlString];
                [data writeToFile:TVImageDiskPath(urlString) atomically:YES];
            }

            __block NSArray<void (^)(NSImage * _Nullable)> *callbacks = nil;
            dispatch_sync(self->_inFlightQueue, ^{
                callbacks = [self->_inFlight[urlString] copy];
                [self->_inFlight removeObjectForKey:urlString];
            });

            dispatch_async(dispatch_get_main_queue(), ^{
                for (void (^block)(NSImage * _Nullable) in callbacks) {
                    block(image);
                }
            });
        }] resume];
}

@end