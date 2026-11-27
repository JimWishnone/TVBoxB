#import "MainViewController.h"
#import "ConfigManager.h"
#import "PlayerViewController.h"
#import "TVBoxVLCPlayerView.h"
#import "TVImageLoader.h"
#import "TVLiveSourceParser.h"
#import "TVTableCellViews.h"
#import "TVVideoCardViews.h"

NS_ASSUME_NONNULL_BEGIN

// —— 共享常量 ——
static NSString *const kVODItemIdentifier = @"VODItemIdentifier";
static NSString *const kTVBoxHistoryKey = @"TVBoxHistory";
static NSString *const kTVBoxSaveHistoryKey = @"TVBoxSaveHistory";
static NSString *const kTVBoxHistoryLimitKey = @"TVBoxHistoryLimit";
static NSString *const kTVBoxFavoritesKey = @"TVBoxFavorites";
static NSString *const kTVBoxSearchKeywordsKey = @"TVBoxSearchKeywords";
static NSString *const kTVBoxFavoriteDragType = @"com.TVBox.favorite.drag";
static NSString *const kTVBoxUseVLCKey = @"TVBoxUseVLCPlayback";
static const NSUInteger kTVBoxHistoryLimit = 30;
static const NSUInteger kTVBoxSearchKeywordsLimit = 12;

// —— 共享工具函数 ——
static inline NSString *TVFirstCharacter(NSString *name) {
    if (name.length == 0) return @"?";
    NSRange range = [name rangeOfComposedCharacterSequenceAtIndex:0];
    return [name substringWithRange:range];
}

static inline NSImage *TVLetterIcon(NSString *name) {
    NSString *letter = TVFirstCharacter(name);
    NSSize size = NSMakeSize(24, 24);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, size.width, size.height)];
    [[NSColor controlAccentColor] setFill];
    [circle fill];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
    NSSize letterSize = [letter sizeWithAttributes:attrs];
    [letter drawAtPoint:NSMakePoint((size.width - letterSize.width) / 2.0,
                                    (size.height - letterSize.height) / 2.0)
         withAttributes:attrs];
    [image unlockFocus];
    return image;
}

static inline NSLayoutConstraint *TVSoftMinWidthConstraint(NSLayoutDimension *dimension, CGFloat minimum) {
    NSLayoutConstraint *constraint = [dimension constraintGreaterThanOrEqualToConstant:minimum];
    constraint.priority = NSLayoutPriorityDefaultHigh;
    return constraint;
}

// 降低视图水平方向的内容压缩抗性。fittingSize 以 NSLayoutPriorityFittingSizeCompression(50)
// 作为约束求解优先级，因此压缩抗性必须低于该值，控件的固有宽度才不会锁死窗口最小宽度。
static inline void TVAllowHorizontalCompression(NSView *view) {
    [view setContentCompressionResistancePriority:(NSLayoutPriorityFittingSizeCompression - 1)
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
}

// 计算两个字符串的编辑距离（Levenshtein），用于搜索结果相似度排序
static inline NSUInteger TVLevenshteinDistance(NSString *a, NSString *b) {
    NSUInteger lenA = a.length;
    NSUInteger lenB = b.length;
    if (lenA == 0) return lenB;
    if (lenB == 0) return lenA;

    NSUInteger *prev = (NSUInteger *)calloc(lenB + 1, sizeof(NSUInteger));
    NSUInteger *curr = (NSUInteger *)calloc(lenB + 1, sizeof(NSUInteger));
    for (NSUInteger j = 0; j <= lenB; j++) prev[j] = j;

    for (NSUInteger i = 1; i <= lenA; i++) {
        curr[0] = i;
        unichar ca = [a characterAtIndex:i - 1];
        for (NSUInteger j = 1; j <= lenB; j++) {
            unichar cb = [b characterAtIndex:j - 1];
            NSUInteger cost = (ca == cb) ? 0 : 1;
            NSUInteger deletion = prev[j] + 1;
            NSUInteger insertion = curr[j - 1] + 1;
            NSUInteger substitution = prev[j - 1] + cost;
            curr[j] = MIN(MIN(deletion, insertion), substitution);
        }
        NSUInteger *tmp = prev;
        prev = curr;
        curr = tmp;
    }
    NSUInteger result = prev[lenB];
    free(prev);
    free(curr);
    return result;
}

// —— 类扩展（私有属性 + 协议） ——
@interface MainViewController () <NSTableViewDataSource, NSTableViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, NSSearchFieldDelegate>

@property (nonatomic, strong) ConfigManager *config;

@property (nonatomic, strong) NSTableView *sidebar;
@property (nonatomic, strong) NSArray<NSString *> *sidebarItems;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) NSView *dataSourcesView;
@property (nonatomic, strong) NSView *searchView;
@property (nonatomic, strong) NSView *vodView;
@property (nonatomic, strong) NSView *liveView;
@property (nonatomic, strong) NSView *favoritesView;
@property (nonatomic, strong) NSView *historyView;
@property (nonatomic, strong) NSView *settingsView;
@property (nonatomic, strong) NSView *aboutView;
@property (nonatomic, strong) NSArray<NSView *> *contentViews;
@property (nonatomic, strong) NSArray<NSArray<NSLayoutConstraint *> *> *contentViewPinConstraints;

