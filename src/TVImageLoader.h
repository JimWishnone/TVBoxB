#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TVImageLoader : NSObject

+ (void)loadImageAtURL:(NSString *)urlString
            completion:(void (^)(NSImage * _Nullable image))completion;

@end

NS_ASSUME_NONNULL_END