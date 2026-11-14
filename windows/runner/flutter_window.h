#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <shellapi.h>

#include <memory>

#include "native_player.h"
#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  friend struct RunnerLifecycleTestAccess;

  void HandlePlatformMethod(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
      decltype(&::ShellExecuteW) open = ::ShellExecuteW);

  flutter::DartProject project_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> platform_channel_;

  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<WindowsNativePlayer> native_player_;
};

#endif
