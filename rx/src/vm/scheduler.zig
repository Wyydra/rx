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

pub const ProcessQueue = struct {
    buf: []*Process,
    head: usize,
    tail: usize,
    count: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !ProcessQueue {
        return .{
            .buf = try allocator.alloc(*Process, capacity),
            .head = 0,
            .tail = 0,
            .count = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ProcessQueue) void {
        self.allocator.free(self.buf);
    }
    
    pub fn push(self: *ProcessQueue, value: *Process) !void {
        if (self.count == self.buf.len) {
            const new_cap = @max(self.buf.len * 2, 8);
            const new_buf = try self.allocator.alloc(*Process, new_cap);
            for (0..self.count) |i| new_buf[i] = self.buf[(self.head + i) % self.buf.len];
            self.allocator.free(self.buf);
            self.buf = new_buf;
            self.head = 0;
            self.tail = self.count;
        }
        self.buf[self.tail] = value;
        self.tail = (self.tail + 1) % self.buf.len;
        self.count += 1;
    }
    
    pub fn pop(self: *ProcessQueue) ?*Process {
        if (self.count == 0) return null;
        const val = self.buf[self.head];
        self.head = (self.head + 1) % self.buf.len;
        self.count -= 1;
        return val;
    }
};

const Resource = struct {
    ptr: *anyopaque,
    destroyFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
};

const AsyncPort = @import("port.zig").AsyncPort;
const Plugin = @import("loader.zig").Plugin;

pub const Scheduler = struct {
    registry: std.AutoHashMap(ActorId, Receiver),
    run_queue: ProcessQueue,
    waiting_queue: DoublyLinkedList,

    mutex: std.Io.Mutex,

    allocator: std.mem.Allocator,
    system: *System,
    io: std.Io,
    io_event: std.Io.Event,
    port_group: std.Io.Group,

    // Generator state
    id: u8,
    local_counter: u24,

    const REDUCTION_LIMIT = 2000;

    pub fn init(allocator: std.mem.Allocator, id: u8, system: *System, io: std.Io) Scheduler {
        return .{
            .registry = .init(allocator),
            .run_queue = ProcessQueue.init(allocator, 1024) catch unreachable,
            .waiting_queue = .{},
            .mutex = std.Io.Mutex.init,
            .allocator = allocator,
            .system = system,
            .io = io,
            .io_event = .unset,
            .port_group = .init,
            .id = id,
            .local_counter = 0,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        while (self.run_queue.pop()) |proc| {
            proc.deinit(self);
        }
        self.run_queue.deinit();
        while (self.waiting_queue.popFirst()) |node| {
            const proc: *Process = @fieldParentPtr("node", node);
            proc.deinit(self);
        }
        self.registry.deinit();
    }

    pub fn spawn(self: *Scheduler, main_func: *HeapObject, args: []const Value) !ActorId {
        const pid = self.nextId();

        const proc = try Process.init(self.allocator, self.io, pid, main_func, args);
        
        self.mutex.lockUncancelable(self.io);
        try self.registry.put(pid, proc.asReceiver());
        self.run_queue.push(proc) catch @panic("OOM in run_queue");
        self.mutex.unlock(self.io);

        return pid;
    }

    pub fn spawnReceiver(self: *Scheduler, receiver: Receiver) !ActorId {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const id = self.nextId();
        try self.registry.put(id, receiver);
        return id;
    }

    pub fn send(self: *Scheduler, target: ActorId, msg: Value) void {
        if (!target.isLocal(self.id)) {
            log.debug("Routing to remote scheduler {d}...\n", .{target.scheduler_id});
            return;
        }
        self.mutex.lockUncancelable(self.io);
        const receiver_opt = self.registry.get(target);
        self.mutex.unlock(self.io);

        if (receiver_opt) |receiver| {
            // Note: receiver.send will internally lock if needed (e.g. Process.push does its own lock and then calls sched lock to wake up)
            const wake = receiver.send(msg, self);

            if (wake) {
                // might crash
                const proc = @as(*Process, @ptrCast(@alignCast(receiver.ptr)));

                self.mutex.lockUncancelable(self.io);
                self.waiting_queue.remove(&proc.node);
                self.run_queue.push(proc) catch @panic("OOM in run_queue");
                self.mutex.unlock(self.io);

                self.io_event.set(self.io);

                log.debug("Scheduler: Immediate Wakeup -> PID {f}\n", .{proc.pid});
            }
        } else {
            log.debug("DROP: ID {f} not found", .{target});
        }
    }

    pub fn execute(self: *Scheduler) !void {
        while (true) {
            self.mutex.lockUncancelable(self.io);
            const process = self.run_queue.pop() orelse {
                if (self.waiting_queue.first != null) {
                    self.mutex.unlock(self.io);
                    try self.io_event.wait(self.io);
                    continue;
                }
                self.mutex.unlock(self.io);
                break; // idle
            };
            self.mutex.unlock(self.io);

            const result = Cpu.run(process, REDUCTION_LIMIT, self);

            switch (result.state) {
                .normal => {
                    self.mutex.lockUncancelable(self.io);
                    self.run_queue.push(process) catch @panic("OOM in run_queue");
                    self.mutex.unlock(self.io);
                },

                .terminated => {
                    std.log.debug("Process {f} Terminated normally.", .{process.pid});
                    self.mutex.lockUncancelable(self.io);
                    _ = self.registry.remove(process.pid);
                    self.mutex.unlock(self.io);
                    process.deinit(self);
                },

                .waiting => {
                    std.log.debug("Process {f} Blocked (Reason: {d}).", .{ process.pid, result.payload });
                    process.markWaiting();
                    self.mutex.lockUncancelable(self.io);
                    self.waiting_queue.append(&process.node);
                    self.mutex.unlock(self.io);
                },

                .error_state => {
                    // Crash
                    std.log.err("Process {f} Crashed! Error Code: {any}", .{ process.pid, result.getErrorCode() });
                    self.mutex.lockUncancelable(self.io);
                    _ = self.registry.remove(process.pid);
                    self.mutex.unlock(self.io);
                    process.deinit(self);
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
