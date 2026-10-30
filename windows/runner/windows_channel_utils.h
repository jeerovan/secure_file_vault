#ifndef RUNNER_WINDOWS_CHANNEL_UTILS_H_
#define RUNNER_WINDOWS_CHANNEL_UTILS_H_

#include <windows.h>
#include <flutter/encodable_value.h>
#include <string>

inline std::wstring Utf16(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring value(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), value.data(), size);
  return value;
}

inline const flutter::EncodableValue* Field(
    const flutter::EncodableValue* args, const char* key) {
  const auto* map = args ? std::get_if<flutter::EncodableMap>(args) : nullptr;
  if (!map) return nullptr;
  const auto it = map->find(flutter::EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

inline bool BoolField(const flutter::EncodableValue* args, const char* key) {
  const auto* field = Field(args, key);
  const auto* value = field ? std::get_if<bool>(field) : nullptr;
  return value && *value;
}

inline std::string StringField(const flutter::EncodableValue* args,
                               const char* key, const char* fallback = "") {
  const auto* field = Field(args, key);
  const auto* value = field ? std::get_if<std::string>(field) : nullptr;
  return value ? *value : fallback;
}
#endif
