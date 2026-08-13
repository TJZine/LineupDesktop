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
    "LINEUP_MPV_ROOT must point to a local libmpv development build. "
    "See docs/DEVELOPMENT.md.")
endif()
file(TO_CMAKE_PATH "$ENV{LINEUP_MPV_ROOT}" LINEUP_MPV_ROOT)
find_path(LINEUP_MPV_INCLUDE_DIR "mpv/client.h"
  PATHS "${LINEUP_MPV_ROOT}/include" NO_DEFAULT_PATH REQUIRED)
find_library(LINEUP_MPV_LIBRARY "libmpv"
  PATHS "${LINEUP_MPV_ROOT}" NO_DEFAULT_PATH REQUIRED)
find_file(LINEUP_MPV_DLL "libmpv-2.dll"
  PATHS "${LINEUP_MPV_ROOT}" NO_DEFAULT_PATH REQUIRED)
target_include_directories(${BINARY_NAME} PRIVATE "${LINEUP_MPV_INCLUDE_DIR}")
target_link_libraries(${BINARY_NAME} PRIVATE "${LINEUP_MPV_LIBRARY}")
set(LINEUP_MPV_RUNTIME_LIBRARY "${LINEUP_MPV_DLL}" PARENT_SCOPE)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
