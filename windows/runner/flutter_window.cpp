#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kQuit = WM_APP + 84;
constexpr UINT_PTR kQuitAfterDialog = 0xF1F3;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  privacy_ = std::make_unique<WindowsPrivacy>(GetHandle(), flutter_controller_->engine()->messenger());
  desktop_ = std::make_unique<WindowsDesktop>(GetHandle(), flutter_controller_->engine()->messenger(),
      [this]() { Open(); }, [this]() { PostMessage(GetHandle(), kQuit, 0, 0); });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  desktop_.reset();
  privacy_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::Open() {
  if (privacy_) privacy_->PrepareToShow();
  ShowWindow(GetHandle(), IsIconic(GetHandle()) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(GetHandle());
  SetFocus(flutter_controller_->view()->GetNativeWindow());
}

void FlutterWindow::Quit() {
  if (privacy_) privacy_->WindowClosing();
  // Do not destroy the engine while a modal platform-channel handler is on the
  // stack. Closing its dialog unwinds that handler before actual termination.
  if (privacy_ && privacy_->saving()) {
    SetTimer(GetHandle(), kQuitAfterDialog, 50, nullptr);
    return;
  }
  KillTimer(GetHandle(), kQuitAfterDialog);
  Destroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kQuit || (message == WM_TIMER && wparam == kQuitAfterDialog)) {
    Quit(); return 0;
  }
  if (message == WM_CLOSE) {
    if (privacy_) privacy_->WindowClosing();
    if (desktop_ && desktop_->available()) {
      ShowWindow(hwnd, SW_HIDE);
    } else {
      Quit();
    }
    return 0;
  }
  if (privacy_) {
    const auto result = privacy_->Handle(message, wparam, lparam);
    if (result) return *result;
  }
  if (desktop_) {
    const auto result = desktop_->Handle(message, wparam, lparam);
    if (result) return *result;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
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
      if (flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
