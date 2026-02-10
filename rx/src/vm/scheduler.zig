const std = @import("std");
const Cpu = @import("cpu.zig");
const Process = @import("process.zig").Process;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Value = @import("../memory/value.zig").Value;
const Receiver = @import("interface.zig").Receiver;
const DoublyLinkedList = std.DoublyLinkedList;
const ActorId = @import("actor.zig").ActorId;
const System = @import("system.zig").System;

pub const Scheduler = struct {
    registry: std.AutoHashMap(ActorId, Receiver),
    run_queue: DoublyLinkedList,
    waiting_queue: DoublyLinkedList,

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
        self.registry.deinit();
    }

    pub fn spawn(self: *Scheduler, main_closure: *HeapObject) !ActorId {
        const pid = self.nextId();

        const proc = try Process.init(self.allocator, pid, main_closure);
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
            std.debug.print("Routing to remote scheduler {d}...\n", .{target.scheduler_id});
            return;
        }
        if (self.registry.get(target)) |receiver| {
            const wake = receiver.send(msg);

            if (wake) {
                // might crash
                const proc = @as(*Process, @ptrCast(@alignCast(receiver.ptr)));

                self.waiting_queue.remove(&proc.node);

                self.run_queue.append(&proc.node);

                std.debug.print("Scheduler: Immediate Wakeup -> PID {f}\n", .{proc.pid});
            }
        } else {
            std.debug.print("DROP: ID {f} not found", .{target});
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
                    std.log.info("Process {f} Terminated normally.", .{process.pid});
                    process.deinit();
                },

                .waiting => {
                    std.log.info("Process {f} Blocked (Reason: {d}).", .{ process.pid, result.payload });
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
