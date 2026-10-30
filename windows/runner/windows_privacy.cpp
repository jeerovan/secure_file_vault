#include "windows_privacy.h"

#include <wtsapi32.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include "windows_channel_utils.h"

namespace {
constexpr UINT kRefresh = WM_APP + 82;
constexpr UINT_PTR kClipboardExpiry = 0xF1F2;
constexpr auto kUnavailable = "RECOVERY_EXPORT_UNAVAILABLE";
bool IsPhrase(const std::string& text) {
  return text.size() < 1024 &&
      std::count(text.begin(), text.end(), ' ') == 23;
}
bool PutClipboard(UINT format, const void* bytes, SIZE_T size) {
  if (!format) return false;
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, size);
  if (!memory) return false;
  void* data = GlobalLock(memory);
  if (!data) { GlobalFree(memory); return false; }
  memcpy(data, bytes, size);
  GlobalUnlock(memory);
  if (SetClipboardData(format, memory)) return true;
  data = GlobalLock(memory);
  if (data) { SecureZeroMemory(data, size); GlobalUnlock(memory); }
  GlobalFree(memory);
  return false;
}
}

WindowsPrivacy::WindowsPrivacy(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  const auto* codec = &flutter::StandardMethodCodec::GetInstance();
  privacy_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "com.jeerovan.fife/app_lock_privacy", codec);
  export_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "com.jeerovan.fife/recovery_export", codec);
  privacy_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "observeLifecycle") {
      Refresh(); result->Success(State());
    } else if (method == "setEnabled") {
      const auto* value = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      enabled_ = value && *value;
      if (enabled_ && !ApplicationActive()) Cover();
      // Even when disabled, only a completed Flutter frame removes the cold
      // launch cover; settings hydration must not expose a previous private UI.
      result->Success();
    } else if (method == "frameReady") {
      if (ApplicationActive()) {
        frame_ready_ = BoolField(call.arguments(), "allowNativeDocuments");
        ShowWindow(cover_, SW_HIDE);
      }
      result->Success();
    } else if (method == "copyRecoveryPhrase") {
      const auto* text = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (AllowsExport() && text && IsPhrase(*text) && Copy(*text)) result->Success();
      else result->Error("RECOVERY_COPY_UNAVAILABLE", "Protected copy unavailable");
    } else result->NotImplemented();
  });
  export_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "clear") {
      ClearExport(); ClearClipboard(); result->Success();
    } else if (method == "release") {
      const auto* token = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (token && *token == reservation_) ClearExport();
      result->Success();
    } else if (method == "reserve") {
      if (saving_ || !AllowsExport()) {
        result->Error(kUnavailable, "Protected export unavailable"); return;
      }
      reservation_ = std::to_string(++export_epoch_);
      result->Success(Value(reservation_));
    } else if (method == "save") Save(call.arguments(), std::move(result));
    else result->NotImplemented();
  });
  // Start covered before the first window Show, regardless of persisted policy.
  cover_ = CreateWindowEx(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_WHITERECT,
      0, 0, 1, 1, window_, nullptr, GetModuleHandle(nullptr), nullptr);
  Cover();
  WTSRegisterSessionNotification(window_, NOTIFY_FOR_THIS_SESSION);
}

WindowsPrivacy::~WindowsPrivacy() {
  privacy_->SetMethodCallHandler(nullptr);
  export_->SetMethodCallHandler(nullptr);
  ClearExport(); ClearClipboard();
  WTSUnRegisterSessionNotification(window_);
  if (cover_) DestroyWindow(cover_);
}

bool WindowsPrivacy::ApplicationActive() const {
  if (!IsWindowVisible(window_) || IsIconic(window_) || session_locked_) return false;
  DWORD process = 0;
  GetWindowThreadProcessId(GetForegroundWindow(), &process);
  // An owned native Save/Hello dialog must not be mistaken for another app.
  return process == GetCurrentProcessId();
}

bool WindowsPrivacy::AllowsExport() const {
  return enabled_ && frame_ready_ && ApplicationActive();
}

WindowsPrivacy::Value WindowsPrivacy::State() const {
  return Value(flutter::EncodableMap{
      {Value("active"), Value(active_)}, {Value("revision"), Value(revision_)}});
}

