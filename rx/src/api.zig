const std = @import("std");
const p = @import("vm/port.zig");
const value = @import("memory/value.zig");
const Value = value.Value;
const Mailbox = @import("vm/mailbox.zig").Mailbox;
const String = @import("memory/string.zig");
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
    port.mailbox.deinit();
    allocator.destroy(port);
}

const RxArena = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
};

export fn rx_get_allocator(sched_ptr: *anyopaque) callconv(.c) *std.mem.Allocator {
    const sched: *Scheduler = @ptrCast(@alignCast(sched_ptr));
    return &sched.allocator;
}

export fn rx_arena_new(sched_ptr: *anyopaque) callconv(.c) *RxArena {
    const sched: *Scheduler = @ptrCast(@alignCast(sched_ptr));
    const arena_ptr = sched.allocator.create(RxArena) catch @panic("OOM");
    arena_ptr.* = .{
        .arena = std.heap.ArenaAllocator.init(sched.allocator),
        .allocator = undefined,
    };
    arena_ptr.allocator = arena_ptr.arena.allocator();
    return arena_ptr;
}

export fn rx_arena_free(arena: *RxArena) callconv(.c) void {
    const parent_allocator = arena.arena.child_allocator;
    arena.arena.deinit();
    parent_allocator.destroy(arena);
}

export fn rx_arena_get_allocator(arena: *RxArena) callconv(.c) *std.mem.Allocator {
    return &arena.allocator;
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
    sched.system.trackResource(@ptrCast(port), destroyPort) catch {
        sched.allocator.destroy(port);
        return 0;
    };

    const pid = sched.spawnReceiver(p.asReceiver(port)) catch return 0;
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
    const mailbox = Mailbox.init(sched.allocator, sched.io) catch {
        sched.allocator.destroy(port);
        return 0;
    };
    port.* = .{ .context = ctx, .handler = handler, .deinit = deinit, .mailbox = mailbox };

    // Register the port for cleanup on scheduler deinit.
    sched.system.ports.append(sched.allocator, port) catch {
        port.mailbox.deinit();
        sched.allocator.destroy(port);
        return 0;
    };

    const pid = sched.spawnReceiver(p.asAsyncReceiver(port)) catch {
        _ = sched.system.ports.pop();
        port.mailbox.deinit();
        sched.allocator.destroy(port);
        return 0;
    };

    // Spawn the background port processing loop concurrently
    sched.port_group.async(sched.io, p.asyncPortLoop, .{ port, sched });

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

    sched.send(ActorId.fromInt(target_id), msg);
    sched.io_event.set(sched.io); // Always wake up in case VM was sleeping
}

