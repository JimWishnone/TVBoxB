#import "MainViewController+Private.h"

@implementation MainViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1080, 700)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.config = [ConfigManager sharedManager];
    self.videos = @[];
    self.searchResults = @[];
    self.liveChannels = @[];
    self.displayedLiveChannels = @[];
    self.sourceRows = @[];
    self.unavailableSourceURLs = [NSMutableSet set];
    self.selectedCategoryId = 0;
    self.historyItems = [NSMutableArray array];
    self.favoritesItems = [NSMutableArray array];

    [self buildUI];
    [self loadHistory];
    [self loadFavorites];
    [self loadSearchKeywords];
    [self rebuildSearchKeywordsBar];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleReloadConfig:)
                                                 name:@"TVBoxReloadConfig"
                                               object:nil];
    [self reloadConfig];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 工具

- (void)setStatus:(NSString *)text {
    self.statusLabel.stringValue = text ?: @"";
}

#pragma mark - 关于（邮箱操作）

- (void)copySupportEmailAction:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:@"ibmos_2@163.com" forType:NSPasteboardTypeString];
    [self setStatus:@"邮箱地址 ibmos_2@163.com 已复制到剪贴板"];
}

- (void)sendSupportEmailAction:(id)sender {
    NSURL *url = [NSURL URLWithString:@"mailto:ibmos_2@163.com"];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

@end