void WindowsPrivacy::Cover() {
  frame_ready_ = false;
  if (!cover_) return;
  RECT rect{};
  GetClientRect(window_, &rect);
  SetWindowPos(cover_, HWND_TOP, 0, 0, rect.right, rect.bottom,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  RedrawWindow(cover_, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW);
}

void WindowsPrivacy::SetActive(bool active) {
  if (!active) {
    frame_ready_ = false;
    if (enabled_) Cover();
  }
  if (active_ == active) return;
  active_ = active;
  ++revision_;
  privacy_->InvokeMethod("lifecycle", std::make_unique<Value>(State()));
}

void WindowsPrivacy::Refresh() { SetActive(ApplicationActive()); }

void WindowsPrivacy::PrepareToShow() {
  if (enabled_ && !ApplicationActive()) Cover();
  PostMessage(window_, kRefresh, 0, 0);
}

void WindowsPrivacy::WindowClosing() {
  SetActive(false);
  ClearExport();
}

std::optional<LRESULT> WindowsPrivacy::Handle(UINT message, WPARAM wparam, LPARAM) {
  switch (message) {
    case WM_ACTIVATEAPP:
      if (!wparam) SetActive(false);
      else PostMessage(window_, kRefresh, 0, 0);
      break;
    case WM_SHOWWINDOW:
      if (!wparam) SetActive(false);
      else PostMessage(window_, kRefresh, 0, 0);
      break;
    case WM_SIZE:
      if (wparam == SIZE_MINIMIZED) SetActive(false);
      else {
        if (IsWindowVisible(cover_)) Cover();
        PostMessage(window_, kRefresh, 0, 0);
      }
      break;
    case WM_WTSSESSION_CHANGE:
      if (wparam == WTS_SESSION_LOCK || wparam == WTS_CONSOLE_DISCONNECT || wparam == WTS_REMOTE_DISCONNECT) {
        session_locked_ = true; SetActive(false); ClearExport(); ClearClipboard();
      } else if (wparam == WTS_SESSION_UNLOCK || wparam == WTS_CONSOLE_CONNECT || wparam == WTS_REMOTE_CONNECT) {
        session_locked_ = false; PostMessage(window_, kRefresh, 0, 0);
      }
      break;
    case WM_POWERBROADCAST:
      if (wparam == PBT_APMSUSPEND) { session_locked_ = true; SetActive(false); ClearExport(); }
      else if (wparam == PBT_APMRESUMEAUTOMATIC || wparam == PBT_APMRESUMESUSPEND) {
        session_locked_ = false; PostMessage(window_, kRefresh, 0, 0);
      }
      break;
    case WM_TIMER:
      if (wparam == kClipboardExpiry) { ClearClipboard(); return 0; }
      break;
    case kRefresh: Refresh(); return 0;
  }
  return std::nullopt;
}

bool WindowsPrivacy::Copy(const std::string& text) {
  std::wstring value = Utf16(text);
  if (value.empty()) return false;
  if (!OpenClipboard(window_)) {
    SecureZeroMemory(value.data(), value.size() * sizeof(wchar_t));
    return false;
  }
  const DWORD exclude = 0;
  bool copied = EmptyClipboard() &&
      PutClipboard(RegisterClipboardFormat(L"CanIncludeInClipboardHistory"), &exclude, sizeof(exclude)) &&
      PutClipboard(RegisterClipboardFormat(L"CanUploadToCloudClipboard"), &exclude, sizeof(exclude)) &&
      PutClipboard(CF_UNICODETEXT, value.c_str(), (value.size() + 1) * sizeof(wchar_t));
  if (!copied) EmptyClipboard();
  // Record ownership while the clipboard is locked. After CloseClipboard a
  // different app can immediately copy; its sequence must never become ours.
  clipboard_sequence_ = copied ? GetClipboardSequenceNumber() : 0;
  CloseClipboard();
  SecureZeroMemory(value.data(), value.size() * sizeof(wchar_t));
  if (copied) SetTimer(window_, kClipboardExpiry, 60000, nullptr);
  return copied;
}

void WindowsPrivacy::ClearClipboard() {
  if (!clipboard_sequence_) return;
  if (GetClipboardSequenceNumber() == clipboard_sequence_) {
    if (!OpenClipboard(window_)) {
      SetTimer(window_, kClipboardExpiry, 1000, nullptr); return;
    }
    if (GetClipboardSequenceNumber() == clipboard_sequence_) EmptyClipboard();
    CloseClipboard();
  }
  clipboard_sequence_ = 0;
  KillTimer(window_, kClipboardExpiry);
}

void WindowsPrivacy::ClearExport() {
  ++export_epoch_;
  reservation_.clear();
  if (dialog_) dialog_->Close(HRESULT_FROM_WIN32(ERROR_CANCELLED));
}

void WindowsPrivacy::Save(const Value* args, std::unique_ptr<Result> result) {
  std::string text = StringField(args, "text");
  const auto token = StringField(args, "reservation");
  const auto title = Utf16(StringField(args, "title", "FiFe"));
  if (saving_ || !AllowsExport() || token.empty() || token != reservation_ || !IsPhrase(text)) {
    if (!text.empty()) SecureZeroMemory(text.data(), text.size());
    result->Error(kUnavailable, "Protected export unavailable"); return;
  }
  Microsoft::WRL::ComPtr<IFileSaveDialog> panel;
  HRESULT status = CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&panel));
  if (FAILED(status)) {
    SecureZeroMemory(text.data(), text.size());
    result->Error(kUnavailable, "Save dialog unavailable"); return;
  }
  const COMDLG_FILTERSPEC types[] = {{L"Text (*.txt)", L"*.txt"}};
  panel->SetFileTypes(1, types);
  panel->SetDefaultExtension(L"txt");
  panel->SetFileName(L"fife_recovery_phrase.txt");
  panel->SetTitle(title.c_str());
  panel->SetOptions(FOS_FORCEFILESYSTEM | FOS_OVERWRITEPROMPT | FOS_NOCHANGEDIR | FOS_DONTADDTORECENT);
  const auto epoch = export_epoch_;
  dialog_ = panel;
  saving_ = true;
  // Show runs a native modal message loop. Cleanup/close can invalidate the
  // reservation and dismiss this dialog through that same loop.
  status = panel->Show(window_);
  bool saved = false;
  if (SUCCEEDED(status) && epoch == export_epoch_ && token == reservation_ &&
      IsWindowVisible(window_) && !session_locked_) {
    Microsoft::WRL::ComPtr<IShellItem> item;
    PWSTR path = nullptr;
    if (SUCCEEDED(panel->GetResult(&item)) && SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
      HANDLE file = CreateFile(path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (file != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        saved = WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) &&
            written == text.size() && FlushFileBuffers(file);
        CloseHandle(file);
      }
      CoTaskMemFree(path);
    }
  }
  SecureZeroMemory(text.data(), text.size());
  dialog_.Reset();
  saving_ = false;
  reservation_.clear();
  ++export_epoch_;
  if (FAILED(status) && status != HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    result->Error(kUnavailable, "Save failed");
  } else if (SUCCEEDED(status) && epoch + 1 == export_epoch_ && !saved) {
    result->Error(kUnavailable, "Save failed");
  } else result->Success(Value(saved));
}
