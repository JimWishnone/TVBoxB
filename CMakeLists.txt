cmake_minimum_required(VERSION 3.20)
project(TVBoxB)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 最低运行版本 macOS 15
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum deployment target")

# 使用 Objective-C++ 编写 macOS 原生界面，开启 ARC
add_compile_options(-fobjc-arc)

add_executable(TVBoxB
    src/main.mm
    src/AppDelegate.mm
    src/Models.mm
    src/ConfigManager.mm
    src/MainViewController.mm
    src/PlayerViewController.mm
        src/Models.h
        src/ConfigManager.h
        src/PlayerViewController.h
)

# 应用图标（由 appImages/T.svg 生成）
set(MACOSX_BUNDLE_ICON_FILE "AppIcon.icns")
set_target_properties(TVBoxB PROPERTIES
    MACOSX_BUNDLE_ICON_FILE "${MACOSX_BUNDLE_ICON_FILE}"
)
target_sources(TVBoxB PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/appImages/AppIcon.icns")
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/appImages/AppIcon.icns" PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources"
)

target_link_libraries(TVBoxB
    "-framework Cocoa"
    "-framework AVFoundation"
    "-framework AVKit"
    "-framework CoreMedia"
    "-framework QuartzCore"
    "-framework CoreImage"
)

set_target_properties(TVBoxB PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.tvboxb.player"
    MACOSX_BUNDLE_BUNDLE_NAME "TVBoxB"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.1.1"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.1"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
)