export fn rx_value_free(alloc: *std.mem.Allocator, v: Value) callconv(.c) void {
    value.freeValue(alloc.*, v);
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
export fn rx_make_string(alloc: *std.mem.Allocator, chars: [*]const u8, len: usize) callconv(.c) Value {
    const obj = String.alloc(alloc.*, .string, chars[0..len]) catch return Value.nil();
    return Value.pointer(obj);
}
export fn rx_make_atom(alloc: *std.mem.Allocator, chars: [*]const u8, len: usize) callconv(.c) Value {
    const obj = String.alloc(alloc.*, .atom, chars[0..len]) catch return Value.nil();
    return Value.atom(obj);
}
export fn rx_make_tuple(alloc: *std.mem.Allocator, elements: [*]const Value, len: usize) callconv(.c) Value {
    const obj = Tuple.alloc(alloc.*, elements[0..len]) catch return Value.nil();
    return Value.pointer(obj);
}

export fn rx_is_nil(v: Value) callconv(.c) bool {
    return v.is(.nil);
}
export fn rx_is_bool(v: Value) callconv(.c) bool {
    return v.is(.boolean);
}
export fn rx_is_int(v: Value) callconv(.c) bool {
    return v.is(.integer);
}
export fn rx_is_pointer(v: Value) callconv(.c) bool {
    return v.is(.pointer) or v.is(.atom);
}
export fn rx_is_string(v: Value) callconv(.c) bool {
    return v.isString();
}
export fn rx_is_atom(v: Value) callconv(.c) bool {
    return v.is(.atom);
}

/// Polymorphic data/length for string or atom. Returns NULL/0 if not a string or atom.
export fn rx_val_cstr(v: Value) callconv(.c) ?[*]const u8 {
    if (!v.isHeapAllocated()) return null;
    const obj = v.asPtr() catch return null;
    return String.getChars(obj).ptr;
}

export fn rx_val_len(v: Value) callconv(.c) usize {
    if (!v.isHeapAllocated()) return 0;
    const obj = v.asPtr() catch return 0;
    return String.getChars(obj).len;
}

/// Polymorphic equality check for string or atom against a null-terminated C string.
export fn rx_val_eq_str(v: Value, s: [*:0]const u8) callconv(.c) bool {
    const v_data: []const u8 = if (v.isHeapAllocated()) blk: {
        const obj = v.asPtr() catch return false;
        if (obj.kind != .string and obj.kind != .atom) return false;
        break :blk String.getChars(obj);
    } else return false;

    const s_len = std.mem.len(s);
    return std.mem.eql(u8, v_data, s[0..s_len]);
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

export fn rx_atom_data(v: Value) callconv(.c) ?[*]const u8 {
    const s = v.asAtom() catch return null;
    return s.ptr;
}
export fn rx_atom_len(v: Value) callconv(.c) usize {
    const s = v.asAtom() catch return 0;
    return s.len;
}

export fn rx_tuple_len(v: Value) callconv(.c) u32 {
    const obj = v.asPtr() catch return 0;
    if (obj.kind != .tuple) return 0;
    return Tuple.getCount(obj);
}
export fn rx_tuple_get(v: Value, index: u32) callconv(.c) Value {
    const obj = v.asPtr() catch return Value.nil();
    if (obj.kind != .tuple) return Value.nil();
    if (index >= Tuple.getCount(obj)) return Value.nil();
    return Tuple.getValue(obj, index);
}

export fn rx_match_tuple(msg: Value, cmd_name: [*:0]const u8, fmt: [*:0]const u8, ...) callconv(.c) bool {
    const len = rx_tuple_len(msg);
    if (len == 0) return false;
    if (!rx_val_eq_str(rx_tuple_get(msg, 0), cmd_name)) return false;

    var args = @cVaStart();
    defer @cVaEnd(&args);

    var i: u32 = 0;
    while (fmt[i] != 0) : (i += 1) {
        // fmt[i] correlates to tuple element at index i + 1 (0 is the cmd name)
        if (i + 1 >= len) return false;
        const v = rx_tuple_get(msg, i + 1);

        switch (fmt[i]) {
            'i' => {
                if (!v.is(.integer)) return false;
                const ptr = @cVaArg(&args, *i64);
                ptr.* = v.asInteger() catch unreachable;
            },
            'b' => {
                if (!v.is(.boolean)) return false;
                const ptr = @cVaArg(&args, *bool);
                ptr.* = v.asBoolean() catch unreachable;
            },
            'f' => {
                // We allow integers to be matched as floats (f64) for ergonomics
                if (!v.is(.integer)) return false;
                const ptr = @cVaArg(&args, *f64);
                ptr.* = @floatFromInt(v.asInteger() catch unreachable);
            },
            's' => {
                if (!v.isString()) return false;
                const ptr = @cVaArg(&args, *?[*]const u8);
                const s = v.asString() catch unreachable;
                ptr.* = s.ptr;
            },
            'a' => {
                if (!v.is(.atom)) return false;
                const ptr = @cVaArg(&args, *?[*]const u8);
                const s = v.asAtom() catch unreachable;
                ptr.* = s.ptr;
            },
            'v' => {
                const ptr = @cVaArg(&args, *Value);
                ptr.* = v;
            },
            else => return false,
        }
    }

    return true;
}
