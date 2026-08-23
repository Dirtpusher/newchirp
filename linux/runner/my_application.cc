#include "my_application.h"

#include <cerrno>
#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

static constexpr char kWindowStateGroup[] = "window";
static constexpr char kWindowStateX[] = "x";
static constexpr char kWindowStateY[] = "y";
static constexpr char kWindowStateWidth[] = "width";
static constexpr char kWindowStateHeight[] = "height";
static constexpr char kWindowStateMaximized[] = "maximized";

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  gboolean window_state_ready;
  gboolean have_restored_size;
  gint restored_width;
  gint restored_height;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static char* window_state_path() {
  return g_build_filename(
      g_get_user_config_dir(), "newchirp", "window-state.ini", nullptr);
}

static gboolean restored_rect_is_visible(gint x,
                                         gint y,
                                         gint width,
                                         gint height) {
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr || width <= 0 || height <= 0) {
    return FALSE;
  }

  const GdkRectangle restored_rect = {x, y, width, height};
  const gint monitor_count = gdk_display_get_n_monitors(display);
  for (gint i = 0; i < monitor_count; ++i) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    GdkRectangle monitor_rect;
    gdk_monitor_get_geometry(monitor, &monitor_rect);

    GdkRectangle intersection;
    if (gdk_rectangle_intersect(&restored_rect, &monitor_rect,
                                &intersection) &&
        intersection.width >= 100 && intersection.height >= 100) {
      return TRUE;
    }
  }

  return FALSE;
}

static void load_window_state(MyApplication* self, GtkWindow* window) {
  g_autofree char* path = window_state_path();
  g_autoptr(GKeyFile) key_file = g_key_file_new();
  g_autoptr(GError) error = nullptr;

  if (!g_key_file_load_from_file(key_file, path, G_KEY_FILE_NONE, &error)) {
    g_clear_error(&error);
    return;
  }

  if (g_key_file_has_key(key_file, kWindowStateGroup, kWindowStateMaximized,
                         nullptr) &&
      g_key_file_get_boolean(key_file, kWindowStateGroup, kWindowStateMaximized,
                             nullptr)) {
    gtk_window_maximize(window);
    return;
  }

  if (!g_key_file_has_key(key_file, kWindowStateGroup, kWindowStateX, nullptr) ||
      !g_key_file_has_key(key_file, kWindowStateGroup, kWindowStateY, nullptr) ||
      !g_key_file_has_key(key_file, kWindowStateGroup, kWindowStateWidth,
                          nullptr) ||
      !g_key_file_has_key(key_file, kWindowStateGroup, kWindowStateHeight,
                          nullptr)) {
    return;
  }

  const gint x = g_key_file_get_integer(key_file, kWindowStateGroup,
                                        kWindowStateX, nullptr);
  const gint y = g_key_file_get_integer(key_file, kWindowStateGroup,
                                        kWindowStateY, nullptr);
  const gint width = g_key_file_get_integer(key_file, kWindowStateGroup,
                                            kWindowStateWidth, nullptr);
  const gint height = g_key_file_get_integer(key_file, kWindowStateGroup,
                                             kWindowStateHeight, nullptr);

  if (!restored_rect_is_visible(x, y, width, height)) {
    return;
  }

  self->have_restored_size = TRUE;
  self->restored_width = width;
  self->restored_height = height;
  gtk_window_move(window, x, y);
}

static void save_window_state(GtkWindow* window) {
  g_autofree char* path = window_state_path();
  g_autofree char* directory = g_path_get_dirname(path);
  g_autoptr(GKeyFile) key_file = g_key_file_new();
  g_autoptr(GError) error = nullptr;

  if (g_mkdir_with_parents(directory, 0755) != 0) {
    g_warning("Unable to create window state directory %s: %s", directory,
              g_strerror(errno));
    return;
  }

  if (gtk_window_is_maximized(window)) {
    g_key_file_set_boolean(key_file, kWindowStateGroup, kWindowStateMaximized,
                           TRUE);
  } else {
    gint x = 0;
    gint y = 0;
    gint width = 0;
    gint height = 0;
    gtk_window_get_position(window, &x, &y);
    gtk_window_get_size(window, &width, &height);

    g_key_file_set_boolean(key_file, kWindowStateGroup, kWindowStateMaximized,
                           FALSE);
    g_key_file_set_integer(key_file, kWindowStateGroup, kWindowStateX, x);
    g_key_file_set_integer(key_file, kWindowStateGroup, kWindowStateY, y);
    g_key_file_set_integer(key_file, kWindowStateGroup, kWindowStateWidth,
                           width);
    g_key_file_set_integer(key_file, kWindowStateGroup, kWindowStateHeight,
                           height);
  }

  if (!g_key_file_save_to_file(key_file, path, &error)) {
    g_warning("Unable to save window state: %s", error->message);
  }
}

static gboolean on_delete_event(GtkWidget* widget, GdkEvent* event,
                                gpointer user_data) {
  save_window_state(GTK_WINDOW(widget));
  return FALSE;
}

static gboolean on_configure_event(GtkWidget* widget, GdkEventConfigure* event,
                                   gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->window_state_ready) {
    save_window_state(GTK_WINDOW(widget));
  }
  return FALSE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  gtk_widget_show(toplevel);
  self->window_state_ready = TRUE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  self->window_state_ready = FALSE;
  self->have_restored_size = FALSE;
  self->restored_width = 0;
  self->restored_height = 0;
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "NewChirp");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "NewChirp");
  }

  gtk_window_set_default_size(window, 1280, 720);
  g_signal_connect(window, "delete-event", G_CALLBACK(on_delete_event), nullptr);
  g_signal_connect(window, "configure-event", G_CALLBACK(on_configure_event),
                   self);
  load_window_state(self, window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  if (self->have_restored_size) {
    gtk_widget_set_size_request(GTK_WIDGET(view), self->restored_width,
                                self->restored_height);
  }
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
