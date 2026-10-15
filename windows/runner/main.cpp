#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "display_guardian.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (auto guardian = lineup::DispatchDisplayGuardian(command_line)) {
    return *guardian;
  }
  HANDLE instance_mutex = ::CreateMutexW(
      nullptr, TRUE, L"Local\\TJZine.LineupDesktop.Instance");
  if (instance_mutex == nullptr) {
    return EXIT_FAILURE;
  }

  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing_window = ::FindWindowW(nullptr, L"Lineup Desktop");
    if (existing_window != nullptr) {
      if (::IsIconic(existing_window)) {
        ::ShowWindow(existing_window, SW_RESTORE);
      }
      ::BringWindowToTop(existing_window);
      ::SetForegroundWindow(existing_window);
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  ::SetEnvironmentVariableW(L"LINEUP_FLUTTER_DCOMP_ACTIVE", nullptr);
  ::SetEnvironmentVariableW(L"FLUTTER_WINDOWS_DCOMP", L"1");

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Lineup Desktop", origin, size)) {
    ::CloseHandle(instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
