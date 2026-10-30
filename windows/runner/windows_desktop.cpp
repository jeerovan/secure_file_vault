#include "windows_desktop.h"

#include <commctrl.h>
#include <windowsx.h>
#include <flutter/standard_method_codec.h>
#include "resource.h"
#include "windows_channel_utils.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 81;
constexpr UINT kOpen = 1, kSync = 2, kQuit = 3;
constexpr UINT_PTR kRetryTray = 0xF1F1;
}

WindowsDesktop::WindowsDesktop(HWND window, flutter::BinaryMessenger* messenger,
    std::function<void()> open, std::function<void()> quit)
    : window_(window), taskbar_created_(RegisterWindowMessage(L"TaskbarCreated")),
      open_(std::move(open)), quit_(std::move(quit)) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.jeerovan.fife/desktop", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "updateMenu") { result->NotImplemented(); return; }
    const auto* args = call.arguments();
    busy_ = BoolField(args, "busy");
    sync_enabled_ = BoolField(args, "syncEnabled") && !busy_;
    open_text_ = Utf16(StringField(args, "open", "Open"));
    sync_text_ = Utf16(StringField(args, busy_ ? "syncing" : "sync", "Sync"));
    quit_text_ = Utf16(StringField(args, "quit", "Quit"));
    result->Success();
  });
  icon_.cbSize = sizeof(icon_);
  icon_.hWnd = window;
  icon_.uID = 1;
  icon_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
  icon_.uCallbackMessage = kTrayMessage;
  LoadIconMetric(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON),
                 LIM_SMALL, &image_);
  icon_.hIcon = image_;
  wcscpy_s(icon_.szTip, L"FiFe");
  Install();
}

WindowsDesktop::~WindowsDesktop() {
  channel_->SetMethodCallHandler(nullptr);
  KillTimer(window_, kRetryTray);
  Shell_NotifyIcon(NIM_DELETE, &icon_);
  if (image_) DestroyIcon(image_);
}

bool WindowsDesktop::Install() {
  installed_ = image_ && Shell_NotifyIcon(NIM_ADD, &icon_);
  if (installed_) {
    icon_.uVersion = NOTIFYICON_VERSION_4;
    if (!Shell_NotifyIcon(NIM_SETVERSION, &icon_)) {
      Shell_NotifyIcon(NIM_DELETE, &icon_);
      installed_ = false;
    }
  }
  if (installed_) KillTimer(window_, kRetryTray);
  else SetTimer(window_, kRetryTray, 3000, nullptr);
  return installed_;
}

std::optional<LRESULT> WindowsDesktop::Handle(UINT message, WPARAM wparam,
                                             LPARAM lparam) {
  if (message == taskbar_created_) {
    installed_ = false;
    if (!Install() && !IsWindowVisible(window_)) open_();
    return 0;
  }
  if (message == WM_TIMER && wparam == kRetryTray) { Install(); return 0; }
  if (message != kTrayMessage) return std::nullopt;
  const auto event = LOWORD(lparam);
  if (event == NIN_SELECT || event == NIN_KEYSELECT) open_();
  if (event == WM_CONTEXTMENU) {
    POINT point{GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam)};
    if (point.x == -1 && point.y == -1) GetCursorPos(&point);
    Menu(point);
  }
  return 0;
}

void WindowsDesktop::Menu(POINT point) {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenu(menu, MF_STRING, kOpen, open_text_.c_str());
  AppendMenu(menu, MF_STRING | (sync_enabled_ ? MF_ENABLED : MF_GRAYED),
             kSync, sync_text_.c_str());
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kQuit, quit_text_.c_str());
  SetMenuDefaultItem(menu, kOpen, FALSE);
  // Required for normal dismissal when clicking outside a tray menu.
  SetForegroundWindow(window_);
  const UINT action = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
      point.x, point.y, 0, window_, nullptr);
  DestroyMenu(menu);
  PostMessage(window_, WM_NULL, 0, 0);
  if (action == kOpen) open_();
  if (action == kSync && sync_enabled_) {
    sync_enabled_ = false;
    channel_->InvokeMethod("sync", nullptr);
  }
  if (action == kQuit) quit_();
}
