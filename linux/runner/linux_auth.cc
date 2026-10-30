#include "linux_auth.h"
#include "linux_channel_utils.h"

namespace {
constexpr auto kName = "org.freedesktop.PolicyKit1";
constexpr auto kPath = "/org/freedesktop/PolicyKit1/Authority";
constexpr auto kInterface = "org.freedesktop.PolicyKit1.Authority";
constexpr auto kAction = "com.jeerovan.fife.authenticate";
}

struct LinuxAuth::Operation {
  LinuxAuth* owner;
  FlMethodCall* call;
  GCancellable* cancel = g_cancellable_new();
  std::string id;
  bool authenticate;
  Operation(LinuxAuth* host, FlMethodCall* request, bool auth)
      : owner(host), call(FL_METHOD_CALL(g_object_ref(request))),
        authenticate(auth) {
    g_autofree gchar* uuid = g_uuid_string_random();
    id = uuid;
  }
  ~Operation() { g_object_unref(call); g_object_unref(cancel); }
};

LinuxAuth::LinuxAuth(FlBinaryMessenger* messenger, std::function<bool()> active,
                     std::function<bool()> eligible)
    : active_(std::move(active)), eligible_(std::move(eligible)) {
  g_autoptr(GError) error = nullptr;
  system_ = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, "com.jeerovan.fife/linux_auth",
                                   FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_,
      +[](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        auto* self = static_cast<LinuxAuth*>(data);
        const auto* name = fl_method_call_get_name(call);
        if (g_strcmp0(name, "isSupported") == 0) self->Begin(call, false);
        else if (g_strcmp0(name, "authenticate") == 0) self->Begin(call, true);
        else if (g_strcmp0(name, "cancel") == 0) {
          self->Cancel(); Success(call);
        } else fl_method_call_respond_not_implemented(call, nullptr);
      }, this, nullptr);
}

void LinuxAuth::Begin(FlMethodCall* call, bool authenticate) {
  if (!system_ || operation_ || !eligible_() ||
      (authenticate && !active_())) {
    g_autoptr(FlValue) no = fl_value_new_bool(false);
    Success(call, no); return;
  }
  operation_ = std::make_shared<Operation>(this, call, authenticate);
  Check(operation_, false);
}

void LinuxAuth::Check(const std::shared_ptr<Operation>& operation,
                      bool interactive) {
  // The subject is this process's own authenticated system-bus connection.
  // No supplied identity, password, command or arbitrary polkit details.
  GVariantBuilder subject, details;
  g_variant_builder_init(&subject, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&subject, "{sv}", "name",
      g_variant_new_string(g_dbus_connection_get_unique_name(system_)));
  g_variant_builder_init(&details, G_VARIANT_TYPE("a{ss}"));
  auto* args = g_variant_new("((sa{sv})sa{ss}us)", "system-bus-name", &subject,
                             kAction, &details, interactive ? 1u : 0u,
                             operation->id.c_str());
  auto* pending = new std::pair<std::shared_ptr<Operation>, bool>(operation, interactive);
  g_dbus_connection_call(system_, kName, kPath, kInterface, "CheckAuthorization",
      args, G_VARIANT_TYPE("((bba{ss}))"), G_DBUS_CALL_FLAGS_NONE, -1,
      operation->cancel,
      +[](GObject* source, GAsyncResult* result, gpointer data) {
        std::unique_ptr<std::pair<std::shared_ptr<Operation>, bool>> pending(
            static_cast<std::pair<std::shared_ptr<Operation>, bool>*>(data));
        auto operation = pending->first;
        g_autoptr(GError) error = nullptr;
        g_autoptr(GVariant) response = g_dbus_connection_call_finish(
            G_DBUS_CONNECTION(source), result, &error);
        auto* self = operation->owner;
        if (!self) return;
        gboolean authorized = FALSE, challenge = FALSE;
        if (response) {
          g_autoptr(GVariant) values = g_variant_get_child_value(response, 0);
          g_variant_get_child(values, 0, "b", &authorized);
          g_variant_get_child(values, 1, "b", &challenge);
        }
        if (pending->second) {
          self->Finish(operation, response && authorized && self->eligible_());
        } else if (!response || authorized || !challenge) {
          // Reject cached/permissive authorization: sensitive access must have
          // a fresh authentication challenge, never auth_self_keep/allow=yes.
          self->Finish(operation, false);
        } else if (!operation->authenticate) {
          self->Finish(operation, true);
        } else if (self->active_() && self->eligible_()) {
          self->Check(operation, true);
        } else {
          self->Finish(operation, false);
        }
      }, pending);
}

void LinuxAuth::Finish(const std::shared_ptr<Operation>& operation, bool success) {
  operation->owner = nullptr;
  if (operation_ == operation) operation_.reset();
  g_autoptr(FlValue) value = fl_value_new_bool(success);
  Success(operation->call, value);
}

void LinuxAuth::Cancel() {
  if (!operation_) return;
  auto operation = operation_;
  g_dbus_connection_call(system_, kName, kPath, kInterface,
      "CancelCheckAuthorization", g_variant_new("(s)", operation->id.c_str()),
      nullptr, G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, nullptr, nullptr);
  g_cancellable_cancel(operation->cancel);
  Finish(operation, false);
}

LinuxAuth::~LinuxAuth() {
  Cancel();
  fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
  g_clear_object(&channel_);
  g_clear_object(&system_);
}
