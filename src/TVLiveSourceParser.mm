#import "TVLiveSourceParser.h"

@implementation TVLiveSourceParser

+ (NSArray<TVLiveChannel *> *)parseLiveChannelsFromText:(NSString *)text {
    if (text.length == 0) return @[];
    NSMutableArray<TVLiveChannel *> *channels = [NSMutableArray array];

    BOOL isM3U = ([text containsString:@"#EXTM3U"] || [text containsString:@"#EXTINF"]);
    if (isM3U) {
        [self parseM3U:text intoChannels:channels];
    } else {
        [self parseDIYPText:text intoChannels:channels];
    }
    return channels;
}

+ (void)parseM3U:(NSString *)text intoChannels:(NSMutableArray<TVLiveChannel *> *)channels {
    NSString *currentName = nil;
    NSString *currentGroup = @"";
    NSString *currentLogo = @"";

    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *raw in lines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;

        if ([line hasPrefix:@"#EXTINF"]) {
            currentGroup = [self attributeValue:@"group-title" inLine:line];
            currentLogo = [self attributeValue:@"tvg-logo" inLine:line];
            NSRange comma = [line rangeOfString:@"," options:NSBackwardsSearch];
            if (comma.location != NSNotFound) {
                currentName = [[line substringFromIndex:NSMaxRange(comma)]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        } else if ([line hasPrefix:@"#"]) {
            continue;
        } else if (currentName.length > 0 && ([line hasPrefix:@"http://"] || [line hasPrefix:@"https://"])) {
            TVLiveChannel *channel = [[TVLiveChannel alloc] init];
            channel.name = currentName;
            channel.url = line;
            channel.group = currentGroup;
            channel.logo = currentLogo;
            [channels addObject:channel];
            currentName = nil;
        }
    }
}

+ (void)parseDIYPText:(NSString *)text intoChannels:(NSMutableArray<TVLiveChannel *> *)channels {
    NSString *currentGroup = @"";

    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *raw in lines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;

        if ([line hasSuffix:@",#genre#"]) {
            currentGroup = [line stringByReplacingOccurrencesOfString:@",#genre#" withString:@""];
            continue;
        }

        NSRange comma = [line rangeOfString:@","];
        if (comma.location == NSNotFound) continue;

        NSString *name = [[line substringToIndex:comma.location]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *url = [[line substringFromIndex:NSMaxRange(comma)]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (name.length > 0 && ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"])) {
            TVLiveChannel *channel = [[TVLiveChannel alloc] init];
            channel.name = name;
            channel.url = url;
            channel.group = currentGroup;
            channel.logo = @"";
            [channels addObject:channel];
        }
    }
}

+ (NSString *)attributeValue:(NSString *)attribute inLine:(NSString *)line {
    NSString *pattern = [NSString stringWithFormat:@"%@=\"([^\"]*)\"", attribute];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (match && match.numberOfRanges > 1) {
        return [line substringWithRange:[match rangeAtIndex:1]];
    }
    return @"";
}

@end