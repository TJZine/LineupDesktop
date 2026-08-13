#ifndef RUNNER_NATIVE_PLAYER_H_
#define RUNNER_NATIVE_PLAYER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <mpv/client.h>
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <queue>
#include <string>
#include <thread>

class WindowsNativePlayer {
 public:
  static constexpr UINT kPlatformEventMessage = WM_APP + 0x31;

  WindowsNativePlayer(HWND top_level_window, HWND flutter_view,
                      flutter::BinaryMessenger* messenger);
  ~WindowsNativePlayer();

  WindowsNativePlayer(const WindowsNativePlayer&) = delete;
  WindowsNativePlayer& operator=(const WindowsNativePlayer&) = delete;

  bool HandleWindowMessage(UINT message);
  void SetParentMinimized(bool minimized);

 private:
  struct QueuedEvent {
    uint64_t generation;
    flutter::EncodableMap value;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool Initialize(std::string& error);
  void Dispose();
  int Command(std::initializer_list<const char*> arguments);
  int SetOption(const char* name, const char* value);
  bool SetVideoRect(const flutter::EncodableMap& arguments);
  void SetFullscreen(bool fullscreen);
  std::optional<int> SetTrack(const flutter::EncodableMap& arguments);
  void StartEventThread();
  void StopEventThread();
  void EventLoop(uint64_t generation);
  void HandleMpvEvent(const mpv_event& event, uint64_t generation);
  void QueueEvent(uint64_t generation, flutter::EncodableMap value);
  void DrainEvents();
  flutter::EncodableValue EncodeTrackList(const mpv_node& node) const;
  flutter::EncodableValue EncodeVideoParameters(const mpv_node& node) const;
  void LogPlaybackFact(const std::string& name, const std::string& value) const;

  HWND top_level_window_;
  HWND flutter_view_;
  HWND video_host_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  mpv_handle* mpv_ = nullptr;
  std::thread event_thread_;
  std::atomic<bool> stopping_{false};
  std::atomic<uint64_t> generation_{0};
  std::mutex event_mutex_;
  std::queue<QueuedEvent> events_;
  RECT video_rect_{};
  bool video_rect_set_ = false;
  bool parent_minimized_ = false;
  bool fullscreen_ = false;
  WINDOWPLACEMENT window_placement_{sizeof(WINDOWPLACEMENT)};
  LONG_PTR window_style_ = 0;
};

#endif  // RUNNER_NATIVE_PLAYER_H_