@property (nonatomic, strong) NSTableView *sourcesTable;
@property (nonatomic, strong) NSArray<NSDictionary *> *sourceRows;
@property (nonatomic, strong) NSMutableSet<NSString *> *unavailableSourceURLs;
@property (nonatomic, strong) NSWindow *checkingPanel;
@property (nonatomic, assign) NSInteger availabilityCheckGeneration;
@property (nonatomic, strong) NSWindow *vlcCheckPanel;
@property (nonatomic, strong) NSTextField *vlcCheckStatusLabel;

@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSCollectionView *searchCollectionView;
@property (nonatomic, strong) NSArray<TVVideo *> *searchResults;
@property (nonatomic, strong) NSTimer *searchTimer;
@property (nonatomic, assign) NSInteger searchGeneration;
@property (nonatomic, strong) NSMutableArray<NSString *> *searchKeywords;
@property (nonatomic, strong) NSScrollView *searchKeywordsScroll;
@property (nonatomic, strong) NSView *searchKeywordsBar;
@property (nonatomic, strong) NSLayoutConstraint *searchKeywordsHeightConstraint;

@property (nonatomic, strong) NSPopUpButton *sitePopup;
@property (nonatomic, strong) NSSearchField *vodSearchField;
@property (nonatomic, strong) NSScrollView *categoryScroll;
@property (nonatomic, strong) NSView *categoryContentView;
@property (nonatomic, strong) NSCollectionView *vodCollectionView;
@property (nonatomic, strong) NSScrollView *vodScrollView;
@property (nonatomic, strong) NSArray<TVCategory *> *categories;
@property (nonatomic, strong) NSArray<TVVideo *> *videos;
@property (nonatomic, assign) NSInteger selectedCategoryId;
@property (nonatomic, assign) NSInteger vodPage;
@property (nonatomic, assign) BOOL vodHasMore;
@property (nonatomic, assign) BOOL vodLoadingMore;
@property (nonatomic, copy) NSString *vodSearchKeyword;

@property (nonatomic, strong) NSPopUpButton *liveSourcePopup;
@property (nonatomic, strong) NSPopUpButton *liveGroupPopup;
@property (nonatomic, strong) NSSearchField *liveSearchField;
@property (nonatomic, strong) NSTableView *liveTable;
@property (nonatomic, strong) NSArray<TVLiveChannel *> *liveChannels;
@property (nonatomic, strong) NSArray<TVLiveChannel *> *displayedLiveChannels;
@property (nonatomic, copy) NSSortDescriptor *liveSortDescriptor;
@property (nonatomic, assign) NSInteger liveEPGGeneration;

