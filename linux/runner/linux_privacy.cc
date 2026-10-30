#include "linux_privacy.h"
#include "linux_channel_utils.h"
#include "recovery_file.h"

#include <algorithm>
#include <unistd.h>

namespace {
constexpr auto kUnavailable = "RECOVERY_EXPORT_UNAVAILABLE";
bool IsPhrase(const std::string& text) {
  return !text.empty() && text.size() < 1024 &&
      std::count(text.begin(), text.end(), ' ') == 23;
}
void Erase(std::string& value) {
  if (!value.empty()) explicit_bzero(&value[0], value.size());
  value.clear();
}
}

LinuxPrivacy::LinuxPrivacy(GtkWindow* window, FlView* view,
                           FlBinaryMessenger* messenger)
    : window_(window), view_(view) {
  auto* overlay = gtk_overlay_new();
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  cover_ = gtk_event_box_new();
  gtk_widget_set_name(cover_, "fife-privacy-cover");
  gtk_container_add(GTK_CONTAINER(cover_), gtk_label_new("FiFe"));
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), cover_);
  gtk_container_add(GTK_CONTAINER(window), overlay);
  g_autoptr(GtkCssProvider) css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(css,
      "#fife-privacy-cover { background-color: @theme_bg_color; }", -1, nullptr);
  gtk_style_context_add_provider(gtk_widget_get_style_context(cover_),
      GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  gtk_widget_show_all(overlay);
  Cover();
  g_signal_connect(window_, "notify::is-active",
      G_CALLBACK(+[](GObject*, GParamSpec*, LinuxPrivacy* self) { self->ScheduleRefresh(); }), this);
  g_signal_connect(window_, "map",
      G_CALLBACK(+[](GtkWidget*, LinuxPrivacy* self) { self->ScheduleRefresh(); }), this);
  g_signal_connect(window_, "unmap",
      G_CALLBACK(+[](GtkWidget*, LinuxPrivacy* self) { self->SetActive(false); }), this);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  privacy_ = fl_method_channel_new(messenger, "com.jeerovan.fife/app_lock_privacy",
                                   FL_METHOD_CODEC(codec));
  export_ = fl_method_channel_new(messenger, "com.jeerovan.fife/recovery_export",
                                  FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(privacy_,
      +[](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        auto* self = static_cast<LinuxPrivacy*>(data);
        const auto* method = fl_method_call_get_name(call);
        auto* args = fl_method_call_get_args(call);
        if (g_strcmp0(method, "observeLifecycle") == 0) {
          self->Refresh();
          g_autoptr(FlValue) state = self->State(); Success(call, state);
        } else if (g_strcmp0(method, "setEnabled") == 0) {
          self->enabled_ = args && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
              fl_value_get_bool(args);
          if (self->enabled_ && !self->Active()) self->Cover();
          Success(call);
        } else if (g_strcmp0(method, "frameReady") == 0) {
          if (self->Active()) {
            self->frame_ready_ = BoolField(args, "allowNativeDocuments");
            const bool restore_focus =
                !gtk_widget_get_sensitive(GTK_WIDGET(self->view_));
            gtk_widget_hide(self->cover_);
            gtk_widget_set_sensitive(GTK_WIDGET(self->view_), TRUE);
            // Cover() removes native keyboard focus. The runner's initial
            // grab_focus happens while the view is still insensitive, so it
            // cannot restore it. Do this only when releasing the cover; later
            // Flutter frames must not steal focus from native window controls.
            if (restore_focus) gtk_widget_grab_focus(GTK_WIDGET(self->view_));
          }
          Success(call);
        } else if (g_strcmp0(method, "copyRecoveryPhrase") == 0) {
          auto text = StringValue(args);
          const bool copied = self->AllowsExport() && IsPhrase(text) && self->Copy(text);
          Erase(text);
          if (copied) Success(call);
          else Unavailable(call, "RECOVERY_COPY_UNAVAILABLE");
        } else fl_method_call_respond_not_implemented(call, nullptr);
      }, this, nullptr);
  fl_method_channel_set_method_call_handler(export_,
      +[](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        auto* self = static_cast<LinuxPrivacy*>(data);
        const auto* method = fl_method_call_get_name(call);
        if (g_strcmp0(method, "clear") == 0) {
          self->ClearExport(); self->ClearClipboard(); Success(call);
        } else if (g_strcmp0(method, "release") == 0) {
          if (StringValue(fl_method_call_get_args(call)) == self->reservation_)
            self->ClearExport();
          Success(call);
        } else if (g_strcmp0(method, "reserve") == 0) {
          if (self->saving_ || !self->AllowsExport()) { Unavailable(call, kUnavailable); return; }
          self->reservation_ = std::to_string(++self->export_epoch_);
          g_autoptr(FlValue) token = fl_value_new_string(self->reservation_.c_str());
          Success(call, token);
        } else if (g_strcmp0(method, "save") == 0) self->Save(call);
        else fl_method_call_respond_not_implemented(call, nullptr);
      }, this, nullptr);

  g_autoptr(GError) error = nullptr;
  system_ = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
  g_clear_error(&error);
  session_ = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (session_) {
    // GNOME and compatible desktops also emit this before lock-screen focus
    // changes. logind below covers other desktops and explicit session locks.
    screensaver_watch_ = g_dbus_connection_signal_subscribe(session_, "org.gnome.ScreenSaver",
        "org.gnome.ScreenSaver", "ActiveChanged", "/org/gnome/ScreenSaver", nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE,
        +[](GDBusConnection*, const gchar*, const gchar*, const gchar*, const gchar*,
            GVariant* parameters, gpointer data) {
          auto* self = static_cast<LinuxPrivacy*>(data);
          gboolean locked = FALSE; g_variant_get(parameters, "(b)", &locked);
          self->screensaver_locked_ = locked;
          if (locked) { self->Closing(); self->ClearClipboard(); }
          self->Refresh();
        }, this, nullptr);
  }
  if (system_) {
    g_clear_error(&error);
    g_autoptr(GVariant) response = g_dbus_connection_call_sync(system_,
        "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager",
        "GetSessionByPID", g_variant_new("(u)", static_cast<guint32>(getpid())),
        G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, &error);
    if (response) {
      const gchar* object = nullptr; g_variant_get(response, "(&o)", &object);
      login_session_ = g_dbus_proxy_new_sync(system_, G_DBUS_PROXY_FLAGS_NONE, nullptr,
          "org.freedesktop.login1", object, "org.freedesktop.login1.Session", nullptr, nullptr);
      if (login_session_) {
        g_autoptr(GVariant) locked = g_dbus_proxy_get_cached_property(login_session_, "LockedHint");
        if (locked) session_locked_ = g_variant_get_boolean(locked);
        g_signal_connect(login_session_, "g-properties-changed",
            G_CALLBACK(+[](GDBusProxy* proxy, GVariant*, const gchar* const*, LinuxPrivacy* self) {
              g_autoptr(GVariant) locked = g_dbus_proxy_get_cached_property(proxy, "LockedHint");
              if (!locked) return;
              self->session_locked_ = g_variant_get_boolean(locked);
              if (self->session_locked_) { self->Closing(); self->ClearClipboard(); }
              self->Refresh();
            }), this);
      }
    }
    sleep_watch_ = g_dbus_connection_signal_subscribe(system_, "org.freedesktop.login1",
        "org.freedesktop.login1.Manager", "PrepareForSleep", "/org/freedesktop/login1",
        nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        +[](GDBusConnection*, const gchar*, const gchar*, const gchar*, const gchar*,
            GVariant* parameters, gpointer data) {
          auto* self = static_cast<LinuxPrivacy*>(data);
          gboolean suspended = FALSE; g_variant_get(parameters, "(b)", &suspended);
          self->suspended_ = suspended;
          if (suspended) { self->Closing(); self->ClearClipboard(); }
          self->Refresh();
        }, this, nullptr);
  }
}

bool LinuxPrivacy::Eligible() const {
  return gtk_widget_get_visible(GTK_WIDGET(window_)) &&
      gtk_widget_get_mapped(GTK_WIDGET(window_)) &&
      !session_locked_ && !screensaver_locked_ && !suspended_;
}
bool LinuxPrivacy::Active() const {
  if (!Eligible()) return false;
  GList* windows = gtk_window_list_toplevels();
  bool active = false;
  for (GList* node = windows; node; node = node->next) {
    auto* window = GTK_WINDOW(node->data);
    if (!gtk_window_is_active(window)) continue;
    while (window && window != window_) window = gtk_window_get_transient_for(window);
    if (window == window_) { active = true; break; }
  }
  g_list_free(windows);
  return active;
}
bool LinuxPrivacy::AllowsExport() const { return enabled_ && frame_ready_ && Active(); }
FlValue* LinuxPrivacy::State() const {
  auto* value = fl_value_new_map();
  fl_value_set_string_take(value, "active", fl_value_new_bool(active_));
  fl_value_set_string_take(value, "revision", fl_value_new_int(revision_));
  return value;
}
void LinuxPrivacy::Cover() {
  frame_ready_ = false;
  gtk_widget_show(cover_);
  gtk_widget_set_sensitive(GTK_WIDGET(view_), FALSE);
}
void LinuxPrivacy::SetActive(bool active) {
  if (!active) {
    frame_ready_ = false;
    if (enabled_) Cover();
    if (active_ || saving_) ClearExport();
  }
  if (active_ == active) return;
  active_ = active; ++revision_;
  g_autoptr(FlValue) state = State();
  fl_method_channel_invoke_method(privacy_, "lifecycle", state, nullptr, nullptr, nullptr);
}
void LinuxPrivacy::Refresh() { SetActive(Active()); }
void LinuxPrivacy::ScheduleRefresh() {
  if (refresh_) return;
  refresh_ = g_idle_add(+[](gpointer data) -> gboolean {
    auto* self = static_cast<LinuxPrivacy*>(data);
    self->refresh_ = 0; self->Refresh(); return G_SOURCE_REMOVE;
  }, this);
}
void LinuxPrivacy::Closing() {
  SetActive(false); ClearExport();
  if (cancel_auth_) cancel_auth_();
}
void LinuxPrivacy::PrepareToShow() {
  if (enabled_ && !Active()) Cover();
  ScheduleRefresh();
}
void LinuxPrivacy::ClearExport() {
  ++export_epoch_; reservation_.clear();
  if (dialog_) gtk_dialog_response(GTK_DIALOG(dialog_), GTK_RESPONSE_CANCEL);
}
void LinuxPrivacy::EraseClipboard() {
  clipboard_owned_ = false;
  Erase(clipboard_text_);
  if (clipboard_timer_) { g_source_remove(clipboard_timer_); clipboard_timer_ = 0; }
}
void LinuxPrivacy::ClearClipboard() {
  if (clipboard_owned_) gtk_clipboard_clear(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
  EraseClipboard();
}
bool LinuxPrivacy::Copy(const std::string& text) {
  ClearClipboard();
  clipboard_text_ = text;
  GtkTargetEntry targets[] = {
      {const_cast<gchar*>("UTF8_STRING"), 0, 0},
      {const_cast<gchar*>("text/plain;charset=utf-8"), 0, 0},
      {const_cast<gchar*>("x-kde-passwordManagerHint"), 0, 1}};
  clipboard_owned_ = gtk_clipboard_set_with_data(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD),
      targets, G_N_ELEMENTS(targets),
      +[](GtkClipboard*, GtkSelectionData* selection, guint info, gpointer data) {
        auto* self = static_cast<LinuxPrivacy*>(data);
        if (info == 1) {
          const auto* hint = reinterpret_cast<const guchar*>("secret");
          gtk_selection_data_set(selection, gtk_selection_data_get_target(selection), 8, hint, 6);
        } else gtk_selection_data_set_text(selection, self->clipboard_text_.c_str(), -1);
      }, +[](GtkClipboard*, gpointer data) {
        static_cast<LinuxPrivacy*>(data)->EraseClipboard();
      }, this);
  if (!clipboard_owned_) { EraseClipboard(); return false; }
  // Never ask a clipboard manager to persist this data (no set_can_store).
  clipboard_timer_ = g_timeout_add_seconds(60, +[](gpointer data) -> gboolean {
    auto* self = static_cast<LinuxPrivacy*>(data);
    self->clipboard_timer_ = 0; self->ClearClipboard(); return G_SOURCE_REMOVE;
  }, this);
  return true;
}
void LinuxPrivacy::Save(FlMethodCall* call) {
  auto* args = fl_method_call_get_args(call);
  auto text = StringField(args, "text");
  const auto token = StringField(args, "reservation");
  if (saving_ || !AllowsExport() || token.empty() || token != reservation_ || !IsPhrase(text)) {
    Erase(text); Unavailable(call, kUnavailable); return;
  }
  const auto title = StringField(args, "title", "FiFe");
  dialog_ = gtk_file_chooser_dialog_new(title.c_str(), window_, GTK_FILE_CHOOSER_ACTION_SAVE,
      g_dgettext("gtk30", "_Cancel"), GTK_RESPONSE_CANCEL,
      g_dgettext("gtk30", "_Save"), GTK_RESPONSE_ACCEPT, nullptr);
  gtk_file_chooser_set_current_name(GTK_FILE_CHOOSER(dialog_), "fife_recovery_phrase.txt");
  gtk_file_chooser_set_do_overwrite_confirmation(GTK_FILE_CHOOSER(dialog_), TRUE);
  gtk_file_chooser_set_local_only(GTK_FILE_CHOOSER(dialog_), TRUE);
  gtk_window_set_modal(GTK_WINDOW(dialog_), TRUE);
  g_signal_connect(dialog_, "notify::is-active",
      G_CALLBACK(+[](GObject*, GParamSpec*, LinuxPrivacy* self) { self->ScheduleRefresh(); }), this);
  const auto epoch = export_epoch_;
  saving_ = true;
  const auto response = gtk_dialog_run(GTK_DIALOG(dialog_));
  const bool accepted = response == GTK_RESPONSE_ACCEPT && epoch == export_epoch_ &&
      token == reservation_ && Eligible();
  bool saved = false;
  if (accepted) {
    g_autofree gchar* file = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog_));
    saved = file && WriteRecoveryPhraseFile(file, text);
  }
  Erase(text);
  gtk_widget_destroy(dialog_); dialog_ = nullptr; saving_ = false;
  reservation_.clear(); ++export_epoch_;
  ScheduleRefresh();
  if (accepted && !saved) Unavailable(call, kUnavailable);
  else { g_autoptr(FlValue) value = fl_value_new_bool(saved); Success(call, value); }
}
LinuxPrivacy::~LinuxPrivacy() {
  cancel_auth_ = nullptr;
  ClearExport(); ClearClipboard();
  if (refresh_) g_source_remove(refresh_);
  g_signal_handlers_disconnect_by_data(window_, this);
  fl_method_channel_set_method_call_handler(privacy_, nullptr, nullptr, nullptr);
  fl_method_channel_set_method_call_handler(export_, nullptr, nullptr, nullptr);
  g_clear_object(&privacy_); g_clear_object(&export_);
  if (screensaver_watch_) g_dbus_connection_signal_unsubscribe(session_, screensaver_watch_);
  if (sleep_watch_) g_dbus_connection_signal_unsubscribe(system_, sleep_watch_);
  if (login_session_) g_signal_handlers_disconnect_by_data(login_session_, this);
  g_clear_object(&login_session_); g_clear_object(&session_); g_clear_object(&system_);
}
