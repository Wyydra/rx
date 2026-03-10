const std = @import("std");
const Value = @import("memory/value.zig").Value;
const Scheduler = @import("vm/scheduler.zig").Scheduler;
const ActorId = @import("vm/actor.zig").ActorId;
const Port = @import("vm/port.zig").Port;
const AsyncPort = @import("vm/port.zig").AsyncPort;
const HandlerFn = @import("vm/port.zig").HandlerFn;
const DeinitFn = @import("vm/port.zig").DeinitFn;
const Tuple = @import("memory/tuple.zig");

fn destroyPort(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const port: *Port = @ptrCast(@alignCast(ptr));
    if (port.deinit) |f| f(port.context); // call user cleanup if set
    allocator.destroy(port);
}

fn destroyAsyncPort(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const port: *AsyncPort = @ptrCast(@alignCast(ptr));
    if (port.deinit) |f| f(port.context); // call user cleanup if set
    allocator.free(port.mailbox.buffer);
    allocator.destroy(port);
}

export fn rx_spawn_port(
    sched_ptr: *anyopaque,
    ctx: ?*anyopaque,
    handler: HandlerFn,
    deinit: ?DeinitFn,
) callconv(.c) u32 {
    const sched: *Scheduler = @ptrCast(@alignCast(sched_ptr));
    const port = sched.allocator.create(Port) catch return 0;
    port.* = .{ .context = ctx, .handler = handler, .deinit = deinit };

    // Register the port for cleanup on scheduler deinit before trying to spawn it.
    sched.trackResource(@ptrCast(port), destroyPort) catch {
        sched.allocator.destroy(port);
        return 0;
    };

    const pid = sched.spawnReceiver(@import("vm/port.zig").asReceiver(port)) catch return 0;
    return pid.toInt();
}

export fn rx_spawn_port_async(
    sched_ptr: *anyopaque,
    ctx: ?*anyopaque,
    handler: HandlerFn,
    deinit: ?DeinitFn,
) callconv(.c) u32 {
    const sched: *Scheduler = @ptrCast(@alignCast(sched_ptr));
    const port = sched.allocator.create(AsyncPort) catch return 0;
    port.* = .{ .context = ctx, .handler = handler, .deinit = deinit, .mailbox = @import("vm/mailbox.zig").Mailbox.init(sched.allocator) catch {
        sched.allocator.destroy(port);
        return 0;
    } };

    // Register the port for cleanup on scheduler deinit.
    sched.ports.append(sched.allocator, port) catch {
        port.mailbox.deinit(sched.allocator, sched.io);
        sched.allocator.destroy(port);
        return 0;
    };

    const pid = sched.spawnReceiver(@import("vm/port.zig").asAsyncReceiver(port)) catch return 0;

    // Spawn the background port processing loop concurrently
    sched.port_group.async(sched.io, @import("vm/port.zig").asyncPortLoop, .{ port, sched });

    return pid.toInt();
}

export fn rx_register_port(
    sched_ptr: *anyopaque,
    name: [*:0]const u8,
    actor_id: u32,
) callconv(.c) void {
    const sched: *Scheduler = @ptrCast(@alignCast(sched_ptr));
    // System.register dupes the name
    sched.system.register(std.mem.span(name), ActorId.fromInt(actor_id)) catch {};
}

export fn rx_port_send_external(sched_ptr: *anyopaque, target_id: u32, msg: Value) callconv(.c) void {
    const sched: *Scheduler = @ptrCast(@alignCast(sched_ptr));

    if (sched.registry.get(ActorId.fromInt(target_id))) |receiver| {
        _ = receiver.sendFn(receiver.ptr, msg, sched);
        sched.io_event.set(sched.io); // Always wake up in case VM was sleeping
    } else {
        std.log.err("rx_port_send_external: Failed to find target ActorId {}", .{target_id});
    }
}

// Value constructors
export fn rx_make_nil() callconv(.c) Value {
    return Value.nil();
}
export fn rx_make_bool(b: bool) callconv(.c) Value {
    return Value.boolean(b);
}
export fn rx_make_int(v: i64) callconv(.c) Value {
    return Value.integer(v);
}

export fn rx_is_nil(v: Value) callconv(.c) bool {
    return v.isNil();
}
export fn rx_is_bool(v: Value) callconv(.c) bool {
    return v.isBoolean();
}
export fn rx_is_int(v: Value) callconv(.c) bool {
    return v.isInteger();
}
export fn rx_is_pointer(v: Value) callconv(.c) bool {
    return v.isPointer();
}
export fn rx_is_string(v: Value) callconv(.c) bool {
    return v.isString();
}

export fn rx_get_bool(v: Value) callconv(.c) bool {
    return v.asBoolean() catch false;
}
export fn rx_get_int(v: Value) callconv(.c) i64 {
    return v.asInteger() catch 0;
}

export fn rx_string_data(v: Value) callconv(.c) ?[*]const u8 {
    const s = v.asString() catch return null;
    return s.ptr;
}
export fn rx_string_len(v: Value) callconv(.c) usize {
    const s = v.asString() catch return 0;
    return s.len;
}

export fn rx_tuple_len(v: Value) callconv(.c) u32 {
    const obj = v.asPointer() catch return 0;
    if (obj.kind != .tuple) return 0;
    return Tuple.getCount(obj);
}
export fn rx_tuple_get(v: Value, index: u32) callconv(.c) Value {
    const obj = v.asPointer() catch return Value.nil();
    if (obj.kind != .tuple) return Value.nil();
    if (index >= Tuple.getCount(obj)) return Value.nil();
    return Tuple.getValue(obj, index);
}
