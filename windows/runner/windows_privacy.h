#ifndef RUNNER_WINDOWS_PRIVACY_H_
#define RUNNER_WINDOWS_PRIVACY_H_

#include <windows.h>
#include <shobjidl.h>
#include <wrl/client.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <optional>
#include <string>

class WindowsPrivacy {
 public:
  WindowsPrivacy(HWND window, flutter::BinaryMessenger* messenger);
  ~WindowsPrivacy();
  std::optional<LRESULT> Handle(UINT message, WPARAM wparam, LPARAM lparam);
  void PrepareToShow();
  void WindowClosing();
  bool saving() const { return saving_; }

 private:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;
  bool ApplicationActive() const;
  bool AllowsExport() const;
  void Refresh();
  void SetActive(bool active);
  void Cover();
  void ClearExport();
  void ClearClipboard();
  bool Copy(const std::string& text);
  void Save(const Value* arguments, std::unique_ptr<Result> result);
  Value State() const;
  HWND window_, cover_ = nullptr;
  bool enabled_ = true, active_ = false, frame_ready_ = false;
  bool session_locked_ = false, saving_ = false;
  int64_t revision_ = 0;
  uint64_t export_epoch_ = 0;
  std::string reservation_;
  DWORD clipboard_sequence_ = 0;
  Microsoft::WRL::ComPtr<IFileSaveDialog> dialog_;
  std::unique_ptr<flutter::MethodChannel<Value>> privacy_, export_;
};
#endif
