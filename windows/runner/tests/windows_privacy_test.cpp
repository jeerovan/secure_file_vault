// Native component checks: actual Win32 privacy/clipboard/dialog transport,
// synthetic phrases, no account/SQLite setup. Normal launcher and Windows Hello
// remain separate journey checks. Run in the logged-in desktop session.
#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>
#include <cstdlib>
#include <iostream>
#include <map>
#include "windows_privacy.h"

using Value = flutter::EncodableValue;
constexpr auto kPrivacy = "com.jeerovan.fife/app_lock_privacy";
constexpr auto kExport = "com.jeerovan.fife/recovery_export";

void Check(bool condition, const char* label) {
  if (!condition) { std::cerr << "FAIL: " << label << '\n'; std::exit(1); }
  std::cout << "PASS: " << label << '\n';
}

struct Reply { bool replied = false, success = false; Value value; };
class Messenger : public flutter::BinaryMessenger {
 public:
  void Send(const std::string&, const uint8_t*, size_t,
            flutter::BinaryReply reply = nullptr) const override {
    if (reply) reply(nullptr, 0);
  }
  void SetMessageHandler(const std::string& channel,
      flutter::BinaryMessageHandler handler) override {
    handlers[channel] = std::move(handler);
  }
  Reply Call(const std::string& channel, const std::string& method,
             Value args = Value()) {
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    const auto message = codec.EncodeMethodCall(
        flutter::MethodCall<Value>(method, std::make_unique<Value>(args)));
    Reply reply;
    handlers.at(channel)(message->data(), message->size(), [&](const uint8_t* bytes, size_t size) {
      flutter::MethodResultFunctions<Value> result(
          [&](const Value* value) { reply.success = true; if (value) reply.value = *value; },
          [&](const std::string&, const std::string&, const Value*) { reply.success = false; },
          [&]() { reply.success = false; });
      reply.replied = codec.DecodeAndProcessResponseEnvelope(bytes, size, &result);
    });
    Check(reply.replied, "native channel replied");
    return reply;
  }
 private:
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
};

WindowsPrivacy* privacy = nullptr;
Messenger* messenger = nullptr;
bool cancel_export = false;
LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_TIMER && wparam == 71 && cancel_export) {
    cancel_export = false;
    KillTimer(window, 71);
    messenger->Call(kExport, "clear");
    return 0;
  }
  if (privacy) {
    const auto result = privacy->Handle(message, wparam, lparam);
    if (result) return *result;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

int main() {
  // Keep the last completed assertion observable if a native dialog stalls.
  std::cout << std::unitbuf;
  std::cerr << std::unitbuf;
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  WNDCLASSW klass{};
  klass.lpszClassName = L"FiFeSyntheticPrivacyTest";
  klass.lpfnWndProc = WindowProc;
  klass.hInstance = GetModuleHandle(nullptr);
  RegisterClass(&klass);
  HWND window = CreateWindow(klass.lpszClassName, L"FiFe native privacy check",
      WS_OVERLAPPEDWINDOW, 40, 40, 640, 480, nullptr, nullptr, klass.hInstance, nullptr);
  Check(window != nullptr, "isolated native window created");
  const auto previous_clipboard = GetClipboardSequenceNumber();
  Messenger transport;
  messenger = &transport;
  {
    WindowsPrivacy native(window, &transport);
    privacy = &native;
    Check(GetClipboardSequenceNumber() == previous_clipboard, "startup does not copy");
    Check(!transport.Call(kExport, "reserve").success, "hidden window cannot export");
    ShowWindow(window, SW_SHOW);
    SetForegroundWindow(window);
    MSG message;
    while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message); DispatchMessage(&message);
    }
    const auto state = transport.Call(kPrivacy, "observeLifecycle");
    const auto* map = std::get_if<flutter::EncodableMap>(&state.value);
    Check(map && std::get<bool>(map->at(Value("active"))), "real native foreground required");
    transport.Call(kPrivacy, "setEnabled", Value(true));
    Check(!transport.Call(kExport, "reserve").success, "cold cover denies export before ready frame");
    transport.Call(kPrivacy, "frameReady", Value(flutter::EncodableMap{
        {Value("allowNativeDocuments"), Value(false)}}));
    Check(!transport.Call(kExport, "reserve").success, "locked frame denies export");
    transport.Call(kPrivacy, "frameReady", Value(flutter::EncodableMap{
        {Value("allowNativeDocuments"), Value(true)}}));
    const auto reserved = transport.Call(kExport, "reserve");
    Check(reserved.success, "ready unlocked frame can reserve");
    transport.Call(kExport, "clear");
    const std::string phrase =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon "
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
    const auto save_args = [&](const Value& reservation) {
      return Value(flutter::EncodableMap{{Value("text"), Value(phrase)},
          {Value("reservation"), reservation}, {Value("title"), Value("Synthetic export: cancel automatically")}});
    };
    Check(!transport.Call(kExport, "save", save_args(reserved.value)).success,
          "cleanup invalidates unused reservation without a dialog or write");
    const auto fresh = transport.Call(kExport, "reserve");
    cancel_export = true;
    SetTimer(window, 71, 200, nullptr);
    const auto canceled = transport.Call(kExport, "save", save_args(fresh.value));
    Check(canceled.success && std::get_if<bool>(&canceled.value) && !std::get<bool>(canceled.value),
          "cleanup dismisses active native Save without publishing");
    Check(!native.saving(), "cancel releases native export state");
    Check(GetClipboardSequenceNumber() == previous_clipboard, "view/reserve/cancel never copy");
    // Do not overwrite the owner's clipboard in unattended component checks.
    // Explicit Copy, history/cloud flags and 60-second expiry are journey tests.
    native.WindowClosing();
    ShowWindow(window, SW_HIDE);
    Check(!transport.Call(kExport, "reserve").success, "closed window cannot export");
    privacy = nullptr;
  }
  DestroyWindow(window);
  CoUninitialize();
  std::cout << "Windows native privacy component checks passed\n";
}
