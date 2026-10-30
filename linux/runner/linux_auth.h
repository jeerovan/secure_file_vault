#ifndef FIFE_LINUX_AUTH_H_
#define FIFE_LINUX_AUTH_H_

#include <flutter_linux/flutter_linux.h>
#include <functional>
#include <memory>

class LinuxAuth {
 public:
  LinuxAuth(FlBinaryMessenger* messenger, std::function<bool()> active,
            std::function<bool()> eligible);
  ~LinuxAuth();
  void Cancel();

 private:
  struct Operation;
  void Begin(FlMethodCall* call, bool authenticate);
  void Check(const std::shared_ptr<Operation>& operation, bool interactive);
  void Finish(const std::shared_ptr<Operation>& operation, bool success);
  GDBusConnection* system_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
  std::shared_ptr<Operation> operation_;
  std::function<bool()> active_, eligible_;
};
#endif
