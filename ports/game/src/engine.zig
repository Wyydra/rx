const std = @import("std");
pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub const rx = @cImport({
    @cInclude("rx_api.h");
});

pub const EntityType = enum {
    rect,
    sprite,
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

// Represents a single graphical object in the Scene Graph
pub const Entity = struct {
    id: u32,
    kind: EntityType,

    // Transform
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    // Physics / Movement
    vx: f32,
    vy: f32,
    has_hitbox: bool,

    // Rendering
    color: Color,
    asset_id: u64, // Used if Sprite
};

// Data-Oriented Design (SoA) for extreme iteration performance
pub const Scene = std.MultiArrayList(Entity);

pub const Engine = struct {
    allocator: std.mem.Allocator,
    sched: *rx.rx_scheduler_t,
    mutex: ?*c.SDL_Mutex = null,
    thread: std.Thread = undefined,

    running: bool = true,
    window: ?*c.SDL_Window = null,
    renderer: ?*c.SDL_Renderer = null,

    // Scene graph and lookup index
    scene: Scene = .{},
    id_map: std.AutoHashMap(u32, usize),

    // Loaded textures
    textures: std.AutoHashMap(u64, *c.SDL_Texture),

    camera_x: f32 = 0.0,
    camera_y: f32 = 0.0,
    camera_zoom: f32 = 1.0,
    camera_shake: f32 = 0.0,

    // Pub/Sub focus
    input_subscribers: std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator, sched: *rx.rx_scheduler_t) !*Engine {
        const self = try allocator.create(Engine);
        self.* = .{
            .allocator = allocator,
            .sched = sched,
            .scene = .{},
            .id_map = std.AutoHashMap(u32, usize).init(allocator),
            .textures = std.AutoHashMap(u64, *c.SDL_Texture).init(allocator),
            .input_subscribers = .{},
            .mutex = c.SDL_CreateMutex(),
        };
        return self;
    }

    pub fn deinit(self: *Engine) void {
        self.running = false;
        self.thread.join();

        if (self.mutex) |m| c.SDL_DestroyMutex(m);

        self.scene.deinit(self.allocator);
        self.id_map.deinit();
        self.input_subscribers.deinit(self.allocator);

        var it = self.textures.valueIterator();
        while (it.next()) |tex| {
            c.SDL_DestroyTexture(tex.*);
        }
        self.textures.deinit();

        self.allocator.destroy(self);
    }

    pub fn getEntityIndex(self: *Engine, id: u32) ?usize {
        return self.id_map.get(id);
    }

    pub fn removeEntity(self: *Engine, id: u32) void {
        if (self.id_map.get(id)) |index| {
            self.scene.swapRemove(index);
            _ = self.id_map.remove(id);
            // If swapRemove actually swapped elements, the element that was at the end
            // is now at `index`. We must update its mapping!
            if (index < self.scene.len) {
                const swapped_id = self.scene.items(.id)[index];
                self.id_map.put(swapped_id, index) catch {};
            }
        }
    }
};
