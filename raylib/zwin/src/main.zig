const std = @import("std");
const rl = @import("raylib");
const c = @cImport(@cInclude("rx_api.h"));

// ─── Port context ─────────────────────────────────────────────────────────────

const WindowCtx = struct {
    mutex: std.Thread.Mutex = .{},
    text: [256:0]u8 = std.mem.zeroes([256:0]u8),
    text_len: usize = 0,

    /// Set to false by windowDeinit to stop the window loop.
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

    /// PID of the _start process. Window thread replies here when it closes.
    caller_pid: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    /// Scheduler handle for rx_port_send_external.
    sched: ?*anyopaque = null,

    /// True once the window thread has fully exited its render loop and
    /// acknowledged the teardown.  windowDeinit() SPINS on this until true,
    /// so that dlclose() cannot fire while libzwin.so code is still on-stack.
    thread_exited: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

var g_ctx: WindowCtx = .{};

// ─── Handler ──────────────────────────────────────────────────────────────────
//
// Protocol: caller sends (tuple self_pid "some text")
//           On window close, port sends nil back to self_pid.

fn windowHandler(ctx: ?*anyopaque, msg: c.rx_value_t, sched: ?*anyopaque) callconv(.c) void {
    const self: *WindowCtx = @ptrCast(@alignCast(ctx));
    self.sched = sched;

    if (c.rx_is_string(msg)) {
        updateText(self, msg);
    } else if (c.rx_tuple_len(msg) >= 2) {
        const pid_val = c.rx_tuple_get(msg, 0);
        const txt_val = c.rx_tuple_get(msg, 1);
        if (c.rx_is_int(pid_val))
            self.caller_pid.store(@intCast(c.rx_get_int(pid_val)), .release);
        if (c.rx_is_string(txt_val))
            updateText(self, txt_val);
    }
}

fn updateText(self: *WindowCtx, msg: c.rx_value_t) void {
    const ptr = c.rx_string_data(msg);
    const len = c.rx_string_len(msg);
    const safe_len = @min(len, self.text.len - 1);
    self.mutex.lock();
    defer self.mutex.unlock();
    @memcpy(self.text[0..safe_len], ptr[0..safe_len]);
    self.text[safe_len] = 0;
    self.text_len = safe_len;
}

fn windowDeinit(ctx: ?*anyopaque) callconv(.c) void {
    const self: *WindowCtx = @ptrCast(@alignCast(ctx));
    // Tell the window thread to stop.
    self.running.store(false, .release);
    // CRITICAL: spin here until the window thread has set thread_exited.
    // This runs inside destroyAsyncPort, which is called BEFORE dlclose().
    // If we return while libzwin.so code is still on the window thread's
    // stack, dlclose will unmap those pages and crash.
    while (!self.thread_exited.load(.acquire)) {
        std.Thread.sleep(1_000_000); // 1 ms
    }
}

// ─── Window thread ────────────────────────────────────────────────────────────

fn windowThread(ctx: *WindowCtx) void {
    const W = 800;
    const H = 450;
    const font_size = 28;

    rl.initWindow(W, H, "Rx Window Port");
    rl.setTargetFPS(60);

    var buf: [256:0]u8 = std.mem.zeroes([256:0]u8);
    var text_len: usize = 0;

    while (!rl.windowShouldClose() and ctx.running.load(.acquire)) {
        {
            ctx.mutex.lock();
            defer ctx.mutex.unlock();
            text_len = ctx.text_len;
            @memcpy(buf[0..text_len], ctx.text[0..text_len]);
            buf[text_len] = 0;
        }

        const text_slice: [:0]const u8 = buf[0..text_len :0];
        const text_w = rl.measureText(text_slice, font_size);
        const x = @divTrunc(W - text_w, 2);
        const y = @divTrunc(H - font_size, 2);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);
        rl.drawText(text_slice, x, y, font_size, .ray_white);
    }

    // All raylib cleanup must finish before we signal thread_exited,
    // because windowDeinit (and thus dlclose) waits on that flag.
    rl.closeWindow();

    // Notify the waiting _start process so it can unblock from recv.
    const caller = ctx.caller_pid.load(.acquire);
    if (caller != 0) {
        if (ctx.sched) |sched| {
            c.rx_port_send_external(sched, caller, c.rx_make_nil());
        }
    }

    // Signal that this thread has fully exited libzwin.so code.
    // windowDeinit will unblock and return, allowing the resource cleanup
    // (and subsequent dlclose) to proceed safely.
    ctx.thread_exited.store(true, .release);
}

// ─── Plugin entry point ───────────────────────────────────────────────────────

export fn rx_load(sched: ?*anyopaque) void {
    const t = std.Thread.spawn(.{}, windowThread, .{&g_ctx}) catch return;
    t.detach();

    const pid = c.rx_spawn_port_async(sched, &g_ctx, windowHandler, windowDeinit);
    if (pid != 0) c.rx_register_port(sched, "window", pid);
}
