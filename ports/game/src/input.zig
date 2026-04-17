const std = @import("std");
const engine = @import("engine.zig");
const c = engine.c;
const rx = engine.rx;

pub fn sendKeyEvent(eng: *engine.Engine, event_type_atom: enum { key_down, key_up }, key: c.SDL_Keycode) void {
    const arena = rx.rx_arena_new(eng.sched);
    defer rx.rx_arena_free(arena);
    const alloc = rx.rx_arena_get_allocator(arena);

    const type_str = if (event_type_atom == .key_down) "key_down" else "key_up";
    const v_type = rx.rx_make_atom(alloc, type_str.ptr, type_str.len);

    var key_name = std.mem.span(c.SDL_GetKeyName(key));
    var buf: [64]u8 = undefined;
    const len = @min(key_name.len, buf.len);
    for (0..len) |i| {
        const ch = std.ascii.toLower(key_name[i]);
        buf[i] = if (ch == ' ') '_' else ch;
    }

    const v_key = rx.rx_make_atom(alloc, &buf, len);

    var elements = [_]rx.rx_value_t{ v_type, v_key };
    const msg = rx.rx_make_tuple(alloc, &elements[0], 2);

    // Broadcast to subscribers
    for (eng.input_subscribers.items) |sub| {
        rx.rx_port_send_external(eng.sched, sub, msg);
    }
}

// sendTickEvent removed.

pub fn sendQuitEvent(eng: *engine.Engine) void {
    const arena = rx.rx_arena_new(eng.sched);
    defer rx.rx_arena_free(arena);
    const alloc = rx.rx_arena_get_allocator(arena);

    const type_str = "quit";
    const v_type = rx.rx_make_atom(alloc, type_str.ptr, type_str.len);

    var elements = [_]rx.rx_value_t{ v_type, rx.rx_make_nil() };
    const msg = rx.rx_make_tuple(alloc, &elements[0], 2);

    for (eng.input_subscribers.items) |sub| {
        rx.rx_port_send_external(eng.sched, sub, msg);
    }
}

pub fn sendWallCollision(eng: *engine.Engine, target_id: u32) void {
    const arena = rx.rx_arena_new(eng.sched);
    defer rx.rx_arena_free(arena);
    const alloc = rx.rx_arena_get_allocator(arena);

    const type_str = "collide";
    const target_str = "wall";
    const v_type = rx.rx_make_atom(alloc, type_str.ptr, type_str.len);
    const v_target = rx.rx_make_atom(alloc, target_str.ptr, target_str.len);

    var elements = [_]rx.rx_value_t{ v_type, v_target };
    const msg = rx.rx_make_tuple(alloc, &elements[0], 2);

    rx.rx_port_send_external(eng.sched, target_id, msg);
}

pub fn sendCollisionEvent(eng: *engine.Engine, id1: u32, id2: u32) void {
    const arena = rx.rx_arena_new(eng.sched);
    defer rx.rx_arena_free(arena);
    const alloc = rx.rx_arena_get_allocator(arena);

    const type_str = "collide";
    const v_type = rx.rx_make_atom(alloc, type_str.ptr, type_str.len);

    // To Actor 1: (collide id2)
    {
        var elements = [_]rx.rx_value_t{ v_type, rx.rx_make_int(@as(i64, id2)) };
        const msg = rx.rx_make_tuple(alloc, &elements[0], 2);
        rx.rx_port_send_external(eng.sched, id1, msg);
    }

    // To Actor 2: (collide id1)
    {
        var elements = [_]rx.rx_value_t{ v_type, rx.rx_make_int(@as(i64, id1)) };
        const msg = rx.rx_make_tuple(alloc, &elements[0], 2);
        rx.rx_port_send_external(eng.sched, id2, msg);
    }
}
