const std = @import("std");
const engine = @import("engine.zig");
const rx = engine.rx;
const c = engine.c;

// Helper to safely parse colors.
pub fn parseColor(val: rx.rx_value_t) engine.Color {
    if (rx.rx_is_atom(val) or rx.rx_is_string(val)) {
        if (rx.rx_val_eq_str(val, "red")) return .{ .r = 255, .g = 0, .b = 0, .a = 255 };
        if (rx.rx_val_eq_str(val, "green")) return .{ .r = 0, .g = 255, .b = 0, .a = 255 };
        if (rx.rx_val_eq_str(val, "blue")) return .{ .r = 0, .g = 0, .b = 255, .a = 255 };
        if (rx.rx_val_eq_str(val, "black")) return .{ .r = 0, .g = 0, .b = 0, .a = 255 };
        if (rx.rx_val_eq_str(val, "white")) return .{ .r = 255, .g = 255, .b = 255, .a = 255 };
        if (rx.rx_val_eq_str(val, "yellow")) return .{ .r = 255, .g = 255, .b = 0, .a = 255 };
        if (rx.rx_val_eq_str(val, "cyan")) return .{ .r = 0, .g = 255, .b = 255, .a = 255 };
        if (rx.rx_val_eq_str(val, "magenta")) return .{ .r = 255, .g = 0, .b = 255, .a = 255 };
    } else if (rx.rx_tuple_len(val) >= 3) {
        return .{
            .r = @intCast(@max(0, @min(255, rx.rx_get_int(rx.rx_tuple_get(val, 0))))),
            .g = @intCast(@max(0, @min(255, rx.rx_get_int(rx.rx_tuple_get(val, 1))))),
            .b = @intCast(@max(0, @min(255, rx.rx_get_int(rx.rx_tuple_get(val, 2))))),
            .a = 255,
        };
    }
    return .{ .r = 255, .g = 255, .b = 255, .a = 255 };
}

pub fn getNum(val: rx.rx_value_t) f32 {
    if (rx.rx_is_int(val)) {
        return @floatFromInt(rx.rx_get_int(val));
    }
    return 0.0;
}

pub fn getBool(val: rx.rx_value_t) bool {
    if (rx.rx_is_bool(val)) {
        return rx.rx_get_bool(val);
    }
    if (rx.rx_is_int(val)) {
        return rx.rx_get_int(val) != 0;
    }
    return false;
}

// Generates a u32 hash ID from an Rx atom for fast constant lookup and safe Rx integers.
pub fn getAtomHash(val: rx.rx_value_t) ?u32 {
    if (!rx.rx_is_atom(val)) return null;
    const len = rx.rx_atom_len(val);
    if (len == 0) return null;
    const ptr = rx.rx_atom_data(val);
    return @truncate(std.hash.Wyhash.hash(0, ptr[0..len]));
}

