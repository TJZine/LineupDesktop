cmake_minimum_required(VERSION 3.20)
project(lineup_authenticated_reference LANGUAGES CXX OBJCXX)

get_filename_component(REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT APPLE OR NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
  message(FATAL_ERROR "This runner currently requires macOS arm64")
endif()
foreach(required LINEUP_MPV_RUNTIME FLUTTER_ROOT)
  if(NOT IS_DIRECTORY "${${required}}")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
set(FLUTTER_FRAMEWORK "${FLUTTER_ROOT}/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64")
if(NOT EXISTS "${FLUTTER_FRAMEWORK}/FlutterMacOS.framework/FlutterMacOS")
  message(FATAL_ERROR "Prepared pinned FlutterMacOS XCFramework is required")
endif()

add_executable(authenticated-reference
  authenticated_reference.mm
  "${REPO_ROOT}/macos/Runner/NativePlayer/LineupNativePlayer.mm"
  "${REPO_ROOT}/macos/Runner/NativePlayer/FoundationValueConversion.mm"
  "${REPO_ROOT}/macos/Runner/NativePlayer/VideoGeometry.mm"
  "${REPO_ROOT}/native/player_core/player_core.cpp"
  "${REPO_ROOT}/native/player_core/libmpv_operations.cpp"
  "${REPO_ROOT}/native/player_core/platform_arguments.cpp"
  "${REPO_ROOT}/native/player_core/track_list_encoder.cpp")
target_compile_features(authenticated-reference PRIVATE cxx_std_17)
set_target_properties(authenticated-reference PROPERTIES OBJCXX_STANDARD 17
  BUILD_RPATH "${LINEUP_MPV_RUNTIME}/lib;${FLUTTER_FRAMEWORK}")
target_include_directories(authenticated-reference PRIVATE
  "${REPO_ROOT}/native" "${REPO_ROOT}/macos/Runner/NativePlayer")
target_include_directories(authenticated-reference SYSTEM PRIVATE "${LINEUP_MPV_RUNTIME}/include")
target_compile_options(authenticated-reference PRIVATE
  "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>" "-F${FLUTTER_FRAMEWORK}")
target_link_options(authenticated-reference PRIVATE "-F${FLUTTER_FRAMEWORK}")
target_link_libraries(authenticated-reference PRIVATE
  "${LINEUP_MPV_RUNTIME}/lib/libmpv.2.dylib"
  "-framework FlutterMacOS" "-framework Cocoa" "-framework QuartzCore")
target_compile_definitions(authenticated-reference PRIVATE
  LINEUP_REFERENCE_RUNTIME="${LINEUP_MPV_RUNTIME}/lib"
  LINEUP_REFERENCE_FLUTTER="${FLUTTER_FRAMEWORK}/FlutterMacOS.framework")
