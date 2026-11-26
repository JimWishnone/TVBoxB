#import <Foundation/Foundation.h>
#import "Models.h"

NS_ASSUME_NONNULL_BEGIN

@interface TVLiveSourceParser : NSObject

+ (NSArray<TVLiveChannel *> *)parseLiveChannelsFromText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END