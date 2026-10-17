#include "flutter_window.h"
#include "native_player_test_support.h"

#include <filesystem>

struct RunnerLifecycleTestAccess {
  static WindowsNativePlayer& Player(FlutterWindow& window) {
    native_test::Check(window.native_player_ != nullptr, "actual runner native owner");
    return *window.native_player_;
  }
  static bool MessengerAlive(FlutterWindow& window) {
    return window.flutter_controller_ && window.flutter_controller_->engine() &&
           window.flutter_controller_->engine()->messenger();
  }
  static bool Retired(FlutterWindow& window) {
    return !window.native_player_ && !window.flutter_controller_;
  }
};

int main(int argc, char** argv) {
  using native_test::Check;
  using native_test::Reply;
  Check(argc == 2, "runner lifecycle requires installed candidate data directory");
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ::SetEnvironmentVariableW(L"LINEUP_FLUTTER_DCOMP_ACTIVE", nullptr);
  ::SetEnvironmentVariableW(L"FLUTTER_WINDOWS_DCOMP", L"1");
  const std::filesystem::path data(argv[1]);
  Check(std::filesystem::is_directory(data / "flutter_assets"), "assembled Flutter assets required");
  flutter::DartProject project(data.wstring());
  project.set_dart_entrypoint("nativeRunnerLifecycleTestMain");
  {
    FlutterWindow window(project);
    Check(window.Create(L"Lineup runner lifecycle test", {10, 10}, {64, 64}),
          "actual FlutterWindow creation with pinned engine and isolated entrypoint");
    window.SetQuitOnClose(false);
    const HWND hwnd = window.GetHandle();
    auto& player = RunnerLifecycleTestAccess::Player(window);
    Reply initialize;
    NativePlayerTestAccess::Invoke(player, "initialize", initialize);
    Check(initialize.successes == 1,
          "actual patched-engine marker and production native initialization");
    Reply disposed;
    disposed.on_success = [&]() {
      Check(NativePlayerTestAccess::Disposed(player), "runner result after join/FinishDispose");
      Check(::IsWindow(hwnd) && RunnerLifecycleTestAccess::MessengerAlive(window),
            "actual runner retains window and Flutter messenger until result");
    };
    NativePlayerTestAccess::Invoke(player, "dispose", disposed);
    Check(disposed.successes == 0, "runner disposal is asynchronous");
    native_test::PumpUntil([&]() { return disposed.successes == 1; },
                          "actual runner routes production platform disposal message");
    Reply reinitialize;
    NativePlayerTestAccess::Invoke(player, "initialize", reinitialize);
    Check(reinitialize.successes == 1, "runner recreate after disposal");
    Reply close_dispose;
    close_dispose.on_success = [&]() {
      Check(NativePlayerTestAccess::Disposed(player), "close result after worker teardown and join");
      Check(::IsWindow(hwnd) && RunnerLifecycleTestAccess::MessengerAlive(window),
            "WM_CLOSE cannot retire real messenger/window before pending dispose result");
    };
    NativePlayerTestAccess::Invoke(player, "dispose", close_dispose);
    ::SendMessage(hwnd, WM_CLOSE, 0, 0);
    Check(::IsWindow(hwnd) && NativePlayerTestAccess::ShutdownStarted(player),
          "actual runner defers WM_CLOSE during async shutdown");
    native_test::PumpUntil([&]() { return !::IsWindow(hwnd); }, "actual runner closes after readiness");
    Check(close_dispose.successes == 1 && close_dispose.errors == 0,
          "result precedes actual runner retirement");
    Check(RunnerLifecycleTestAccess::Retired(window), "OnDestroy retires native owner then engine");
  }
  ::CoUninitialize();
  return 0;
}