@property (nonatomic, strong) NSTextField *vodConfigURLField;
@property (nonatomic, strong) NSTextField *liveConfigURLField;
@property (nonatomic, strong) NSTextField *settingsProgressLabel;
@property (nonatomic, strong) NSTextField *vodValidationResultLabel;
@property (nonatomic, strong) NSTextField *liveValidationResultLabel;
@property (nonatomic, strong) NSButton *historySaveSwitch;
@property (nonatomic, strong) NSTextField *historyLimitField;
@property (nonatomic, strong) NSButton *vlcPlaybackSwitch;

@property (nonatomic, strong) NSTableView *historyTable;
@property (nonatomic, strong) NSMutableArray<TVHistoryItem *> *historyItems;
@property (nonatomic, strong) TVHistoryItem *currentHistoryItem;

@property (nonatomic, strong) NSTableView *favoritesTable;
@property (nonatomic, strong) NSMutableArray<TVFavoriteItem *> *favoritesItems;

@property (nonatomic, strong) NSWindow *playerWindow;
@property (nonatomic, strong) NSTextField *statusLabel;

// 节目单模态窗口（直播频道点击“节目单”链接后弹出）
@property (nonatomic, strong) NSWindow *programModalWindow;
@property (nonatomic, strong) NSTableView *programTable;
@property (nonatomic, strong) NSArray<TVLiveProgram *> *programModalItems;

// 视频详情模态窗口（点播列表点击后展示介绍信息与可播放列表）
@property (nonatomic, strong) NSWindow *detailModalWindow;
@property (nonatomic, strong) NSPopUpButton *detailModalLinePopup;
@property (nonatomic, strong) NSPopUpButton *detailModalEpisodePopup;
@property (nonatomic, strong) NSButton *detailModalFavoriteButton;
@property (nonatomic, strong) TVVideo *detailModalVideo;
@property (nonatomic, strong) TVSite *detailModalSite;

// 主文件提供，供各 Category 调用
- (void)setStatus:(NSString *)text;

@end

// —— Category 接口声明 ——

@interface MainViewController (UI)
- (void)buildUI;
- (void)buildSidebar;
- (NSView *)buildDataSourcesView;
- (NSView *)buildSearchView;
- (NSView *)buildVODView;
- (NSView *)buildFavoritesView;
- (NSView *)buildHistoryView;
- (NSImage *)makeQRCodeImageFromString:(NSString *)string size:(CGFloat)size;
- (NSCollectionView *)makeCollectionView;
- (NSScrollView *)makeScrollViewForCollectionView:(NSCollectionView *)collectionView;
- (void)showContentViewAtIndex:(NSInteger)index;
- (NSImage *)sidebarIconForRow:(NSInteger)row;
@end

@interface MainViewController (UILive)
- (NSView *)buildLiveView;
@end

@interface MainViewController (UISettings)
- (NSView *)buildSettingsView;
@end

@interface MainViewController (UIAbout)
- (NSView *)buildAboutView;
@end

@interface MainViewController (DataSources)
- (void)handleReloadConfig:(NSNotification *)notification;
- (void)reloadConfig;
- (NSArray<TVSite *> *)availableVodSites;
- (NSArray<TVLiveSource *> *)availableLiveSources;
- (BOOL)isSourceAvailable:(NSString *)urlString;
- (void)rebuildSites;
- (void)rebuildLiveSources;
- (void)rebuildDataSources;
- (void)checkDataSourcesAvailabilityInteractive:(BOOL)interactive;
- (void)checkDataSourceURL:(NSString *)urlString completion:(void (^)(NSString *status))completion;
- (void)updateSourceRowStatus:(NSString *)status forURL:(NSString *)urlString generation:(NSInteger)generation;
- (void)sortUnavailableSourcesToEnd;
- (void)showCheckingPanel;
- (void)hideCheckingPanel;
@end

