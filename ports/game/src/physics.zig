const std = @import("std");
const engine = @import("engine.zig");
const input = @import("input.zig");

pub fn checkOverlap(x1: f32, y1: f32, w1: f32, h1: f32, x2: f32, y2: f32, w2: f32, h2: f32) bool {
    const r1 = x1 + w1;
    const b1 = y1 + h1;
    const r2 = x2 + w2;
    const b2 = y2 + h2;
    return x1 < r2 and r1 > x2 and y1 < b2 and b1 > y2;
}

pub fn stepPhysics(eng: *engine.Engine, delta_f: f32) void {
    const xs = eng.scene.items(.x);
    const ys = eng.scene.items(.y);
    const ws = eng.scene.items(.w);
    const hs = eng.scene.items(.h);
    const vxs = eng.scene.items(.vx);
    const vys = eng.scene.items(.vy);
    const hitboxes = eng.scene.items(.has_hitbox);
    const ids = eng.scene.items(.id);

    const len = eng.scene.len;

    // Integration step
    for (0..len) |i| {
        xs[i] += vxs[i] * (delta_f / 1000.0);
        ys[i] += vys[i] * (delta_f / 1000.0);
    }

    // Collision Check (AABB)
    for (0..len) |i| {
        if (!hitboxes[i]) continue;
        for (i + 1..len) |j| {
            if (!hitboxes[j]) continue;

            if (checkOverlap(xs[i], ys[i], ws[i], hs[i], xs[j], ys[j], ws[j], hs[j])) {
                // Send collision event
                input.sendCollisionEvent(eng, ids[i], ids[j]);

                // Basic separation/bounce to prevent continuous firing and stuck entities
                // We push them slightly apart and zero/invert their velocities.
                const cx1 = xs[i] + ws[i]/2.0;
                const cy1 = ys[i] + hs[i]/2.0;
                const cx2 = xs[j] + ws[j]/2.0;
                const cy2 = ys[j] + hs[j]/2.0;

                const dx = cx1 - cx2;
                const dy = cy1 - cy2;
                
                // Separation based on centers
                if (@abs(dx) > @abs(dy)) {
                   if (dx > 0) { xs[i] += 2.0; xs[j] -= 2.0; } 
                   else { xs[i] -= 2.0; xs[j] += 2.0; }
                   vxs[i] = -vxs[i];
                   vxs[j] = -vxs[j];
                } else {
                   if (dy > 0) { ys[i] += 2.0; ys[j] -= 2.0; }
                   else { ys[i] -= 2.0; ys[j] += 2.0; }
                   vys[i] = -vys[i];
                   vys[j] = -vys[j];
                }
            }
        }
    }
}
