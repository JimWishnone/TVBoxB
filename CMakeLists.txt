cmake_minimum_required(VERSION 3.20)
project(TVBoxB)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum deployment target")

add_compile_options(-fobjc-arc)

set(VLC_VENDOR_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/vlc")
if(EXISTS "${VLC_VENDOR_DIR}/include" AND EXISTS "${VLC_VENDOR_DIR}/lib")
    set(VLC_INCLUDE_DIR "${VLC_VENDOR_DIR}/include")
    set(VLC_LIB_DIR     "${VLC_VENDOR_DIR}/lib")
    set(VLC_PLUGINS_DIR "${VLC_VENDOR_DIR}/plugins")
    set(VLC_DATA_DIR    "${VLC_VENDOR_DIR}/share")
    message(STATUS "Using vendored VLC runtime from third_party/vlc")
else()
    set(VLC_APP_PATH "/Applications/VLC.app")
    set(VLC_INCLUDE_DIR "${VLC_APP_PATH}/Contents/MacOS/include")
    set(VLC_LIB_DIR     "${VLC_APP_PATH}/Contents/MacOS/lib")
    set(VLC_PLUGINS_DIR "${VLC_APP_PATH}/Contents/MacOS/plugins")
    set(VLC_DATA_DIR    "${VLC_APP_PATH}/Contents/MacOS/share")
    if(NOT EXISTS "${VLC_APP_PATH}")
        message(FATAL_ERROR "VLC runtime not found. Either vendor it into third_party/vlc/ or install VLC.app to /Applications/")
    endif()
    message(STATUS "Using system VLC from /Applications/VLC.app (vendored third_party/vlc not found)")
endif()

add_executable(TVBoxB
    src/main.mm
    src/AppDelegate.mm
    src/Models.mm
    src/ConfigManager.mm
    src/MainViewController.mm
    src/PlayerViewController.mm
    src/TVBoxVLCPlayerView.mm
    src/TVBoxVLCPlayerView.h
    src/TVImageLoader.mm
    src/TVImageLoader.h
    src/TVLiveSourceParser.mm
    src/TVLiveSourceParser.h
)

set(MACOSX_BUNDLE_ICON_FILE "AppIcon.icns")
set_target_properties(TVBoxB PROPERTIES
    MACOSX_BUNDLE_ICON_FILE "${MACOSX_BUNDLE_ICON_FILE}"
)
target_sources(TVBoxB PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/appImages/AppIcon.icns")
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/appImages/AppIcon.icns" PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources"
)

target_include_directories(TVBoxB PRIVATE "${VLC_INCLUDE_DIR}")

target_link_libraries(TVBoxB
    "-framework Cocoa"
    "-framework AVFoundation"
    "-framework AVKit"
    "-framework CoreMedia"
    "-framework QuartzCore"
    "-framework CoreImage"
    "-framework AppKit"
    "${VLC_LIB_DIR}/libvlc.5.dylib"
    "${VLC_LIB_DIR}/libvlccore.9.dylib"
)

set(VLC_BUNDLE_DIR "$<TARGET_BUNDLE_CONTENT_DIR:TVBoxB>/Frameworks/vlc")
set_target_properties(TVBoxB PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.tvboxb.player"
    MACOSX_BUNDLE_BUNDLE_NAME "TVBoxB"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.2.1"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.2.1"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    BUILD_RPATH "@loader_path/../Frameworks/vlc/lib"
    INSTALL_RPATH "@loader_path/../Frameworks/vlc/lib"
    MACOSX_RPATH ON
)

add_custom_command(TARGET TVBoxB POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${VLC_BUNDLE_DIR}/lib"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${VLC_LIB_DIR}/libvlc.5.dylib"
        "${VLC_BUNDLE_DIR}/lib/"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${VLC_LIB_DIR}/libvlccore.9.dylib"
        "${VLC_BUNDLE_DIR}/lib/"
    COMMAND ${CMAKE_COMMAND} -E create_symlink "libvlc.5.dylib" "${VLC_BUNDLE_DIR}/lib/libvlc.dylib"
    COMMAND ${CMAKE_COMMAND} -E create_symlink "libvlccore.9.dylib" "${VLC_BUNDLE_DIR}/lib/libvlccore.dylib"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${VLC_PLUGINS_DIR}" "${VLC_BUNDLE_DIR}/plugins"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${VLC_DATA_DIR}" "${VLC_BUNDLE_DIR}/share"
    COMMENT "Integrating VLC lib/plugins/share into TVBoxB.app bundle"
)