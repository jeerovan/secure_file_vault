#include "recovery_file.h"
#include <cassert>
#include <fstream>
#include <iterator>
#include <sys/stat.h>
#include <unistd.h>

std::string Read(const std::string& file) {
  std::ifstream input(file);
  return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}
int main() {
  char directory[] = "/tmp/fife-recovery-file-XXXXXX";
  assert(mkdtemp(directory));
  const std::string root(directory), file = root + "/phrase.txt";
  const std::string text = "public synthetic export test";
  assert(WriteRecoveryPhraseFile(file.c_str(), text));
  struct stat info{};
  assert(stat(file.c_str(), &info) == 0 && (info.st_mode & 0777) == 0600);
  assert(Read(file) == text);
  assert(chmod(file.c_str(), 0644) == 0);
  assert(WriteRecoveryPhraseFile(file.c_str(), text));
  assert(stat(file.c_str(), &info) == 0 && (info.st_mode & 0777) == 0600);
  const auto symbolic = root + "/symbolic", hard = root + "/hard";
  assert(symlink(file.c_str(), symbolic.c_str()) == 0);
  assert(!WriteRecoveryPhraseFile(symbolic.c_str(), "must not overwrite"));
  assert(link(file.c_str(), hard.c_str()) == 0);
  assert(!WriteRecoveryPhraseFile(hard.c_str(), "must not overwrite"));
  assert(Read(file) == text);
  assert(!WriteRecoveryPhraseFile(root.c_str(), text));
  const auto fifo = root + "/pipe";
  assert(mkfifo(fifo.c_str(), 0600) == 0);
  alarm(3); // A non-regular destination must never block the UI thread.
  assert(!WriteRecoveryPhraseFile(fifo.c_str(), text));
  alarm(0);
  assert(unlink(fifo.c_str()) == 0);
  assert(unlink(hard.c_str()) == 0);
  assert(unlink(symbolic.c_str()) == 0);
  assert(unlink(file.c_str()) == 0);
  assert(rmdir(root.c_str()) == 0);
}
