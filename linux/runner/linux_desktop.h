#ifndef FIFE_LINUX_DESKTOP_H_
#define FIFE_LINUX_DESKTOP_H_

#include <flutter_linux/flutter_linux.h>
#include <libayatana-appindicator/app-indicator.h>
#include <functional>

class LinuxDesktop {
 public:
  LinuxDesktop(GtkWindow* window, FlBinaryMessenger* messenger,
               const char* icon, std::function<void()> open,
               std::function<void()> quit);
  ~LinuxDesktop();
  bool available() const;

 private:
  GtkWindow* window_;
  AppIndicator* indicator_ = nullptr;
  GtkWidget* menu_ = nullptr;
  GtkWidget *open_item_, *sync_item_, *quit_item_;
  FlMethodChannel* channel_ = nullptr;
  bool quitting_ = false;
  std::function<void()> open_, quit_;
};
#endif