@interface MainViewController (VOD)
- (void)siteChanged:(NSPopUpButton *)sender;
- (void)loadVODList;
- (void)loadVODPage:(NSInteger)page reset:(BOOL)reset;
- (void)fillMissingPostersForVideos:(NSArray<TVVideo *> *)videos site:(TVSite *)site;
- (void)loadNextVODPage;
- (void)vodScrollDidScroll:(NSNotification *)note;
- (void)scheduleVODPaginationCheck;
- (void)vodSearchAction:(id)sender;
- (void)performVODSearch;
- (void)openVideo:(TVVideo *)video site:(TVSite *)site;
- (void)showDetailModalForVideo:(TVVideo *)detail site:(TVSite *)site;
- (void)detailModalLineChanged:(NSPopUpButton *)sender;
- (void)detailModalPlayAction:(id)sender;
- (void)detailModalCancelAction:(id)sender;
- (void)beginPlaybackFromModal;
- (NSString *)modalMetaTextForVideo:(TVVideo *)video;
- (NSAttributedString *)modalDetailTextForVideo:(TVVideo *)video;
- (void)loadPosterImage:(NSString *)urlString into:(NSImageView *)imageView;
- (NSAttributedString *)modalHTMLAttributedString:(NSString *)html;
@end

@interface MainViewController (Search)
- (void)controlTextDidChange:(NSNotification *)notification;
- (void)scheduleSearch;
- (void)searchTimerFired:(NSTimer *)timer;
- (void)searchAction:(id)sender;
- (void)loadSearchKeywords;
- (void)rememberSearchKeyword:(NSString *)keyword;
- (void)rebuildSearchKeywordsBar;
- (void)searchKeywordChipClicked:(id)sender;
- (void)searchKeywordDeleteClicked:(id)sender;
- (void)performSearch:(id)sender;
- (double)searchSimilarityScore:(NSString *)keyword video:(TVVideo *)video;
- (double)similarityBetweenKeyword:(NSString *)keyword andTitle:(NSString *)title;
- (NSArray<TVVideo *> *)videosFromList:(id)list;
- (TVSite *)selectedSiteForPopup:(NSPopUpButton *)popup;
- (void)rebuildCategoryButtons;
- (NSButton *)categoryButtonWithTitle:(NSString *)title typeId:(NSInteger)typeId;
- (void)categoryButtonClicked:(NSButton *)sender;
- (void)updateCategoryButtonStates;
@end

@interface MainViewController (Live)
- (void)liveSourceChanged:(id)sender;
- (void)liveGroupChanged:(id)sender;
- (void)reloadLiveAction:(id)sender;
- (void)loadMergedLiveChannels;
- (NSString *)currentLiveEPGURL;
- (void)loadProgramSchedulesForChannels:(NSArray<TVLiveChannel *> *)channels;
- (void)showProgramScheduleForChannel:(TVLiveChannel *)channel;
- (void)programModalCloseAction:(id)sender;
- (void)liveSearchChanged:(id)sender;
- (void)applyLiveFilterAndSort;
- (void)rebuildLiveGroupPopup;
- (void)sizeLiveTableColumnsToFit;
- (void)bumpLiveColumnWidth:(NSMutableDictionary<NSString *, NSNumber *> *)maxWidths
                        key:(NSString *)key
                       text:(NSString *)text
                      attrs:(NSDictionary *)attrs;
- (NSString *)liveLogoForChannel:(TVLiveChannel *)channel source:(TVLiveSource *)source;
- (NSArray<TVLiveChannel *> *)mergeLiveChannels:(NSArray<NSDictionary *> *)collected;
- (void)sourceRowDoubleClicked:(id)sender;
- (void)liveTableScrolled:(NSNotification *)note;
- (void)refreshLiveHoverStates;
- (void)liveRowDoubleClicked:(id)sender;
@end

