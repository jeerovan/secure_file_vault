#ifndef FIFE_RECOVERY_FILE_H_
#define FIFE_RECOVERY_FILE_H_
#include <string>

// Writes only to the explicit Save destination; never stages plaintext.
bool WriteRecoveryPhraseFile(const char* name, const std::string& text);
#endif
