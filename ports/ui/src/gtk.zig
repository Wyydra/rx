const std = @import("std");

pub const GtkApplication = opaque {};
pub const GtkApplicationWindow = opaque {};
pub const GtkWidget = opaque {};
pub const GtkButton = opaque {};
pub const gpointer = ?*anyopaque;
pub const gboolean = c_int;

pub extern fn gtk_application_new(application_id: [*:0]const u8, flags: c_int) ?*GtkApplication;
pub extern fn g_application_run(app: *GtkApplication, argc: c_int, argv: ?[*]?[*:0]u8) c_int;
pub extern fn g_application_quit(app: *GtkApplication) void;
pub extern fn g_object_unref(object: *anyopaque) void;
pub extern fn g_signal_connect_data(
    instance: *anyopaque,
    detailed_signal: [*:0]const u8,
    c_handler: *const anyopaque,
    data: ?*anyopaque,
    destroy_data: ?*const anyopaque,
    connect_flags: c_int,
) c_ulong;

pub extern fn gtk_application_window_new(app: *GtkApplication) *GtkApplicationWindow;
pub extern fn gtk_window_set_title(window: *GtkApplicationWindow, title: [*:0]const u8) void;
pub extern fn gtk_window_set_default_size(window: *GtkApplicationWindow, width: c_int, height: c_int) void;
pub extern fn gtk_window_set_child(window: *GtkApplicationWindow, child: *GtkWidget) void;
pub extern fn gtk_window_present(window: *GtkApplicationWindow) void;

pub extern fn gtk_label_new(str: [*:0]const u8) *GtkWidget;
pub extern fn gtk_label_set_text(label: *GtkWidget, str: [*:0]const u8) void;

pub extern fn gtk_button_new_with_label(label: [*:0]const u8) *GtkWidget;
pub extern fn gtk_button_set_label(button: *GtkButton, label: [*:0]const u8) void;

pub extern fn gtk_box_new(orientation: c_int, spacing: c_int) *GtkWidget;
pub extern fn gtk_box_append(box: *GtkWidget, child: *GtkWidget) void;

pub extern fn g_idle_add(function: *const anyopaque, data: gpointer) c_uint;

pub extern fn gtk_css_provider_new() *anyopaque;
pub extern fn gtk_css_provider_load_from_string(provider: *anyopaque, string: [*:0]const u8) void;
pub extern fn gtk_style_context_add_provider_for_display(display: *anyopaque, provider: *anyopaque, priority: c_uint) void;
pub extern fn gdk_display_get_default() ?*anyopaque;

pub extern fn gtk_widget_set_halign(widget: *GtkWidget, alignment: c_int) void;
pub extern fn gtk_widget_set_hexpand(widget: *GtkWidget, expand: gboolean) void;

pub fn connect(instance: anytype, signal: [*:0]const u8, handler: anytype) void {
    const inst: *anyopaque = @ptrCast(instance);
    const func: *const anyopaque = @ptrCast(handler);
    _ = g_signal_connect_data(inst, signal, func, null, null, 0);
}

pub fn connect_data(instance: anytype, signal: [*:0]const u8, handler: anytype, data: gpointer) void {
    const inst: *anyopaque = @ptrCast(instance);
    const func: *const anyopaque = @ptrCast(handler);
    _ = g_signal_connect_data(inst, signal, func, data, null, 0);
}
