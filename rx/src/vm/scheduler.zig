const std = @import("std");
const Cpu = @import("cpu.zig");
const Process = @import("process.zig").Process;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Value = @import("../memory/value.zig").Value;
const Receiver = @import("interface.zig").Receiver;
const DoublyLinkedList = std.DoublyLinkedList;
const ActorId = @import("actor.zig").ActorId;
const System = @import("system.zig").System;
const log = std.log.scoped(.scheduler);

const Resource = struct {
    ptr: *anyopaque,
    destroyFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
};

pub const Scheduler = struct {
    registry: std.AutoHashMap(ActorId, Receiver),
    run_queue: DoublyLinkedList,
    waiting_queue: DoublyLinkedList,
    resources: std.ArrayListUnmanaged(Resource),

    allocator: std.mem.Allocator,
    system: *System,

    // Generator state
    id: u8,
    local_counter: u24,

    const REDUCTION_LIMIT = 2000;

    pub fn init(allocator: std.mem.Allocator, id: u8, system: *System) Scheduler {
        return .{
            .registry = .init(allocator),
            .run_queue = .{},
            .waiting_queue = .{},
            .resources = .empty,
            .allocator = allocator,
            .system = system,
            .id = id,
            .local_counter = 0,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        while (self.run_queue.popFirst()) |node| {
            const proc: *Process = @fieldParentPtr("node", node);
            proc.deinit();
        }
        while (self.waiting_queue.popFirst()) |node| {
            const proc: *Process = @fieldParentPtr("node", node);
            proc.deinit();
        }
        for (self.resources.items) |r| r.destroyFn(r.ptr, self.allocator);
        self.resources.deinit(self.allocator);
        self.registry.deinit();
    }

    pub fn trackResource(
        self: *Scheduler,
        ptr: *anyopaque,
        destroyFn: *const fn (*anyopaque, std.mem.Allocator) void,
    ) !void {
        try self.resources.append(self.allocator, .{ .ptr = ptr, .destroyFn = destroyFn });
    }

    pub fn spawn(self: *Scheduler, main_func: *HeapObject, args: []const Value) !ActorId {
        const pid = self.nextId();

        const proc = try Process.init(self.allocator, pid, main_func, args);
        try self.registry.put(pid, proc.asReceiver());
        self.run_queue.append(&proc.node);

        return pid;
    }

    pub fn spawnReceiver(self: *Scheduler, receiver: Receiver) !ActorId {
        const id = self.nextId();
        try self.registry.put(id, receiver);
        return id;
    }

    pub fn send(self: *Scheduler, target: ActorId, msg: Value) void {
        if (!target.isLocal(self.id)) {
            log.debug("Routing to remote scheduler {d}...\n", .{target.scheduler_id});
            return;
        }
        if (self.registry.get(target)) |receiver| {
            const wake = receiver.send(msg, self);

            if (wake) {
                // might crash
                const proc = @as(*Process, @ptrCast(@alignCast(receiver.ptr)));

                self.waiting_queue.remove(&proc.node);

                self.run_queue.append(&proc.node);

                log.debug("Scheduler: Immediate Wakeup -> PID {f}\n", .{proc.pid});
            }
        } else {
            log.debug("DROP: ID {f} not found", .{target});
        }
    }

    pub fn execute(self: *Scheduler) !void {
        while (true) {
            const node = self.run_queue.popFirst() orelse {
                if (self.waiting_queue.first != null) {
                    // TODO: consider save cpu here;
                    continue;
                }
                break; // idle
            };

            const process: *Process = @fieldParentPtr("node", node);

            const result = Cpu.run(process, REDUCTION_LIMIT, self);

            switch (result.state) {
                .normal => {
                    self.run_queue.append(node);
                },

                .terminated => {
                    std.log.debug("Process {f} Terminated normally.", .{process.pid});
                    process.deinit();
                },

                .waiting => {
                    std.log.debug("Process {f} Blocked (Reason: {d}).", .{ process.pid, result.payload });
                    process.markWaiting();
                    self.waiting_queue.append(node);
                },

                .error_state => {
                    // Crash
                    std.log.err("Process {f} Crashed! Error Code: {any}", .{ process.pid, result.getErrorCode() });
                    process.deinit();
                },
            }
        }
    }

    pub fn resolve(self: *Scheduler, name: []const u8) ?ActorId {
        return self.system.resolve(name);
    }

    fn nextId(self: *Scheduler) ActorId {
        self.local_counter += 1;
        return ActorId.init(self.id, self.local_counter);
    }
};