// Parses Rx IPC messages into Mutex-guarded Engine API calls
pub fn handle_message(eng: *engine.Engine, msg: rx.rx_value_t) void {
    if (rx.rx_tuple_len(msg) == 0) return;

    var x: f64 = 0;
    var y: f64 = 0;
    var z: f64 = 0;
    var sender: i64 = 0;
    var atom_ptr: [*c]const u8 = undefined;
    const cmd = rx.rx_tuple_get(msg, 0);

    if (rx.rx_match_tuple(msg, "camera", "fff", &x, &y, &z)) {
        if (eng.mutex) |m| {
            _ = c.SDL_LockMutex(m);
            defer _ = c.SDL_UnlockMutex(m);
            eng.camera_x = @floatCast(x);
            eng.camera_y = @floatCast(y);
            eng.camera_zoom = @floatCast(z);
        }
        return;
    }

    if (rx.rx_match_tuple(msg, "shake", "f", &x)) {
        if (eng.mutex) |m| {
            _ = c.SDL_LockMutex(m);
            defer _ = c.SDL_UnlockMutex(m);
            eng.camera_shake = @floatCast(x);
        }
        return;
    }

    if (rx.rx_match_tuple(msg, "rm", "i", &sender)) {
        if (eng.mutex) |m| {
            _ = c.SDL_LockMutex(m);
            defer _ = c.SDL_UnlockMutex(m);
            eng.removeEntity(@intCast(sender));
        }
        return;
    }

    if (rx.rx_val_eq_str(cmd, "subscribe")) {
        // (subscribe kind pid) - length is 3
        if (rx.rx_tuple_len(msg) >= 3) {
            const topic = rx.rx_tuple_get(msg, 1);
            const sub_pid = rx.rx_get_int(rx.rx_tuple_get(msg, 2));

            if (rx.rx_val_eq_str(topic, "input")) {
                if (eng.mutex) |m| {
                    _ = c.SDL_LockMutex(m);
                    defer _ = c.SDL_UnlockMutex(m);
                    eng.input_subscribers.append(eng.allocator, @intCast(sub_pid)) catch {};
                }
            }
        }
        return;
    }

    if (rx.rx_match_tuple(msg, "transform", "iff", &sender, &x, &y)) {
        const id: u32 = @intCast(sender);
        if (eng.mutex) |m| {
            _ = c.SDL_LockMutex(m);
            defer _ = c.SDL_UnlockMutex(m);
            if (eng.getEntityIndex(id)) |idx| {
                eng.scene.items(.x)[idx] = @floatCast(x);
                eng.scene.items(.y)[idx] = @floatCast(y);
            }
        }
        return;
    }

    if (rx.rx_match_tuple(msg, "physics", "iff", &sender, &x, &y)) {
        const id: u32 = @intCast(sender);
        if (eng.mutex) |m| {
            _ = c.SDL_LockMutex(m);
            defer _ = c.SDL_UnlockMutex(m);
            if (eng.getEntityIndex(id)) |idx| {
                eng.scene.items(.vx)[idx] = @floatCast(x);
                eng.scene.items(.vy)[idx] = @floatCast(y);
            }
        }
        return;
    }

    // Register / Spawn
    if (rx.rx_val_eq_str(cmd, "register")) {
        if (rx.rx_tuple_len(msg) >= 8) {
            const id_val = rx.rx_tuple_get(msg, 1);
            const id: u32 = @intCast(rx.rx_get_int(id_val));
            const kind_val = rx.rx_tuple_get(msg, 2);

            if (rx.rx_val_eq_str(kind_val, "rect")) {
                if (eng.mutex) |m| {
                    _ = c.SDL_LockMutex(m);
                    defer _ = c.SDL_UnlockMutex(m);
                    eng.removeEntity(id);

                    eng.scene.append(eng.allocator, .{
                        .id = id,
                        .kind = .rect,
                        .x = getNum(rx.rx_tuple_get(msg, 3)),
                        .y = getNum(rx.rx_tuple_get(msg, 4)),
                        .w = getNum(rx.rx_tuple_get(msg, 5)),
                        .h = getNum(rx.rx_tuple_get(msg, 6)),
                        .color = parseColor(rx.rx_tuple_get(msg, 7)),
                        .vx = 0,
                        .vy = 0,
                        .has_hitbox = if (rx.rx_tuple_len(msg) > 8) getBool(rx.rx_tuple_get(msg, 8)) else false,
                        .asset_id = 0,
                    }) catch return;

                    eng.id_map.put(id, eng.scene.len - 1) catch return;
                }
            } else if (rx.rx_val_eq_str(kind_val, "sprite")) {
                const asset_id = getAtomHash(rx.rx_tuple_get(msg, 3)) orelse return;
                if (eng.mutex) |m| {
                    _ = c.SDL_LockMutex(m);
                    defer _ = c.SDL_UnlockMutex(m);
                    eng.removeEntity(id);

                    eng.scene.append(eng.allocator, .{
                        .id = id,
                        .kind = .sprite,
                        .x = getNum(rx.rx_tuple_get(msg, 4)),
                        .y = getNum(rx.rx_tuple_get(msg, 5)),
                        .w = getNum(rx.rx_tuple_get(msg, 6)),
                        .h = getNum(rx.rx_tuple_get(msg, 7)),
                        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
                        .vx = 0,
                        .vy = 0,
                        .has_hitbox = if (rx.rx_tuple_len(msg) > 8) getBool(rx.rx_tuple_get(msg, 8)) else false,
                        .asset_id = asset_id,
                    }) catch return;

                    eng.id_map.put(id, eng.scene.len - 1) catch return;
                }
            }
        }
    } else if (rx.rx_val_eq_str(cmd, "load_bmp")) {
        if (rx.rx_match_tuple(msg, "load_bmp", "as", &atom_ptr, &atom_ptr)) { // Reuse atom_ptr for path
            const asset_id = getAtomHash(rx.rx_tuple_get(msg, 1)) orelse return;
            const path_ptr = rx.rx_string_data(rx.rx_tuple_get(msg, 2)) orelse return;
            const path_len = rx.rx_string_len(rx.rx_tuple_get(msg, 2));

            var buf: [1024]u8 = undefined;
            if (path_len >= buf.len) return;
            @memcpy(buf[0..path_len], path_ptr[0..path_len]);
            buf[path_len] = 0;

            if (eng.mutex) |m| {
                _ = c.SDL_LockMutex(m);
                defer _ = c.SDL_UnlockMutex(m);

                const surface = c.SDL_LoadBMP(@ptrCast(&buf));
                if (surface != null) {
                    if (eng.renderer) |renderer| {
                        const texture = c.SDL_CreateTextureFromSurface(renderer, surface);
                        if (texture != null) {
                            eng.textures.put(asset_id, texture.?) catch {};
                        }
                    }
                    c.SDL_DestroySurface(surface);
                }
            }
        }
    }
}
