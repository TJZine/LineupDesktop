#include "flutter_window.h"
#include "native_player_test_support.h"

#include <filesystem>

struct RunnerLifecycleTestAccess {
  inline static INT_PTR shell_result = 33;
  inline static int shell_calls = 0;
  static HINSTANCE WINAPI Open(HWND, LPCWSTR verb, LPCWSTR url,
                              LPCWSTR parameters, LPCWSTR directory, INT show) {
    native_test::Check(std::wstring(verb) == L"open" &&
        std::wstring(url) == L"https://plex.tv/link" && !parameters &&
        !directory && show == SW_SHOWNORMAL, "fixed native browser request");
    ++shell_calls;
    return reinterpret_cast<HINSTANCE>(shell_result);
  }
  static void Platform(FlutterWindow& window, const char* name,
                       std::unique_ptr<flutter::EncodableValue> arguments,
                       bool* opened, int* errors, int* missing) {
    window.HandlePlatformMethod(
        flutter::MethodCall<flutter::EncodableValue>(name, std::move(arguments)),
        std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
            [opened](const auto* value) { *opened = std::get<bool>(*value); },
            [errors](const auto&, const auto&, const auto*) { ++*errors; },
            [missing]() { ++*missing; }), &Open);
  }
  static void CheckPlatform(FlutterWindow& window) {
    bool opened = false;
    int errors = 0, missing = 0;
    for (const auto code : {0, 2, 31, 32, 33, 42}) {
      shell_result = code;
      Platform(window, "openPlexLink", nullptr, &opened, &errors, &missing);
      native_test::Check(opened == (code > 32), "documented ShellExecute result");
    }
    Platform(window, "openPlexLink",
             std::make_unique<flutter::EncodableValue>(),
             &opened, &errors, &missing);
    native_test::Check(opened, "codec null is an argument-free request");
    const auto calls = shell_calls;
    Platform(window, "openPlexLink",
             std::make_unique<flutter::EncodableValue>("https://untrusted.invalid"),
             &opened, &errors, &missing);
    Platform(window, "unknown", nullptr, &opened, &errors, &missing);
    native_test::Check(errors == 1 && missing == 1 && shell_calls == calls,
                       "arguments and unknown methods never invoke shell");
  }
  static WindowsNativePlayer& Player(FlutterWindow& window) {
    native_test::Check(window.native_player_ != nullptr, "actual runner native owner");
    return *window.native_player_;
  }
  static bool MessengerAlive(FlutterWindow& window) {
    return window.flutter_controller_ && window.flutter_controller_->engine() &&
           window.flutter_controller_->engine()->messenger();
  }
  static bool Retired(FlutterWindow& window) {
    return !window.platform_channel_ && !window.native_player_ &&
           !window.flutter_controller_;
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
    RunnerLifecycleTestAccess::CheckPlatform(window);
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
