#import <Cocoa/Cocoa.h>

@class TVVideo;

@interface TVPosterImageView : NSImageView
@end

@interface TVNonInteractiveLabel : NSTextField
@end

// 渐变背景视图：使用 CAGradientLayer 绘制上下渐变色，用于增强界面视觉效果。
@interface TVGradientView : NSView
- (instancetype)initWithColors:(NSArray<NSColor *> *)colors;
@end

@interface VODCollectionItem : NSCollectionViewItem
@property (nonatomic, copy) NSString *posterURLString;
@property (nonatomic, strong) NSImageView *posterView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
- (void)configureWithVideo:(TVVideo *)video;
+ (NSImage *)defaultPosterImage;
@end