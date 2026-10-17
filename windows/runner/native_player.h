#ifndef RUNNER_NATIVE_PLAYER_H_
#define RUNNER_NATIVE_PLAYER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include "display_dynamic_range.h"

#include <memory>
#include <optional>
#include <string>

#include "player_core/player_core.h"

// Windows adapter for the shared player core. It owns the Flutter channel and
// codec conversion, the child HWND that libmpv renders into, display
// matching, fullscreen, and WM_CLOSE/end-session sequencing.
class WindowsNativePlayer final : private lineup::player::CoreHost {
 public:
  static constexpr UINT kPlatformEventMessage = WM_APP + 0x31;

  using MpvOperations = lineup::player::MpvOperations;

  WindowsNativePlayer(HWND top_level_window, HWND flutter_view,
                      flutter::BinaryMessenger* messenger);
  WindowsNativePlayer(HWND top_level_window, HWND flutter_view,
                      flutter::BinaryMessenger* messenger,
                      MpvOperations mpv_operations);
  ~WindowsNativePlayer();

  WindowsNativePlayer(const WindowsNativePlayer&) = delete;
  WindowsNativePlayer& operator=(const WindowsNativePlayer&) = delete;

  bool HandleWindowMessage(UINT message, WPARAM wparam = 0);
  void EndWindowsSession();
  bool BeginWindowClose();
  bool TakeWindowCloseReady();
  void SetParentMinimized(bool minimized);

 private:
  friend struct NativePlayerTestAccess;

  // lineup::player::CoreHost
  bool PostWakeup() override;
  void PostWorkerFinished() override;
  std::optional<lineup::player::CallError> PrepareOutput(
      lineup::player::OutputConfig& output) override;
  void CancelOutput() override;
  void ReleaseOutput() override;
  void OnDisposeRequested() override;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SendEvent(const lineup::player::ValueMap& event);
  bool SetDisplayMatching(const lineup::player::ValueMap* arguments,
                          std::string& error);
  bool SetVideoRect(const lineup::player::ValueMap& arguments);
  bool SetFullscreen(bool fullscreen, std::string& error);
  void QueueDisplayReport(const lineup::DisplayReport& report);

  HWND top_level_window_;
  HWND flutter_view_;
  HWND video_host_ = nullptr;
  // Declared before display_ so that display callbacks always reach a live
  // core; the destructor resets display_ before shutting the core down.
  lineup::player::PlayerCore core_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<lineup::DisplayDynamicRange> display_;
  bool window_close_requested_ = false;
  bool window_close_ready_ = false;
  bool display_close_timeout_ = false;
  RECT video_rect_{};
  bool video_rect_set_ = false;
  bool parent_minimized_ = false;
  bool fullscreen_ = false;
  WINDOWPLACEMENT window_placement_{sizeof(WINDOWPLACEMENT)};
  LONG_PTR window_style_ = 0;
};

#endif
