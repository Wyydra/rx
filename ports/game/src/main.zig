const std = @import("std");
const engine = @import("engine.zig");
const rx = engine.rx;
const parse = @import("parse.zig");
const render = @import("render.zig");

pub export fn game_handler_func(ctx_ptr: ?*anyopaque, msg: rx.rx_value_t, sched: ?*rx.rx_scheduler_t) callconv(.c) void {
    const eng: *engine.Engine = @ptrCast(@alignCast(ctx_ptr orelse return));
    _ = sched;

    parse.handle_message(eng, msg);
}

pub export fn game_deinit(ctx_ptr: ?*anyopaque) callconv(.c) void {
    const eng: *engine.Engine = @ptrCast(@alignCast(ctx_ptr orelse return));
    eng.deinit();
}

pub export fn rx_load(sched_ptr: ?*rx.rx_scheduler_t) callconv(.c) void {
    const sched = sched_ptr orelse return;
    const allocator = std.heap.c_allocator;

    const eng = engine.Engine.init(allocator, sched) catch return;

    eng.thread = std.Thread.spawn(.{}, render.sdl_thread_main, .{eng}) catch {
        allocator.destroy(eng);
        return;
    };

    const actor_id = rx.rx_spawn_port_async(sched, eng, game_handler_func, game_deinit);
    rx.rx_register_port(sched, "game", actor_id);
}
