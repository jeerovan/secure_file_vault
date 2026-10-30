#ifndef RUNNER_WINDOWS_DESKTOP_H_
#define RUNNER_WINDOWS_DESKTOP_H_

#include <windows.h>
#include <shellapi.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <functional>
#include <memory>
#include <optional>
#include <string>

// One icon belongs to the existing main window/engine, including while hidden.
class WindowsDesktop {
 public:
  WindowsDesktop(HWND window, flutter::BinaryMessenger* messenger,
                 std::function<void()> open, std::function<void()> quit);
  ~WindowsDesktop();
  bool available() const { return installed_; }
  std::optional<LRESULT> Handle(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  bool Install();
  void Menu(POINT point);
  HWND window_;
  NOTIFYICONDATAW icon_{};
  HICON image_ = nullptr;
  UINT taskbar_created_;
  bool installed_ = false, sync_enabled_ = false, busy_ = false;
  std::wstring open_text_ = L"Open", sync_text_ = L"Sync", quit_text_ = L"Quit";
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::function<void()> open_, quit_;
};
#endif
