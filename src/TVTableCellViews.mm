#import "TVTableCellViews.h"

@implementation TVLiveIconCell
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _iconView = [[NSImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _iconView.wantsLayer = YES;
        _iconView.layer.cornerRadius = 4;
        _iconView.layer.masksToBounds = YES;
        [self addSubview:_iconView];
        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:24],
            [_iconView.heightAnchor constraintEqualToConstant:24],
        ]];
    }
    return self;
}
@end

@implementation TVChannelCellView {
    BOOL _hovered;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _nameLabel = [NSTextField labelWithString:@""];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_nameLabel];

        NSMutableAttributedString *linkTitle = [[NSMutableAttributedString alloc] initWithString:@"节目单" attributes:@{
            NSForegroundColorAttributeName: [NSColor linkColor],
            NSFontAttributeName: [NSFont systemFontOfSize:11],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        }];
        _programLink = [NSButton buttonWithTitle:@"" target:self action:@selector(programLinkClicked:)];
        _programLink.attributedTitle = linkTitle;
        _programLink.bordered = NO;
        _programLink.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_programLink];

        _favoriteButton = [NSButton buttonWithTitle:@"" target:self action:@selector(favoriteButtonClicked:)];
        _favoriteButton.bordered = NO;
        _favoriteButton.imagePosition = NSImageOnly;
        _favoriteButton.translatesAutoresizingMaskIntoConstraints = NO;
        _favoriteButton.hidden = YES;
        [self addSubview:_favoriteButton];

        [NSLayoutConstraint activateConstraints:@[
            [_favoriteButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_favoriteButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_favoriteButton.widthAnchor constraintEqualToConstant:18],
            [_favoriteButton.heightAnchor constraintEqualToConstant:18],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_favoriteButton.trailingAnchor constant:6],
            [_nameLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_programLink.leadingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor constant:8],
            [_programLink.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_programLink.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-4],
        ]];
        [_nameLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_programLink setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_favoriteButton setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                        options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect)
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseEntered:(NSEvent *)event {
    _hovered = YES;
    [self updateFavoriteButton];
}

- (void)mouseExited:(NSEvent *)event {
    _hovered = NO;
    [self updateFavoriteButton];
}

- (void)setFavorited:(BOOL)favorited {
    _favorited = favorited;
    [self updateFavoriteButton];
}

- (void)refreshHoverState {
    BOOL inside = NO;
    NSWindow *window = self.window;
    if (window) {
        NSPoint mouseInWindow = [window mouseLocationOutsideOfEventStream];
        NSPoint mouseInView = [self convertPoint:mouseInWindow fromView:nil];
        inside = NSPointInRect(mouseInView, self.bounds);
    }
    _hovered = inside;
    [self updateFavoriteButton];
}

- (void)updateFavoriteButton {
    BOOL visible = self.favorited || _hovered;
    self.favoriteButton.hidden = !visible;
    self.favoriteButton.image = [NSImage imageWithSystemSymbolName:(self.favorited ? @"star.fill" : @"star")
                                         accessibilityDescription:nil];
    self.favoriteButton.toolTip = self.favorited ? @"已收藏，点击取消收藏" : @"收藏";
}

- (void)programLinkClicked:(id)sender {
    if (self.onProgramClick) self.onProgramClick();
}

- (void)favoriteButtonClicked:(id)sender {
    if (self.onFavoriteClick) self.onFavoriteClick();
}

@end

@implementation TVFavoriteCellView {
    NSLayoutConstraint *_deleteWidthConstraint;
    BOOL _hovered;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _nameLabel = [NSTextField labelWithString:@""];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_nameLabel];

        _deleteButton = [NSButton buttonWithTitle:@"" target:self action:@selector(deleteButtonClicked:)];
        _deleteButton.bordered = NO;
        _deleteButton.imagePosition = NSImageOnly;
        _deleteButton.image = [NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:@"删除"];
        _deleteButton.contentTintColor = [NSColor systemRedColor];
        _deleteButton.toolTip = @"删除";
        _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
        _deleteButton.hidden = YES;
        [self addSubview:_deleteButton];
        _deleteWidthConstraint = [_deleteButton.widthAnchor constraintEqualToConstant:0];

        [NSLayoutConstraint activateConstraints:@[
            [_nameLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_nameLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_deleteButton.leadingAnchor constant:-6],
            [_deleteButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
            [_deleteButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_deleteButton.heightAnchor constraintEqualToConstant:18],
            _deleteWidthConstraint,
        ]];
        [_nameLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_deleteButton setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                        options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect)
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseEntered:(NSEvent *)event {
    _hovered = YES;
    self.deleteButton.hidden = NO;
    _deleteWidthConstraint.constant = 18;
}

- (void)mouseExited:(NSEvent *)event {
    _hovered = NO;
    self.deleteButton.hidden = YES;
    _deleteWidthConstraint.constant = 0;
}

- (void)deleteButtonClicked:(id)sender {
    if (self.onDelete) self.onDelete();
}

@end