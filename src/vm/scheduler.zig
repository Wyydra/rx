const std = @import("std");
const Cpu = @import("cpu.zig");
const Process = @import("process.zig").Process;
const HeapObject = @import("../memory/value.zig").HeapObject;
const DoublyLinkedList = std.DoublyLinkedList;

pub const Scheduler = struct {

    run_queue: DoublyLinkedList,
    waiting_queue: DoublyLinkedList,

    allocator: std.mem.Allocator,

    const REDUCTION_LIMIT = 2000;

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{
            .run_queue = .{},
            .waiting_queue = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        while (self.run_queue.popFirst()) |node| {
            const proc: *Process = @fieldParentPtr("node", node);
            proc.deinit(self.allocator);
        }
        while (self.waiting_queue.popFirst()) |node| {
            const proc: *Process = @fieldParentPtr("node", node);
            proc.deinit(self.allocator);
        }
    }

    pub fn spawn(self: *Scheduler, main_closure: *HeapObject) !void {
        const proc = try Process.init(self.allocator, 0, main_closure);
        self.run_queue.append(&proc.node);
    }

    pub fn execute(self: *Scheduler, allocator: std.mem.Allocator) !void {
        while (true) {
            const node = self.run_queue.popFirst() orelse {
                if (self.waiting_queue.first != null) {
                    continue;
                }
                break; // idle
            };

            const process: *Process = @fieldParentPtr("node", node);

            const result = Cpu.run(process, REDUCTION_LIMIT);

            switch (result.state) {
                .normal => {
                    self.run_queue.append(node);
                },

                .terminated => {
                    std.log.info("Process {d} Terminated normally.", .{process.pid});
                    process.deinit(allocator);
                },

                .waiting => {
                    std.log.info("Process {d} Blocked (Reason: {d}).", .{ process.pid, result.payload });
                    self.waiting_queue.append(node);
                },

                .error_state => {
                    // Crash
                    std.log.err("Process {d} Crashed! Error Code: {d}", .{ process.pid, result.payload });
                    process.deinit(allocator);
                }
            }
        }
    }
};
