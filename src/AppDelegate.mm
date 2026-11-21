#import "AppDelegate.h"
#import "MainViewController.h"

// 主窗体尺寸/位置持久化键
static NSString * const kTVBoxMainWindowFrameKey = @"TVBoxMainWindowFrame";

@implementation AppDelegate

// 首次启动时按当前显示器宽窄计算窗口内容区大小（适配横屏/竖屏（旋转）方向，带上下限）
- (NSSize)initialMainWindowContentSize {
    NSScreen *screen = [NSScreen mainScreen];
    NSRect visible = screen ? screen.visibleFrame : NSMakeRect(0, 0, 1280, 800);
    CGFloat vw = visible.size.width;
    CGFloat vh = visible.size.height;

    // 主显示器为竖屏（旋转 90°/270°）时，可用高度大于宽度
    BOOL isPortrait = vh > vw;

    CGFloat width, height;
    if (isPortrait) {
        // 竖屏：宽度以较窄的屏幕宽度为基准，高度相应缩短，避免窗体超出屏幕
        width = round(vw * 0.85);
        height = round(vh * 0.55);
    } else {
        // 横屏：保持较窄的宽度占比
        width = round(vw * 0.58);
        height = round(vh * 0.76);
    }

    // 上下限，且确保不超过屏幕可用尺寸（旋转后窄边也不会溢出）
    width = MIN(width, MIN(vw, 1000));
    width = MAX(width, MIN(vw, 480));

    height = MIN(height, MIN(vh, 820));
    height = MAX(height, MIN(vh, 340));

    return NSMakeSize(width, height);
}

// 读取上次启动保存的主窗体 frame；若不存在或已不在任何可见屏幕内，返回 NSZeroRect
- (NSRect)restoredMainWindowFrame {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kTVBoxMainWindowFrameKey];
    if (saved.length > 0) {
        NSRect frame = NSRectFromString(saved);
        if (!NSIsEmptyRect(frame)) {
            for (NSScreen *screen in [NSScreen screens]) {
                if (NSIntersectsRect(frame, screen.visibleFrame)) {
                    return frame;
                }
            }
        }
    }
    return NSZeroRect;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // 设置应用图标（Dock / 切换器），使用 appImages/T.svg 生成的 AppIcon.icns
    NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
    if (iconPath) {
        NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
        if (icon) {
            [NSApp setApplicationIconImage:icon];
        }
    }

    [self buildMenu];

    NSRect restoredFrame = [self restoredMainWindowFrame];
    BOOL firstLaunch = NSIsEmptyRect(restoredFrame);

    // 首次启动：按当前显示器宽窄计算窗口大小；否则沿用上次启动保存的大小
    NSSize contentSize = firstLaunch ? [self initialMainWindowContentSize] : NSMakeSize(1000, 700);

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, contentSize.width, contentSize.height)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"TVBoxB";

    // 主窗体可自由放大缩小：不设最大尺寸，最小尺寸放宽，方便用户按需缩小
    window.contentMinSize = NSMakeSize(40, 30);

    if (firstLaunch) {
        [window center];
    } else {
        [window setFrame:restoredFrame display:NO];
    }

    MainViewController *mainVC = [[MainViewController alloc] init];
    window.contentViewController = mainVC;

    [window makeKeyAndOrderFront:nil];
    self.window = window;

    [NSApp activateIgnoringOtherApps:YES];
}

// 退出前保存主窗体 frame，供下次启动恢复
- (void)applicationWillTerminate:(NSNotification *)notification {
    NSWindow *window = self.window;
    if (window) {
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(window.frame) forKey:kTVBoxMainWindowFrameKey];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItem:[self menuItemWithTitle:@"关于 TVBoxB" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@"" symbolName:@"info.circle"]];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItem:[self menuItemWithTitle:@"退出 TVBoxB" action:@selector(terminate:) keyEquivalent:@"q" symbolName:@"power"]];
    appItem.submenu = appMenu;

    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"文件"];
    [fileMenu addItem:[self menuItemWithTitle:@"关闭窗口" action:@selector(performClose:) keyEquivalent:@"w" symbolName:@"xmark"]];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItem:[self menuItemWithTitle:@"重新加载配置" action:@selector(reloadConfig:) keyEquivalent:@"r" symbolName:@"arrow.clockwise"]];
    fileItem.submenu = fileMenu;

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"编辑"];
    [editMenu addItem:[self menuItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z" symbolName:@"arrow.uturn.backward"]];
    [editMenu addItem:[self menuItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"Z" symbolName:@"arrow.uturn.forward"]];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItem:[self menuItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x" symbolName:@"scissors"]];
    [editMenu addItem:[self menuItemWithTitle:@"拷贝" action:@selector(copy:) keyEquivalent:@"c" symbolName:@"doc.on.doc"]];
    [editMenu addItem:[self menuItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v" symbolName:@"doc.on.clipboard"]];
    [editMenu addItem:[self menuItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a" symbolName:@"checkmark.circle"]];
    editItem.submenu = editMenu;

    NSApp.mainMenu = mainMenu;
}

- (NSMenuItem *)menuItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key symbolName:(NSString *)symbolName {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    if (symbolName) {
        item.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:title];
    }
    return item;
}

- (void)reloadConfig:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TVBoxReloadConfig" object:nil];
}

@end