#ifndef FIFE_LINUX_CHANNEL_UTILS_H_
#define FIFE_LINUX_CHANNEL_UTILS_H_

#include <flutter_linux/flutter_linux.h>
#include <string>

inline FlValue* Field(FlValue* map, const char* key) {
  return map && fl_value_get_type(map) == FL_VALUE_TYPE_MAP
      ? fl_value_lookup_string(map, key) : nullptr;
}
inline bool BoolField(FlValue* map, const char* key) {
  auto* value = Field(map, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
      fl_value_get_bool(value);
}
inline std::string StringValue(FlValue* value) {
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
      ? fl_value_get_string(value) : "";
}
inline std::string StringField(FlValue* map, const char* key,
                               const char* fallback = "") {
  auto* value = Field(map, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
      ? fl_value_get_string(value) : fallback;
}
inline void Success(FlMethodCall* call, FlValue* value = nullptr) {
  fl_method_call_respond_success(call, value, nullptr);
}
inline void Unavailable(FlMethodCall* call, const char* code) {
  fl_method_call_respond_error(call, code, "System operation unavailable",
                               nullptr, nullptr);
}
#endif
