cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)
if(NOT CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION OR
    CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION VERSION_LESS "10.0.26100.0")
  message(FATAL_ERROR "Lineup HDR matching requires Windows SDK 10.0.26100.0 or newer.")
endif()

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "native_player.cpp"
  "display_recovery.cpp"
  "display_dynamic_range.cpp"
  "display_guardian.cpp"
  "track_list_encoder.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib")
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
    "322CB0040B97B15F97069F631F665FD63DA331CED92705F757DA13B99380DA5F")
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
  "4BA364226FD2EA5DD2C6F2333F0118462DA549FEED92360FB766A3924E313A51")
verify_lineup_mpv_file("${LINEUP_MPV_LIBRARY}"
  "${LINEUP_MPV_IMPORT_LIBRARY_SHA256}")
target_include_directories(${BINARY_NAME} PRIVATE "${LINEUP_MPV_INCLUDE_DIR}")
target_link_libraries(${BINARY_NAME} PRIVATE "${LINEUP_MPV_LIBRARY}")
set(LINEUP_MPV_RUNTIME_LIBRARY "${LINEUP_MPV_DLL}" PARENT_SCOPE)

add_executable(track_list_encoder_test EXCLUDE_FROM_ALL
  "track_list_encoder.cpp"
  "track_list_encoder_test.cpp"
)
apply_standard_settings(track_list_encoder_test)
target_include_directories(track_list_encoder_test PRIVATE "${LINEUP_MPV_INCLUDE_DIR}")
target_link_libraries(track_list_encoder_test PRIVATE flutter_wrapper_app)
add_test(NAME track_list_encoder COMMAND track_list_encoder_test)

add_executable(authenticated_reference_test EXCLUDE_FROM_ALL
  "authenticated_reference_test.cpp"
  "native_player.cpp"
  "track_list_encoder.cpp"
  "display_recovery.cpp"
  "display_dynamic_range.cpp"
  "display_guardian.cpp"
)
apply_standard_settings(authenticated_reference_test)
target_compile_definitions(authenticated_reference_test PRIVATE "NOMINMAX")
target_include_directories(authenticated_reference_test PRIVATE "${LINEUP_MPV_INCLUDE_DIR}")
target_link_libraries(authenticated_reference_test PRIVATE
  flutter_wrapper_app "${LINEUP_MPV_LIBRARY}" "dwmapi.lib" "shell32.lib")
add_custom_command(TARGET authenticated_reference_test POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${LINEUP_MPV_DLL}" "$<TARGET_FILE_DIR:authenticated_reference_test>")
add_test(NAME authenticated_reference
  COMMAND "${CMAKE_COMMAND}"
    "-DLINEUP_REFERENCE_CHECKER=${CMAKE_SOURCE_DIR}/../tool/windows/authenticated-reference-test.py"
    "-DLINEUP_REFERENCE_HARNESS=$<TARGET_FILE:authenticated_reference_test>"
    "-DLINEUP_REFERENCE_DLL=${LINEUP_MPV_DLL}"
    -P "${CMAKE_SOURCE_DIR}/../tool/windows/run-authenticated-reference-test.cmake")
set_tests_properties(authenticated_reference PROPERTIES TIMEOUT 180)

add_executable(native_playback_state_test EXCLUDE_FROM_ALL
  "native_playback_state_test.cpp"
)
apply_standard_settings(native_playback_state_test)
add_test(NAME native_playback_state COMMAND native_playback_state_test)

add_executable(native_player_contract_test EXCLUDE_FROM_ALL
  "native_player_contract_test.cpp"
  "native_player.cpp"
  "track_list_encoder.cpp"
  "display_recovery.cpp"
  "display_dynamic_range.cpp"
  "display_guardian.cpp"
)
apply_standard_settings(native_player_contract_test)
target_compile_definitions(native_player_contract_test PRIVATE "NOMINMAX")
target_include_directories(native_player_contract_test PRIVATE "${LINEUP_MPV_INCLUDE_DIR}")
target_link_libraries(native_player_contract_test PRIVATE
  flutter_wrapper_app "${LINEUP_MPV_LIBRARY}" "dwmapi.lib" "ole32.lib" "shell32.lib")
add_custom_command(TARGET native_player_contract_test POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${LINEUP_MPV_DLL}" "$<TARGET_FILE_DIR:native_player_contract_test>")
add_test(NAME native_player_contract COMMAND native_player_contract_test)
set_tests_properties(native_player_contract PROPERTIES TIMEOUT 45)

add_executable(runner_lifecycle_test EXCLUDE_FROM_ALL
  "runner_lifecycle_test.cpp"
  "flutter_window.cpp"
  "native_player.cpp"
  "track_list_encoder.cpp"
  "win32_window.cpp"
  "utils.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "display_recovery.cpp"
  "display_dynamic_range.cpp"
  "display_guardian.cpp"
)
apply_standard_settings(runner_lifecycle_test)
target_compile_definitions(runner_lifecycle_test PRIVATE "NOMINMAX")
target_include_directories(runner_lifecycle_test PRIVATE
  "${CMAKE_SOURCE_DIR}" "${LINEUP_MPV_INCLUDE_DIR}")
target_link_libraries(runner_lifecycle_test PRIVATE
  flutter flutter_wrapper_app flutter_secure_storage_windows_plugin
  "${LINEUP_MPV_LIBRARY}" "dwmapi.lib" "ole32.lib" "shell32.lib")
add_dependencies(runner_lifecycle_test flutter_assemble)
add_custom_command(TARGET runner_lifecycle_test POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${LINEUP_MPV_DLL}" "$<TARGET_FILE_DIR:runner_lifecycle_test>")
add_test(NAME runner_lifecycle
  COMMAND runner_lifecycle_test "$<TARGET_FILE_DIR:${BINARY_NAME}>/data")
set_tests_properties(runner_lifecycle PROPERTIES TIMEOUT 45
  WORKING_DIRECTORY "$<TARGET_FILE_DIR:${BINARY_NAME}>")

add_executable(display_dynamic_range_test EXCLUDE_FROM_ALL
  "display_recovery.cpp"
  "display_dynamic_range.cpp"
  "display_dynamic_range_test.cpp"
)
apply_standard_settings(display_dynamic_range_test)
target_compile_definitions(display_dynamic_range_test PRIVATE "NOMINMAX")
target_link_libraries(display_dynamic_range_test PRIVATE "user32.lib")
add_test(NAME display_dynamic_range COMMAND display_dynamic_range_test)
set_tests_properties(display_dynamic_range PROPERTIES TIMEOUT 30)

add_executable(display_guardian_test EXCLUDE_FROM_ALL
  "display_guardian.cpp"
  "display_recovery.cpp"
  "display_dynamic_range.cpp"
  "display_guardian_test.cpp"
  "display_admission_process_test.cpp"
)
apply_standard_settings(display_guardian_test)
target_compile_definitions(display_guardian_test PRIVATE "NOMINMAX")
target_link_libraries(display_guardian_test PRIVATE "user32.lib" "shell32.lib")
add_test(NAME display_guardian COMMAND display_guardian_test)
set_tests_properties(display_guardian PROPERTIES TIMEOUT 60)

add_dependencies(${BINARY_NAME} flutter_assemble)

foreach(target ${BINARY_NAME} authenticated_reference_test native_player_contract_test
    runner_lifecycle_test display_dynamic_range_test display_guardian_test)
  target_link_libraries(${target} PRIVATE "advapi32.lib" "shell32.lib")
endforeach()
