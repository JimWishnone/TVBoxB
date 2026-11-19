#import "AppDelegate.h"
#import "MainViewController.h"

@implementation AppDelegate

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

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1080, 700)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"TVBoxB";
    [window center];

    MainViewController *mainVC = [[MainViewController alloc] init];
    window.contentViewController = mainVC;

    [window makeKeyAndOrderFront:nil];
    self.window = window;

    [NSApp activateIgnoringOtherApps:YES];
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