const std = @import("std");
const engine = @import("engine.zig");
const c = engine.c;
const input = @import("input.zig");
const physics = @import("physics.zig");

pub fn sdl_thread_main(eng: *engine.Engine) void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_Quit();

    if (eng.mutex == null) {
        std.debug.print("SDL_CreateMutex failed: {s}\n", .{c.SDL_GetError()});
        return;
    }

    eng.window = c.SDL_CreateWindow("Rx High-Perf GPU Engine", 800, 600, 0);
    if (eng.window == null) {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_DestroyWindow(eng.window);

    eng.renderer = c.SDL_CreateRenderer(eng.window, null);
    if (eng.renderer == null) {
        std.debug.print("SDL_CreateRenderer failed: {s}\n", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_DestroyRenderer(eng.renderer);

    var event: c.SDL_Event = undefined;
    var last_time = c.SDL_GetTicks();

    while (eng.running) {
        // 1. Poll Events
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                input.sendQuitEvent(eng);
                eng.running = false;
            } else if (event.type == c.SDL_EVENT_KEY_DOWN) {
                if (event.key.key == c.SDLK_ESCAPE) {
                    input.sendQuitEvent(eng);
                } else {
                    input.sendKeyEvent(eng, .key_down, event.key.key);
                }
            } else if (event.type == c.SDL_EVENT_KEY_UP) {
                input.sendKeyEvent(eng, .key_up, event.key.key);
            }
        }

        const current_time = c.SDL_GetTicks();
        const delta = current_time - last_time;

        if (delta > 0) {
            last_time = current_time;
            // Removed automatic :tick flood to prevent mailbox saturation.
            // Actors should use explicit timers if needed.
        }

        // Lock to step physics and render at the same time to prevent data races.
        // For 'turbo-performance' with thousands of entities, double buffering is better,
        // but locking once per 16ms frame for 1ms is perfectly fine for 2D.
        if (eng.mutex) |m| _ = c.SDL_LockMutex(m);

        const delta_f: f32 = @floatFromInt(delta);

        physics.stepPhysics(eng, delta_f);

        const len = eng.scene.len;
        const xs = eng.scene.items(.x);
        const ys = eng.scene.items(.y);
        const ws = eng.scene.items(.w);
        const hs = eng.scene.items(.h);

        // --- RENDER STEP ---
        _ = c.SDL_SetRenderDrawColor(eng.renderer, 20, 20, 30, 255);
        _ = c.SDL_RenderClear(eng.renderer);

        const kinds = eng.scene.items(.kind);
        const colors = eng.scene.items(.color);
        const asset_ids = eng.scene.items(.asset_id);
        var cx = eng.camera_x;
        var cy = eng.camera_y;
        const czoom = eng.camera_zoom;

        if (eng.camera_shake > 0.1) {
            const ticks: f32 = @floatFromInt(current_time);
            cx += @sin(ticks * 0.05) * eng.camera_shake;
            cy += @cos(ticks * 0.04) * eng.camera_shake;
            eng.camera_shake *= 0.9;
        }

        // Draw Loop (Cache local traversal thanks to MultiArrayList)
        for (0..len) |i| {
            // Apply Camera Transform
            const screen_x = (xs[i] - cx) * czoom;
            const screen_y = (ys[i] - cy) * czoom;
            const screen_w = ws[i] * czoom;
            const screen_h = hs[i] * czoom;

            if (kinds[i] == .rect) {
                const col = colors[i];
                _ = c.SDL_SetRenderDrawColor(eng.renderer, col.r, col.g, col.b, col.a);
                const sdl_rect = c.SDL_FRect{ .x = screen_x, .y = screen_y, .w = screen_w, .h = screen_h };
                _ = c.SDL_RenderFillRect(eng.renderer, &sdl_rect);
            } else if (kinds[i] == .sprite) {
                // If it's a sprite, try to get the texture
                if (eng.textures.get(asset_ids[i])) |tex| {
                    const sdl_rect = c.SDL_FRect{ .x = screen_x, .y = screen_y, .w = screen_w, .h = screen_h };
                    // For performance, we assume entire texture is rendered
                    _ = c.SDL_RenderTexture(eng.renderer, tex, null, &sdl_rect);
                } else {
                    // Fallback to magenta rect for missing textures
                    _ = c.SDL_SetRenderDrawColor(eng.renderer, 255, 0, 255, 255);
                    const sdl_rect = c.SDL_FRect{ .x = screen_x, .y = screen_y, .w = screen_w, .h = screen_h };
                    _ = c.SDL_RenderFillRect(eng.renderer, &sdl_rect);
                }
            }
        }

        if (eng.mutex) |m| _ = c.SDL_UnlockMutex(m);

        _ = c.SDL_RenderPresent(eng.renderer);

        // Cap to approx ~60FPS (16ms)
        c.SDL_Delay(16);
    }
}
