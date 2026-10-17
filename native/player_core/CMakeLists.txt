# Platform-neutral libmpv player core shared by the Windows runner and the
# macOS adapter.
#
# Included from windows/runner/CMakeLists.txt, it defines the core libraries
# and the portable test targets (excluded from the default build). Configured
# on its own, it builds and runs the portable tests:
#
#   cmake -S native/player_core -B build/player_core
#   cmake --build build/player_core
#   ctest --test-dir build/player_core --output-on-failure
#
# The tests use fake MpvOperations, so they need the mpv headers but not
# libmpv. Set LINEUP_MPV_INCLUDE_DIR to the directory containing mpv/client.h.
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  cmake_minimum_required(VERSION 3.14)
  project(lineup_player_core LANGUAGES CXX)
  set(LINEUP_PLAYER_CORE_STANDALONE ON)
  enable_testing()
else()
  set(LINEUP_PLAYER_CORE_STANDALONE OFF)
endif()

if(NOT DEFINED LINEUP_MPV_INCLUDE_DIR)
  set(LINEUP_MPV_INCLUDE_DIR "/opt/homebrew/include" CACHE PATH
    "Directory that contains mpv/client.h")
endif()
if(NOT EXISTS "${LINEUP_MPV_INCLUDE_DIR}/mpv/client.h")
  message(FATAL_ERROR
    "LINEUP_MPV_INCLUDE_DIR (${LINEUP_MPV_INCLUDE_DIR}) does not contain mpv/client.h.")
endif()

find_package(Threads REQUIRED)
get_filename_component(LINEUP_NATIVE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)

# The Windows build supplies apply_standard_settings (MSVC /W4 /WX, no
# exceptions). Elsewhere, use an equivalent strict warning set.
function(lineup_player_core_settings TARGET)
  if(COMMAND apply_standard_settings)
    apply_standard_settings(${TARGET})
  else()
    target_compile_features(${TARGET} PUBLIC cxx_std_17)
    set_target_properties(${TARGET} PROPERTIES CXX_EXTENSIONS OFF)
    if(MSVC)
      target_compile_options(${TARGET} PRIVATE /W4 /WX /wd4100 /EHsc)
    else()
      target_compile_options(${TARGET} PRIVATE
        -Wall -Wextra -Wpedantic -Wshadow -Werror)
    endif()
  endif()
endfunction()

add_library(lineup_player_core STATIC
  "player_core.cpp"
  "track_list_encoder.cpp"
)
lineup_player_core_settings(lineup_player_core)
target_include_directories(lineup_player_core PUBLIC
  "${LINEUP_NATIVE_DIR}" "${LINEUP_MPV_INCLUDE_DIR}")
target_link_libraries(lineup_player_core PUBLIC Threads::Threads)

# Binds MpvOperations to the real libmpv. The consumer links libmpv itself.
add_library(lineup_player_core_libmpv STATIC
  "libmpv_operations.cpp"
)
lineup_player_core_settings(lineup_player_core_libmpv)
target_link_libraries(lineup_player_core_libmpv PUBLIC lineup_player_core)

if(LINEUP_PLAYER_CORE_STANDALONE)
  set(LINEUP_PLAYER_CORE_TEST_OPTIONS)
else()
  set(LINEUP_PLAYER_CORE_TEST_OPTIONS EXCLUDE_FROM_ALL)
endif()

add_executable(track_list_encoder_test ${LINEUP_PLAYER_CORE_TEST_OPTIONS}
  "track_list_encoder_test.cpp"
)
lineup_player_core_settings(track_list_encoder_test)
target_link_libraries(track_list_encoder_test PRIVATE lineup_player_core)
add_test(NAME track_list_encoder COMMAND track_list_encoder_test)

add_executable(native_playback_state_test ${LINEUP_PLAYER_CORE_TEST_OPTIONS}
  "native_playback_state_test.cpp"
)
lineup_player_core_settings(native_playback_state_test)
target_include_directories(native_playback_state_test PRIVATE "${LINEUP_NATIVE_DIR}")
add_test(NAME native_playback_state COMMAND native_playback_state_test)

add_executable(player_core_contract_test ${LINEUP_PLAYER_CORE_TEST_OPTIONS}
  "player_core_contract_test.cpp"
)
lineup_player_core_settings(player_core_contract_test)
target_link_libraries(player_core_contract_test PRIVATE lineup_player_core)
add_test(NAME player_core_contract COMMAND player_core_contract_test)
set_tests_properties(player_core_contract PROPERTIES TIMEOUT 45)
