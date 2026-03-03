const std = @import("std");
const Value = @import("memory/value.zig").Value;
const String = @import("memory/string.zig");
const Scheduler = @import("vm/scheduler.zig").Scheduler;
const ActorId = @import("vm/actor.zig").ActorId;

export fn rx_port_send(sched_ptr: *anyopaque, target_actor_id: u32, msg: Value) void {
    const sched = @as(*Scheduler, @ptrCast(@alignCast(sched_ptr)));
    const target = ActorId.fromInt(target_actor_id);
    sched.send(target, msg);
}

export fn rx_spawn_port(
    sched_ptr: *anyopaque,
    context: ?*anyopaque,
    handler: *const fn (ctx: ?*anyopaque, msg: Value, sched: ?*anyopaque) callconv(.c) void,
    cleanup: ?*const fn (ctx: ?*anyopaque) callconv(.c) void,
) u32 {
    const sched = @as(*Scheduler, @ptrCast(@alignCast(sched_ptr)));
    const id = sched.spawnPort(context, handler, cleanup) catch |err| {
        std.debug.print("Failed to spawn port: {any}\n", .{err});
        return 0; // Or better error handling, 0 == invalid actor ID usually?
    };
    return id.toInt();
}

export fn rx_make_nil() Value {
    return Value.nil();
}

export fn rx_make_bool(b: bool) Value {
    return Value.boolean(b);
}

export fn rx_make_int(val: i64) Value {
    return Value.integer(val);
}

export fn rx_string_data(val: Value) ?[*:0]const u8 {
    if (!val.isObject(.string)) return null;
    const obj = val.asObject();
    const ptr = String.getChars(obj);
    // string.zig ensures strings are null terminated.
    return @ptrCast(ptr.ptr);
}

export fn rx_string_len(val: Value) usize {
    if (!val.isObject(.string)) return 0;
    const obj = val.asObject();
    return String.getMeta(obj).len;
}

export fn rx_is_nil(val: Value) bool {
    return val.isNil();
}
export fn rx_is_bool(val: Value) bool {
    return val.isBoolean();
}
export fn rx_is_int(val: Value) bool {
    return val.isInteger();
}
export fn rx_is_pointer(val: Value) bool {
    return val.isPointer();
}
export fn rx_is_string(val: Value) bool {
    return val.isObject(.string);
}

export fn rx_get_bool(val: Value) bool {
    if (!val.isBoolean()) return false;
    return val.asBoolean();
}

export fn rx_get_int(val: Value) i64 {
    if (!val.isInteger()) return 0;
    return val.asInteger();
}
