#include "recovery_file.h"

#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

bool WriteRecoveryPhraseFile(const char* name, const std::string& text) {
  // O_NONBLOCK prevents a FIFO/device selected or substituted after the picker
  // from hanging the UI. Validate the opened descriptor before truncation.
  const int fd = open(name, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
  if (fd < 0) return false;
  struct stat info{};
  bool ok = fstat(fd, &info) == 0 && S_ISREG(info.st_mode) &&
      info.st_uid == geteuid() && info.st_nlink == 1 &&
      fchmod(fd, 0600) == 0 && ftruncate(fd, 0) == 0;
  size_t offset = 0;
  while (ok && offset < text.size()) {
    const auto written = write(fd, text.data() + offset, text.size() - offset);
    if (written < 0 && errno == EINTR) continue;
    if (written <= 0) { ok = false; break; }
    offset += static_cast<size_t>(written);
  }
  if (ok) ok = fsync(fd) == 0;
  if (close(fd) != 0) ok = false;
  return ok;
}
