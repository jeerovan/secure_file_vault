#ifndef FIFE_LINUX_PRIVACY_H_
#define FIFE_LINUX_PRIVACY_H_

#include <flutter_linux/flutter_linux.h>
#include <functional>
#include <string>

class LinuxPrivacy {
 public:
  LinuxPrivacy(GtkWindow* window, FlView* view, FlBinaryMessenger* messenger);
  ~LinuxPrivacy();
  bool Active() const;
  bool Eligible() const;
  void Closing();
  void PrepareToShow();
  void set_cancel_auth(std::function<void()> cancel) { cancel_auth_ = std::move(cancel); }

 private:
  void Refresh();
  void ScheduleRefresh();
  void Cover();
  void SetActive(bool active);
  FlValue* State() const;
  bool AllowsExport() const;
  void ClearExport();
  void ClearClipboard();
  void EraseClipboard();
  bool Copy(const std::string& text);
  void Save(FlMethodCall* call);
  GtkWindow* window_;
  FlView* view_;
  GtkWidget* cover_;
  GtkWidget* dialog_ = nullptr;
  FlMethodChannel *privacy_ = nullptr, *export_ = nullptr;
  GDBusConnection *session_ = nullptr, *system_ = nullptr;
  GDBusProxy* login_session_ = nullptr;
  guint screensaver_watch_ = 0, sleep_watch_ = 0, refresh_ = 0, clipboard_timer_ = 0;
  bool enabled_ = true, active_ = false, frame_ready_ = false;
  bool session_locked_ = false, screensaver_locked_ = false;
  bool suspended_ = false, saving_ = false;
  bool clipboard_owned_ = false;
  int64_t revision_ = 0;
  uint64_t export_epoch_ = 0;
  std::string reservation_, clipboard_text_;
  std::function<void()> cancel_auth_;
};
#endif
