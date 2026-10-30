#include "linux_desktop.h"
#include "linux_channel_utils.h"

LinuxDesktop::LinuxDesktop(GtkWindow* window, FlBinaryMessenger* messenger,
                           const char* icon, std::function<void()> open,
                           std::function<void()> quit)
    : window_(window), open_(std::move(open)), quit_(std::move(quit)) {
  menu_ = gtk_menu_new();
  g_object_ref_sink(menu_);
  open_item_ = gtk_menu_item_new_with_label("Open");
  sync_item_ = gtk_menu_item_new_with_label("Sync");
  quit_item_ = gtk_menu_item_new_with_label("Quit");
  for (auto* item : {open_item_, sync_item_, quit_item_}) {
    gtk_menu_shell_append(GTK_MENU_SHELL(menu_), item);
  }
  gtk_widget_set_sensitive(sync_item_, FALSE);
  gtk_widget_show_all(menu_);
  g_signal_connect_swapped(open_item_, "activate",
      G_CALLBACK(+[](LinuxDesktop* self) { self->open_(); }), this);
  g_signal_connect_swapped(quit_item_, "activate",
      G_CALLBACK(+[](LinuxDesktop* self) {
        self->quitting_ = true;
        self->quit_();
      }), this);
  g_signal_connect_swapped(sync_item_, "activate",
      G_CALLBACK(+[](LinuxDesktop* self) {
        if (gtk_widget_get_sensitive(self->sync_item_)) {
          fl_method_channel_invoke_method(self->channel_, "sync", nullptr,
                                           nullptr, nullptr, nullptr);
        }
      }), this);
  indicator_ = app_indicator_new("com.jeerovan.fife", icon,
                                 APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
  app_indicator_set_title(indicator_, g_get_application_name());
  app_indicator_set_menu(indicator_, GTK_MENU(menu_));
  app_indicator_set_secondary_activate_target(indicator_, open_item_);
  g_signal_connect(indicator_, "connection-changed",
      G_CALLBACK(+[](AppIndicator*, gboolean connected, LinuxDesktop* self) {
        // A shell/tray restart must not strand a hidden vault window.
        if (!connected && !self->quitting_ &&
            !gtk_widget_get_visible(GTK_WIDGET(self->window_))) self->open_();
      }), this);
  app_indicator_set_status(indicator_, APP_INDICATOR_STATUS_ACTIVE);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, "com.jeerovan.fife/desktop",
                                   FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_,
      +[](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        auto* self = static_cast<LinuxDesktop*>(data);
        if (g_strcmp0(fl_method_call_get_name(call), "updateMenu") != 0) {
          fl_method_call_respond_not_implemented(call, nullptr); return;
        }
        auto* args = fl_method_call_get_args(call);
        gtk_menu_item_set_label(GTK_MENU_ITEM(self->open_item_),
            StringField(args, "open", "Open").c_str());
        gtk_menu_item_set_label(GTK_MENU_ITEM(self->quit_item_),
            StringField(args, "quit", "Quit").c_str());
        const bool busy = BoolField(args, "busy");
        gtk_menu_item_set_label(GTK_MENU_ITEM(self->sync_item_),
            StringField(args, busy ? "syncing" : "sync",
                        busy ? "In progress..." : "Sync").c_str());
        gtk_widget_set_sensitive(self->sync_item_,
                                 !busy && BoolField(args, "syncEnabled"));
        Success(call);
      }, this, nullptr);
}

bool LinuxDesktop::available() const {
  gboolean connected = FALSE;
  if (indicator_) g_object_get(indicator_, "connected", &connected, nullptr);
  return connected;
}

LinuxDesktop::~LinuxDesktop() {
  quitting_ = true;
  fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
  g_clear_object(&channel_);
  g_signal_handlers_disconnect_by_data(indicator_, this);
  app_indicator_set_status(indicator_, APP_INDICATOR_STATUS_PASSIVE);
  g_clear_object(&indicator_);
  gtk_widget_destroy(menu_);
  g_clear_object(&menu_);
}