@interface MainViewController (Settings)
- (void)presentPlayerWithTitle:(NSString *)title block:(void (^)(PlayerViewController *player))block;
- (void)playerWindowWillClose:(NSNotification *)note;
- (void)reloadConfigAction:(id)sender;
- (void)refreshDataSourcesAction:(id)sender;
- (void)loadConfigURLRows;
- (void)loadHistorySettings;
- (void)historySaveSwitchChanged:(id)sender;
- (void)controlTextDidEndEditing:(NSNotification *)notification;
- (BOOL)saveHistoryEnabled;
- (NSUInteger)historyLimit;
- (void)loadVLCSetting;
- (void)vlcPlaybackSwitchChanged:(id)sender;
- (void)showVLCCheckPanel;
- (void)hideVLCCheckPanel;
- (void)saveConfigURLAction:(id)sender;
- (void)setSettingsProgress:(NSString *)text;
- (void)showValidationProgress:(NSString *)text forLabel:(NSTextField *)label;
- (void)showValidationSuccess:(NSString *)text forLabel:(NSTextField *)label;
- (void)showValidationFailure:(NSString *)text forLabel:(NSTextField *)label;
- (void)validateAndSaveLiveURL:(NSString *)liveURL;
- (void)validateLiveURLAndSave:(NSString *)liveURL;
- (void)validateVODURLAction:(id)sender;
- (void)validateLiveURLAction:(id)sender;
- (void)showErrorAlertWithMessage:(NSString *)message;
- (void)showInfoAlertWithMessage:(NSString *)message;
- (void)presentLiveSourcePicker:(NSArray<TVLiveSource *> *)lives completion:(void (^)(TVLiveSource * _Nullable chosenSource))completion;
@end

@interface MainViewController (Library)
- (TVHistoryItem *)historyItemForVideo:(TVVideo *)video site:(TVSite *)site;
- (TVHistoryItem *)historyItemForLiveChannel:(TVLiveChannel *)channel;
- (void)finalizeCurrentHistory;
- (void)insertHistoryItem:(TVHistoryItem *)item;
- (void)loadHistory;
- (void)saveHistory;
- (void)clearHistoryAction:(id)sender;
- (TVFavoriteItem *)favoriteItemForVideo:(TVVideo *)video site:(TVSite *)site;
- (TVFavoriteItem *)favoriteItemForLiveChannel:(TVLiveChannel *)channel;
- (NSInteger)favoriteIndexForVideo:(TVVideo *)video site:(TVSite *)site;
- (NSInteger)favoriteIndexForLiveChannel:(TVLiveChannel *)channel;
- (BOOL)isVideoFavorited:(TVVideo *)video site:(TVSite *)site;
- (void)toggleLiveChannelFavorite:(TVLiveChannel *)channel;
- (void)detailModalFavoriteAction:(id)sender;
- (void)updateDetailFavoriteButtonState;
- (void)loadFavorites;
- (void)saveFavorites;
- (void)favoriteRowDoubleClicked:(id)sender;
- (void)removeFavoriteAtIndex:(NSInteger)index;
- (TVLiveChannel *)liveChannelFromPayload:(NSDictionary *)payload fallbackTitle:(NSString *)title;
- (void)resumeFavoriteItem:(TVFavoriteItem *)item;
- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row;
- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation;
- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation;
- (void)historyRowDoubleClicked:(id)sender;
- (void)resumeHistoryItem:(TVHistoryItem *)item;
- (TVLiveChannel *)liveChannelFromHistoryItem:(TVHistoryItem *)item;
- (NSString *)formatPlaybackTime:(NSTimeInterval)seconds;
- (NSString *)formatHistoryDate:(NSDate *)date;
@end

@interface MainViewController (Tables)
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
- (void)loadLiveLogoForChannel:(TVLiveChannel *)channel intoCell:(TVLiveIconCell *)cell;
- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section;
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths;
@end

NS_ASSUME_NONNULL_END