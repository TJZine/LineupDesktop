cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "native_player.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

if(NOT DEFINED ENV{LINEUP_MPV_ROOT})
  message(FATAL_ERROR
    "LINEUP_MPV_ROOT must point to the prepared libmpv production build. "
    "See docs/DEVELOPMENT.md.")
endif()
file(TO_CMAKE_PATH "$ENV{LINEUP_MPV_ROOT}" LINEUP_MPV_ROOT)
unset(LINEUP_MPV_INCLUDE_DIR CACHE)
unset(LINEUP_MPV_LIBRARY CACHE)
unset(LINEUP_MPV_DLL CACHE)
set(LINEUP_MPV_INCLUDE_DIR "${LINEUP_MPV_ROOT}/include")
set(LINEUP_MPV_LIBRARY "${LINEUP_MPV_ROOT}/libmpv.lib")
set(LINEUP_MPV_DLL "${LINEUP_MPV_ROOT}/libmpv-2.dll")
foreach(LINEUP_MPV_REQUIRED_FILE
    "${LINEUP_MPV_INCLUDE_DIR}/mpv/client.h"
    "${LINEUP_MPV_LIBRARY}"
    "${LINEUP_MPV_DLL}")
  if(NOT EXISTS "${LINEUP_MPV_REQUIRED_FILE}")
    message(FATAL_ERROR
      "LINEUP_MPV_ROOT is missing ${LINEUP_MPV_REQUIRED_FILE}.")
  endif()
endforeach()
set(LINEUP_MPV_PROVENANCE "${LINEUP_MPV_ROOT}/lineup-mpv-provenance.cmake")
if(NOT EXISTS "${LINEUP_MPV_PROVENANCE}")
  message(FATAL_ERROR
    "LINEUP_MPV_ROOT must be prepared by tool/windows/prepare-mpv.ps1.")
endif()
include("${LINEUP_MPV_PROVENANCE}")
if(NOT LINEUP_MPV_DISTRIBUTION STREQUAL "production" OR
    NOT LINEUP_MPV_LICENSE STREQUAL "LGPL-2.1-or-later")
  message(FATAL_ERROR "LINEUP_MPV_ROOT is not the selected production runtime.")
endif()
if(NOT LINEUP_MPV_ASSET_SHA256 STREQUAL
    "13723530C3A719577A27EA19E0127175CE6A047071F8D988ADC1B0DD400B3D18")
  message(FATAL_ERROR "LINEUP_MPV_ROOT is not the pinned mpv production asset.")
endif()
function(verify_lineup_mpv_file PATH EXPECTED_HASH)
  file(SHA256 "${PATH}" ACTUAL_HASH)
  string(TOUPPER "${ACTUAL_HASH}" ACTUAL_HASH)
  string(TOUPPER "${EXPECTED_HASH}" EXPECTED_HASH)
  if("${EXPECTED_HASH}" STREQUAL "" OR
      NOT "${ACTUAL_HASH}" STREQUAL "${EXPECTED_HASH}")
    message(FATAL_ERROR
      "Verified mpv provenance does not match ${PATH}: expected "
      "${EXPECTED_HASH}, found ${ACTUAL_HASH}.")
  endif()
endfunction()
verify_lineup_mpv_file("${LINEUP_MPV_INCLUDE_DIR}/mpv/client.h"
  "1ACF99EE77C8C2A6F1D1993BD81BBC8A91D27FB5924E80171670E6139A4BD353")
verify_lineup_mpv_file("${LINEUP_MPV_DLL}"
  "353D527E569F69D822A9D679B28D2E975C6B22A82AB9924D533110E1C21C8508")
verify_lineup_mpv_file("${LINEUP_MPV_LIBRARY}"
  "${LINEUP_MPV_IMPORT_LIBRARY_SHA256}")
target_include_directories(${BINARY_NAME} PRIVATE "${LINEUP_MPV_INCLUDE_DIR}")
target_link_libraries(${BINARY_NAME} PRIVATE "${LINEUP_MPV_LIBRARY}")
set(LINEUP_MPV_RUNTIME_LIBRARY "${LINEUP_MPV_DLL}" PARENT_SCOPE)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
