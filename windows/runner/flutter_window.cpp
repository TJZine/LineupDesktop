#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  platform_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "lineup/platform",
          &flutter::StandardMethodCodec::GetInstance());
  platform_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandlePlatformMethod(call, std::move(result));
      });
  RegisterPlugins(flutter_controller_->engine());
  const HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view);
  native_player_ = std::make_unique<WindowsNativePlayer>(
      GetHandle(), flutter_view, flutter_controller_->engine()->messenger());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (platform_channel_) {
    platform_channel_->SetMethodCallHandler(nullptr);
    platform_channel_.reset();
  }
  native_player_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_QUERYENDSESSION) return TRUE;
  if (message == WM_ENDSESSION && wparam == TRUE && native_player_) {
    native_player_->EndWindowsSession();
    return 0;
  }
  if (native_player_ && native_player_->HandleWindowMessage(message, wparam)) {
    if (native_player_->TakeWindowCloseReady()) {
      ::DestroyWindow(hwnd);
    }
    return 0;
  }
  if (message == WM_CLOSE && native_player_ &&
      !native_player_->BeginWindowClose()) {
    return 0;
  }
  if (message == WM_SIZE && native_player_) {
    native_player_->SetParentMinimized(wparam == SIZE_MINIMIZED);
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::HandlePlatformMethod(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    decltype(&::ShellExecuteW) open) {
  if (call.method_name() != "openPlexLink") {
    result->NotImplemented();
    return;
  }
  if (call.arguments() &&
      !std::holds_alternative<std::monostate>(*call.arguments())) {
    result->Error("invalid_arguments", "This method accepts no arguments.");
    return;
  }
  // No caller-controlled URL, executable name, working directory or parameters.
  const auto outcome = open(GetHandle(), L"open", L"https://plex.tv/link",
                            nullptr, nullptr, SW_SHOWNORMAL);
  result->Success(flutter::EncodableValue(
      reinterpret_cast<INT_PTR>(outcome) > 32));
}
