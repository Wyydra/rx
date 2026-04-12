const std = @import("std");
const gtk = @import("gtk.zig");

const rx = @cImport({
    @cInclude("rx_api.h");
});

var global_sched: ?*rx.rx_scheduler_t = null;
var global_app: ?*gtk.GtkApplication = null;
var global_window: ?*gtk.GtkWidget = null;
var target_actor: u32 = 0;

// Named widget registry — populated once during `draw`, used by `update`.
var widget_registry: std.StringHashMapUnmanaged(*gtk.GtkWidget) = .{};

export fn app_activate(app: *gtk.GtkApplication, user_data: gtk.gpointer) callconv(.c) void {
    _ = user_data;
    global_window = @ptrCast(gtk.gtk_application_window_new(app));
    gtk.gtk_window_set_title(@ptrCast(global_window), "Rx Calculator");
    gtk.gtk_window_set_default_size(@ptrCast(global_window), 280, 400);

    const css_provider = gtk.gtk_css_provider_new();
    const css =
        \\ window { background-color: #1e1e2e; }
        \\ button { background-color: #313244; color: #cdd6f4; font-size: 18px; font-weight: bold; border-radius: 8px; margin: 4px; padding: 16px; box-shadow: 0px 2px 4px rgba(0,0,0,0.2); transition: all 0.2s; }
        \\ button:hover { background-color: #45475a; }
        \\ button:active { background-color: #585b70; box-shadow: none; }
        \\ label { color: #a6e3a1; font-size: 42px; font-weight: bold; margin: 20px 10px; }
    ;
    gtk.gtk_css_provider_load_from_string(css_provider, css);

    if (gtk.gdk_display_get_default()) |display| {
        gtk.gtk_style_context_add_provider_for_display(display, css_provider, 600);
    }
}

fn gtk_thread_main() void {
    const app = gtk.gtk_application_new("org.rx.plugin", 0) orelse return;
    global_app = app;

    gtk.connect(app, "activate", &app_activate);
    _ = gtk.g_application_run(app, 0, null);
    gtk.g_object_unref(app);
}

// ── Widget definition ────────────────────────────────────────────────────────

const WidgetDef = struct {
    kind: []const u8,
    text: ?[]const u8,
    /// widget_id: if set, the built GtkWidget is stored in widget_registry.
    id: ?[]const u8,
    children: std.ArrayListUnmanaged(*WidgetDef),
};

/// Read an rx value as a heap-allocated string (string or integer both ok).
fn readText(allocator: std.mem.Allocator, val: rx.rx_value_t) ?[]const u8 {
    if (rx.rx_is_string(val)) {
        const len = rx.rx_string_len(val);
        return allocator.dupe(u8, rx.rx_string_data(val)[0..len]) catch null;
    } else if (rx.rx_is_int(val)) {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{rx.rx_get_int(val)}) catch "?";
        return allocator.dupe(u8, s) catch null;
    }
    return null;
}

fn parse_widget(allocator: std.mem.Allocator, val: rx.rx_value_t) ?*WidgetDef {
    if (rx.rx_tuple_len(val) == 0) return null;
    const kind_val = rx.rx_tuple_get(val, 0);
    if (!rx.rx_is_string(kind_val)) return null;

    const kind_len = rx.rx_string_len(kind_val);
    const kind_ptr = rx.rx_string_data(kind_val);
    const def = allocator.create(WidgetDef) catch return null;
    def.* = .{
        .kind = allocator.dupe(u8, kind_ptr[0..kind_len]) catch return null,
        .text = null,
        .id = null,
        .children = .{},
    };

    if (std.mem.eql(u8, def.kind, "label")) {
        // (tuple "label" <text> [<widget_id>])
        def.text = readText(allocator, rx.rx_tuple_get(val, 1));
        def.id = readText(allocator, rx.rx_tuple_get(val, 2));
    } else if (std.mem.eql(u8, def.kind, "button")) {
        // (tuple "button" <label> <click_id>)
        def.text = readText(allocator, rx.rx_tuple_get(val, 1));
        def.id = readText(allocator, rx.rx_tuple_get(val, 2));
    } else if (std.mem.eql(u8, def.kind, "vbox") or std.mem.eql(u8, def.kind, "hbox")) {
        var i: u32 = 1;
        while (i < rx.rx_tuple_len(val)) : (i += 1) {
            if (parse_widget(allocator, rx.rx_tuple_get(val, i))) |child|
                def.children.append(allocator, child) catch {};
        }
    }
    return def;
}

// ── GTK construction ────────────────────────────────────────────────────────

const GTK_ORIENTATION_VERTICAL = 1;

export fn on_button_clicked(btn: *gtk.GtkButton, user_data: gtk.gpointer) callconv(.c) void {
    _ = btn;
    const id_ptr: [*c]const u8 = @ptrCast(user_data);
    const id_str = std.mem.span(id_ptr);

    if (global_sched) |sched| {
        const type_str = "click";
        const v_type = rx.rx_make_string(sched, type_str.ptr, type_str.len);

        // Send integer if parseable so calc.rxt can do arithmetic directly.
        const v_id = if (std.fmt.parseInt(i64, id_str, 10)) |n|
            rx.rx_make_int(n)
        else |_|
            rx.rx_make_string(sched, id_str.ptr, id_str.len);

        var elements = [_]rx.rx_value_t{ v_type, v_id };
        rx.rx_port_send_external(sched, target_actor, rx.rx_make_tuple(sched, &elements[0], 2));
    }
}

fn toSentinel(buf: []u8, s: []const u8) [*:0]const u8 {
    const len = @min(s.len, buf.len - 1);
    @memcpy(buf[0..len], s[0..len]);
    buf[len] = 0;
    return @ptrCast(buf.ptr);
}

fn build_gtk_widget(allocator: std.mem.Allocator, def: *WidgetDef) ?*gtk.GtkWidget {
    var buf: [1024]u8 = undefined;

    if (std.mem.eql(u8, def.kind, "label")) {
        const text = def.text orelse "";
        const lbl = gtk.gtk_label_new(toSentinel(&buf, text));
        gtk.gtk_widget_set_halign(lbl, 2); // GTK_ALIGN_END
        // Register named labels so `update` can reach them in O(1).
        if (def.id) |id| {
            widget_registry.put(allocator, id, lbl) catch {};
        }
        return lbl;
    } else if (std.mem.eql(u8, def.kind, "button")) {
        const text = def.text orelse "";
        const btn = gtk.gtk_button_new_with_label(toSentinel(&buf, text));
        if (def.id) |id| {
            const id_c = std.heap.c_allocator.dupeZ(u8, id) catch return btn;
            gtk.connect_data(btn, "clicked", &on_button_clicked, @ptrCast(id_c.ptr));
        }
        return btn;
    } else if (std.mem.eql(u8, def.kind, "vbox") or std.mem.eql(u8, def.kind, "hbox")) {
        const orientation: c_int = if (std.mem.eql(u8, def.kind, "vbox")) GTK_ORIENTATION_VERTICAL else 0;
        const box_w = gtk.gtk_box_new(orientation, 5);
        for (def.children.items) |child|
            if (build_gtk_widget(allocator, child)) |cw| gtk.gtk_box_append(box_w, cw);
        return box_w;
    }
    return null;
}

// ── Idle callbacks (always run on the GTK event-loop thread) ────────────────

const DrawPayload = struct { layout: *WidgetDef };
const UpdatePayload = struct { widget_id: [:0]const u8, text: [:0]const u8 };

export fn idle_draw(user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
    const payload: *DrawPayload = @ptrCast(@alignCast(user_data));
    defer std.heap.c_allocator.destroy(payload);

    if (global_window) |win| {
        widget_registry.clearRetainingCapacity();
        if (build_gtk_widget(std.heap.c_allocator, payload.layout)) |content| {
            gtk.gtk_window_set_child(@ptrCast(win), content);
            gtk.gtk_window_present(@ptrCast(win));
        }
    }
    return 0; // remove from idle list
}

export fn idle_update(user_data: gtk.gpointer) callconv(.c) gtk.gboolean {
    const payload: *UpdatePayload = @ptrCast(@alignCast(user_data));
    defer {
        std.heap.c_allocator.free(payload.widget_id);
        std.heap.c_allocator.free(payload.text);
        std.heap.c_allocator.destroy(payload);
    }

    if (widget_registry.get(payload.widget_id)) |widget| {
        gtk.gtk_label_set_text(@ptrCast(widget), payload.text.ptr);
    }
    return 0;
}

// ── Message handler (runs on VM scheduler thread) ───────────────────────────

pub export fn ui_handler_func(ctx: ?*anyopaque, msg: rx.rx_value_t, sched: ?*rx.rx_scheduler_t) callconv(.c) void {
    _ = ctx;
    _ = sched;

    if (rx.rx_tuple_len(msg) == 0) return;
    const cmd = rx.rx_tuple_get(msg, 0);
    if (!rx.rx_is_string(cmd)) return;
    const cmd_str = rx.rx_string_data(cmd)[0..rx.rx_string_len(cmd)];

    if (std.mem.eql(u8, cmd_str, "draw")) {
        // (tuple "draw" <layout> <me>)
        target_actor = @intCast(rx.rx_get_int(rx.rx_tuple_get(msg, 2)));
        if (parse_widget(std.heap.c_allocator, rx.rx_tuple_get(msg, 1))) |layout| {
            const p = std.heap.c_allocator.create(DrawPayload) catch return;
            p.* = .{ .layout = layout };
            _ = gtk.g_idle_add(@ptrCast(&idle_draw), @ptrCast(p));
        }
    } else if (std.mem.eql(u8, cmd_str, "update")) {
        // (tuple "update" <widget_id_string> <new_text_or_int>)
        const id_val = rx.rx_tuple_get(msg, 1);
        const text_val = rx.rx_tuple_get(msg, 2);
        if (!rx.rx_is_string(id_val)) return;

        const id_raw = rx.rx_string_data(id_val)[0..rx.rx_string_len(id_val)];
        const id_z = std.heap.c_allocator.dupeZ(u8, id_raw) catch return;

        var text_buf: [64]u8 = undefined;
        const text_s: []const u8 = if (rx.rx_is_string(text_val))
            rx.rx_string_data(text_val)[0..rx.rx_string_len(text_val)]
        else if (rx.rx_is_int(text_val))
            std.fmt.bufPrint(&text_buf, "{d}", .{rx.rx_get_int(text_val)}) catch "?"
        else
            "?";

        const text_z = std.heap.c_allocator.dupeZ(u8, text_s) catch {
            std.heap.c_allocator.free(id_z);
            return;
        };

        const p = std.heap.c_allocator.create(UpdatePayload) catch {
            std.heap.c_allocator.free(id_z);
            std.heap.c_allocator.free(text_z);
            return;
        };
        p.* = .{ .widget_id = id_z, .text = text_z };
        _ = gtk.g_idle_add(@ptrCast(&idle_update), @ptrCast(p));
    }
}

pub export fn rx_load(sched: ?*rx.rx_scheduler_t) callconv(.c) void {
    global_sched = sched;

    const t = std.Thread.spawn(.{}, gtk_thread_main, .{}) catch return;
    t.detach();

    const actor_id = rx.rx_spawn_port(sched, null, ui_handler_func, null);
    rx.rx_register_port(sched, "ui", actor_id);
}
