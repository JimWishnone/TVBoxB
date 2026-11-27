#import <Cocoa/Cocoa.h>

@interface TVLiveIconCell : NSTableCellView
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, copy) NSString *channelKey;
@end

// 直播频道单元格：频道名 + 右侧可点击的“节目单”链接（有节目单时才显示）+ 收藏按钮（悬停显示）
@interface TVChannelCellView : NSTableCellView
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSButton *programLink;
@property (nonatomic, strong) NSButton *favoriteButton;
@property (nonatomic, copy) void (^onProgramClick)(void);
@property (nonatomic, copy) void (^onFavoriteClick)(void);
@property (nonatomic, assign) BOOL favorited;
- (void)refreshHoverState;
@end

// 收藏夹单元格：名称 + 悬停显示的删除按钮
@interface TVFavoriteCellView : NSTableCellView
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSButton *deleteButton;
@property (nonatomic, copy) void (^onDelete)(void);
@end