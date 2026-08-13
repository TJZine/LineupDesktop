#ifndef RUNNER_NATIVE_PLAYER_H_
#define RUNNER_NATIVE_PLAYER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <mpv/client.h>
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>

class WindowsNativePlayer {
 public:
  static constexpr UINT kPlatformEventMessage = WM_APP + 0x31;

  WindowsNativePlayer(HWND top_level_window, HWND flutter_view,
                      flutter::BinaryMessenger* messenger);
  ~WindowsNativePlayer();

  WindowsNativePlayer(const WindowsNativePlayer&) = delete;
  WindowsNativePlayer& operator=(const WindowsNativePlayer&) = delete;

  bool HandleWindowMessage(UINT message);
  bool BeginWindowClose();
  bool TakeWindowCloseReady();
  void SetParentMinimized(bool minimized);

 private:
  struct QueuedEvent {
    uint64_t generation;
    flutter::EncodableMap value;
  };

  enum class CommandType { load, play, pause, seek, stop, track, volume };
  struct QueuedCommand {
    CommandType type;
    int64_t load_id = 0;
    std::string text;
    double number = 0;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool Initialize(std::string& error);
  void BeginAsyncDispose();
  void Dispose();
  void FinishDispose();
  void QueueCommand(QueuedCommand command);
  void RunCommand(const QueuedCommand& command, uint64_t generation);
  bool SetVideoRect(const flutter::EncodableMap& arguments);
  bool SetFullscreen(bool fullscreen, std::string& error);
  std::optional<QueuedCommand> ParseTrack(
      const flutter::EncodableMap& arguments);
  void StartEventThread();
  void StopEventThread();
  void EventLoop(uint64_t generation);
  void HandleMpvEvent(const mpv_event& event, uint64_t generation);
  void QueueEvent(uint64_t generation, flutter::EncodableMap value);
  void PostPlatformWakeup();
  void DrainEvents();
  flutter::EncodableValue EncodeTrackList(const mpv_node& node) const;
  flutter::EncodableValue EncodeVideoParameters(const mpv_node& node) const;

  HWND top_level_window_;
  HWND flutter_view_;
  HWND video_host_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  mpv_handle* mpv_ = nullptr;
  std::thread event_thread_;
  std::atomic<bool> accepting_commands_{false};
  std::atomic<bool> stopping_{false};
  std::atomic<uint64_t> generation_{0};
  std::atomic<bool> wakeup_posted_{false};
  std::mutex command_mutex_;
  std::deque<QueuedCommand> commands_;
  std::mutex event_mutex_;
  std::deque<QueuedEvent> events_;
  std::optional<int64_t> active_load_id_;
  std::optional<int64_t> event_load_id_;
  std::unordered_map<int64_t, int64_t> playlist_load_ids_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
      dispose_result_;
  std::atomic<bool> dispose_ready_{false};
  bool shutdown_started_ = false;
  bool disposed_ = true;
  bool window_close_requested_ = false;
  bool window_close_ready_ = false;
  RECT video_rect_{};
  bool video_rect_set_ = false;
  bool parent_minimized_ = false;
  bool fullscreen_ = false;
  WINDOWPLACEMENT window_placement_{sizeof(WINDOWPLACEMENT)};
  LONG_PTR window_style_ = 0;
};

#endif  // RUNNER_NATIVE_PLAYER_H_
