const std = @import("std");
const engine = @import("engine.zig");
const c = engine.c;
const rx = engine.rx;

pub fn sendKeyEvent(eng: *engine.Engine, event_type_atom: enum { key_down, key_up }, key: c.SDL_Keycode) void {
    if (eng.target_actor == 0) return;

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
    rx.rx_port_send_external(eng.sched, eng.target_actor, msg);
}

pub fn sendTickEvent(eng: *engine.Engine, delta_ms: u64) void {
    if (eng.target_actor == 0) return;

    const arena = rx.rx_arena_new(eng.sched);
    defer rx.rx_arena_free(arena);
    const alloc = rx.rx_arena_get_allocator(arena);

    const type_str = "tick";
    const v_type = rx.rx_make_atom(alloc, type_str.ptr, type_str.len);
    const v_delta = rx.rx_make_int(@intCast(delta_ms));

    var elements = [_]rx.rx_value_t{ v_type, v_delta };
    const msg = rx.rx_make_tuple(alloc, &elements[0], 2);
    rx.rx_port_send_external(eng.sched, eng.target_actor, msg);
}

pub fn sendQuitEvent(eng: *engine.Engine) void {
    if (eng.target_actor == 0) return;

    const arena = rx.rx_arena_new(eng.sched);
    defer rx.rx_arena_free(arena);
    const alloc = rx.rx_arena_get_allocator(arena);

    const type_str = "quit";
    const v_type = rx.rx_make_atom(alloc, type_str.ptr, type_str.len);

    var elements = [_]rx.rx_value_t{ v_type, rx.rx_make_nil() };
    const msg = rx.rx_make_tuple(alloc, &elements[0], 2);
    rx.rx_port_send_external(eng.sched, eng.target_actor, msg);
}

pub fn sendCollisionEvent(eng: *engine.Engine, id1: u32, id2: u32) void {
    if (eng.target_actor == 0) return;
    
    const arena = rx.rx_arena_new(eng.sched);
    defer rx.rx_arena_free(arena);
    const alloc = rx.rx_arena_get_allocator(arena);

    const type_str = "collide";
    const v_type = rx.rx_make_atom(alloc, type_str.ptr, type_str.len);
    
    // We send back the hash ints. It would be better to retain the string, 
    // but the VM sent us Atoms. For simplicity, we just send integers back or format them.
    // Wait, the VM uses `eq` for atoms, which checks string content. 
    // Sending the numeric hash is OK if the VM scripts binds IDs to integers, or we cache the strings.
    // Let's send them as integers to keep it "turbo performant". The VM can check numeric IDs.
    const v_id1 = rx.rx_make_int(@as(i64, id1));
    const v_id2 = rx.rx_make_int(@as(i64, id2));

    var elements = [_]rx.rx_value_t{ v_type, v_id1, v_id2 };
    const msg = rx.rx_make_tuple(alloc, &elements[0], 3);
    rx.rx_port_send_external(eng.sched, eng.target_actor, msg);
}
