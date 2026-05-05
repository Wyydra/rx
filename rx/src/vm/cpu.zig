const std = @import("std");
const Process = @import("process.zig").Process;
const Closure = @import("../memory/closure.zig");
const Function = @import("../memory/function.zig");
const Tuple = @import("../memory/tuple.zig");
const Instruction = @import("../bytecode/opcode.zig").Instruction;
const Value = @import("../memory/value.zig").Value;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Object = @import("../memory/value.zig").Object;
const ActorId = @import("actor.zig").ActorId;

const log = std.log.scoped(.cpu);

// TODO: old struct remake it
pub const ExecutionResult = packed struct(u32) {
    state: State,
    cost_or_error: u6,
    payload: u24,

    pub const State = enum(u2) {
        normal = 0,
        waiting = 1,
        terminated = 2,
        error_state = 3,
    };

    pub const ErrorCode = enum(u6) {
        stack_underflow = 0,
        stack_overflow = 1,
        invalid_instruction = 2,
        register_out_of_bounds = 3,
        division_by_zero = 4,
        out_of_memory = 5,
        invalid_memory_access = 6,
        unknown_actor = 7,
        type_error = 8,
    };

    pub fn fromValueErr(v_err: Value.Error) ErrorCode {
        return switch (v_err) {
            error.TypeError => .type_error,
            error.DivisionByZero => .division_by_zero,
            error.IntegerOverflow => .type_error, // TODO
        };
    }

    pub const WaitReason = enum(u6) {
        io_read = 1,
        io_write = 2,
        message = 3,
        timer = 4,
        process = 5,
    };

    pub inline fn normal(cost: u8) ExecutionResult {
        return ExecutionResult{
            .state = .normal,
            .cost_or_error = @min(cost, 63),
            .payload = 0,
        };
    }

    pub inline fn terminated(exit_code: u8) ExecutionResult {
        return ExecutionResult{
            .state = .terminated,
            .cost_or_error = @min(exit_code, 63),
            .payload = 0,
        };
    }

    pub inline fn err(error_code: ExecutionResult.ErrorCode) ExecutionResult {
        return ExecutionResult{
            .state = .error_state,
            .cost_or_error = @intFromEnum(error_code),
            .payload = 0,
        };
    }

    pub inline fn waiting(reason: ExecutionResult.WaitReason, data: u24) ExecutionResult {
        return ExecutionResult{
            .state = .waiting,
            .cost_or_error = @intFromEnum(reason),
            .payload = data,
        };
    }

    pub inline fn isNormal(self: ExecutionResult) bool {
        return self.state == .normal;
    }

    pub inline fn isWaiting(self: ExecutionResult) bool {
        return self.state == .waiting;
    }

    pub inline fn isTerminated(self: ExecutionResult) bool {
        return self.state == .terminated;
    }

    pub inline fn isError(self: ExecutionResult) bool {
        return self.state == .error_state;
    }

    pub inline fn getCost(self: ExecutionResult) u8 {
        return self.cost_or_error;
    }

    pub inline fn getErrorCode(self: ExecutionResult) ExecutionResult.ErrorCode {
        return @enumFromInt(self.cost_or_error);
    }

    pub inline fn getWaitReason(self: ExecutionResult) ExecutionResult.WaitReason {
        return @enumFromInt(self.cost_or_error);
    }

    pub inline fn getPayload(self: ExecutionResult) u24 {
        return self.payload;
    }
};

pub const Environment = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        send: *const fn (ptr: *anyopaque, target: ActorId, msg: Value) void,
        spawn: *const fn (ptr: *anyopaque, func: *HeapObject, args: []const Value) anyerror!ActorId,
        resolve: *const fn (ptr: *anyopaque, name: []const u8) ?ActorId,
    };

    pub inline fn send(self: Environment, target: ActorId, msg: Value) void {
        self.vtable.send(self.ptr, target, msg);
    }

    pub inline fn spawn(self: Environment, func: *HeapObject, args: []const Value) anyerror!ActorId {
        return self.vtable.spawn(self.ptr, func, args);
    }

    pub inline fn resolve(self: Environment, name: []const u8) ?ActorId {
        return self.vtable.resolve(self.ptr, name);
    }
};

pub fn run(proc: *Process, limit: usize, env: Environment) ExecutionResult {
    var interpreter = Interpreter{
        .proc = proc,
        .env = env,
        .budget = limit,
        .limit = limit,
    };
    return interpreter.run();
}

const Interpreter = struct {
    const Self = @This();

    proc: *Process,
    env: Environment,
    budget: usize,
    limit: usize,

    // Cached state for performance
    ip: usize = 0,
    base: usize = 0,
    stack: []Value = undefined,
    frames: []@import("process.zig").CallFrame = undefined,
    frame_idx: usize = 0,
    constants: []const Value = undefined,
    code: []const u8 = undefined,

    pub fn run(self: *Self) ExecutionResult {
        self.stack = self.proc.stack.items;
        self.frames = self.proc.frames.items;
        self.frame_idx = self.frames.len - 1;
        self.ip = self.proc.saved_ip;
        self.syncFrame();

        while (self.budget > 0) {
            if (self.ip + 4 > self.code.len) {
                return ExecutionResult.terminated(0);
            }

            const instr = Instruction.decode(std.mem.readInt(u32, @ptrCast(self.code.ptr + self.ip), .little));
            self.ip += 4;

            const op = instr.getOpcode();
            self.dispatch(op, instr) catch |err| {
                if (err == error.Suspend) return ExecutionResult.waiting(.message, 0);
                return ExecutionResult.err(self.mapError(err));
            };

            const cost = op.reductionCost();
            self.budget = if (cost >= self.budget) 0 else self.budget - cost;

            // If the instruction terminated the process (RET from last frame)
            if (self.proc.frames.items.len == 0) return ExecutionResult.terminated(0);
        }

        self.proc.saved_ip = self.ip;
        const used = self.limit - self.budget;
        return ExecutionResult.normal(@intCast(@min(used, 255)));
    }

    fn syncFrame(self: *Self) void {
        const frame = &self.proc.frames.items[self.frame_idx];
        self.base = frame.base;
        const function = Closure.getFunction(frame.closure);
        self.code = Function.getCode(function);
        self.constants = Function.getConstants(function);
    }

    // --- Register Helpers ---
    inline fn getA(self: *Self, instr: Instruction) Value {
        return self.stack[self.base + instr.A];
    }
    inline fn getB(self: *Self, instr: Instruction) Value {
        return self.stack[self.base + instr.B];
    }
    inline fn getC(self: *Self, instr: Instruction) Value {
        return self.stack[self.base + instr.C];
    }
    inline fn getK(self: *Self, instr: Instruction) Value {
        return self.constants[instr.getBx()];
    }

    inline fn setA(self: *Self, instr: Instruction, val: Value) void {
        self.stack[self.base + instr.A] = val;
    }
    inline fn setB(self: *Self, instr: Instruction, val: Value) void {
        self.stack[self.base + instr.B] = val;
    }

    const RunError = Value.Error || error{
        StackUnderflow,
        InvalidInstruction,
        UnknownActor,
        OutOfMemory,
        Suspend,
    };

    fn mapError(self: *Self, err: RunError) ExecutionResult.ErrorCode {
        _ = self;
        return switch (err) {
            error.TypeError => .type_error,
            error.DivisionByZero => .division_by_zero,
            error.IntegerOverflow => .type_error,
            error.StackUnderflow => .stack_underflow,
            error.InvalidInstruction => .invalid_instruction,
            error.UnknownActor => .unknown_actor,
            error.OutOfMemory => .out_of_memory,
            error.Suspend => unreachable, // Handled outside
        };
    }

    fn dispatch(self: *Self, op: @import("../bytecode/opcode.zig").Opcode, instr: Instruction) RunError!void {
        switch (op) {
            .MOVE => self.setB(instr, self.getA(instr)),
            .LOADK => self.setA(instr, self.getK(instr)),
            .PRINT => std.debug.print("> {f}\n", .{self.getA(instr)}),

            .ADD => self.setA(instr, try self.getB(instr).add(self.getC(instr))),
            .SUB => self.setA(instr, try self.getB(instr).sub(self.getC(instr))),
            .MUL => self.setA(instr, try self.getB(instr).mul(self.getC(instr))),
            .DIV => self.setA(instr, try self.getB(instr).div(self.getC(instr))),

            .LT => self.setA(instr, Value.boolean(try self.getB(instr).lt(self.getC(instr)))),
            .GT => self.setA(instr, Value.boolean(try self.getB(instr).gt(self.getC(instr)))),
            .EQ => self.setA(instr, Value.boolean(self.getB(instr).equals(self.getC(instr)))),

            .SEND => try self.instrSend(instr),
            .RECV => try self.instrRecv(instr),
            .SELF => self.setA(instr, Value.integer(@intCast(self.proc.pid.toInt()))),
            .SPAWN => try self.instrSpawn(instr),

            .CLOSURE => try self.instrClosure(instr),
            .JMP => self.ip += instr.getBx(),
            .JF => if (!(try self.getA(instr).asBoolean())) {
                self.ip += instr.getBx();
            },

            .RET => try self.instrRet(instr),
            .CALL => try self.instrCall(instr),
            .TAILCALL => try self.instrTailCall(instr),

            .NEWTUPLE => try self.instrNewTuple(instr),
            .GETTUPLE => try self.instrGetTuple(instr),

            .JNTUP => try self.instrJntup(instr),
            .JNEQ => if (!self.getA(instr).equals(self.getB(instr))) {
                self.ip += @as(usize, instr.C) * 4;
            },
        }
    }

    // --- Individual Instruction Handlers ---

    fn instrSend(self: *Self, instr: Instruction) RunError!void {
        const id_val = self.getA(instr);
        const msg_val = self.getB(instr);

        const target = if (id_val.is(.integer)) blk: {
            break :blk ActorId.fromInt(@intCast(try id_val.asInteger()));
        } else if (id_val.isString() or id_val.is(.atom)) blk: {
            const name = if (id_val.isString()) try id_val.asString() else try id_val.asAtom();
            if (self.env.resolve(name)) |pid| {
                break :blk pid;
            } else return error.UnknownActor;
        } else return error.TypeError;

        self.env.send(target, msg_val);
    }

    fn instrRecv(self: *Self, instr: Instruction) RunError!void {
        if (self.proc.pop() catch null) |msg| {
            self.setA(instr, msg);
        } else {
            self.ip -= 4;
            self.proc.saved_ip = self.ip;
            return error.Suspend;
        }
    }

    fn instrSpawn(self: *Self, instr: Instruction) RunError!void {
        const closure_idx = self.base + instr.B;
        const closure_obj = try self.stack[closure_idx].asClosure();
        const func_obj = Closure.getFunction(closure_obj);
        const args = self.stack[closure_idx + 1 .. closure_idx + 1 + instr.C];
        const new_pid = self.env.spawn(func_obj, args) catch return error.OutOfMemory;
        self.setA(instr, Value.integer(@intCast(new_pid.toInt())));
    }

    fn instrClosure(self: *Self, instr: Instruction) RunError!void {
        const func_obj = try self.getK(instr).asFunction();
        const closure_obj = self.proc.alloc(.closure, @sizeOf(u64)) catch return error.OutOfMemory;
        const func_slot = @as(**HeapObject, @ptrCast(@alignCast(@as([*]u8, @ptrCast(closure_obj)) + @sizeOf(HeapObject))));
        func_slot.* = func_obj;
        self.setA(instr, Value.pointer(closure_obj));
    }

    fn instrRet(self: *Self, instr: Instruction) RunError!void {
        const result = self.getA(instr);
        const popped_frame = self.proc.frames.pop() orelse return error.StackUnderflow;
        if (self.proc.frames.items.len == 0) return;

        self.frame_idx -= 1;
        self.syncFrame();
        self.stack[popped_frame.base - 1] = result;
        self.ip = popped_frame.caller_ip;
    }

    fn instrCall(self: *Self, instr: Instruction) RunError!void {
        const closure_idx = self.base + instr.A;
        const closure_obj = try self.stack[closure_idx].asClosure();
        const new_base = closure_idx + 1;
        const callee_func = Closure.getFunction(closure_obj);

        try self.proc.ensureStack(new_base + Function.getMaxRegs(callee_func));
        self.stack = self.proc.stack.items;

        self.proc.frames.append(self.proc.allocator, .{
            .base = new_base,
            .caller_ip = self.ip,
            .closure = closure_obj,
        }) catch return error.OutOfMemory;

        self.frame_idx += 1;
        self.ip = 0;
        self.syncFrame();
    }

    fn instrTailCall(self: *Self, instr: Instruction) RunError!void {
        const closure_idx = self.base + instr.A;
        const closure_obj = try self.stack[closure_idx].asClosure();
        const args_count = instr.B;
        const callee_func = Closure.getFunction(closure_obj);

        try self.proc.ensureStack(self.base + Function.getMaxRegs(callee_func));
        self.stack = self.proc.stack.items;

        const src_start = closure_idx + 1;
        if (args_count > 0) {
            std.mem.copyForwards(Value, self.stack[self.base .. self.base + args_count], self.stack[src_start .. src_start + args_count]);
        }
        const max_regs = Function.getMaxRegs(callee_func);
        @memset(self.stack[self.base + args_count .. self.base + max_regs], Value.nil());

        const frame = &self.proc.frames.items[self.frame_idx];
        frame.closure = closure_obj;
        self.ip = 0;
        self.syncFrame();
    }

    fn instrNewTuple(self: *Self, instr: Instruction) RunError!void {
        const count = instr.B;
        const obj = self.proc.alloc(.tuple, count * @sizeOf(Value)) catch return error.OutOfMemory;
        const elems = Tuple.slice(obj);
        for (0..count) |i| elems[i] = self.stack[self.base + instr.A + 1 + i];
        self.setA(instr, Value.pointer(obj));
    }

    fn instrGetTuple(self: *Self, instr: Instruction) RunError!void {
        const target_obj = try self.getB(instr).asPtr();
        if (target_obj.kind != .tuple) return error.TypeError;
        const elems = Tuple.slice(target_obj);
        const idx = try self.getC(instr).asInteger();
        if (idx < 0 or idx >= elems.len) return error.InvalidInstruction;
        self.setA(instr, elems[@intCast(idx)]);
    }

    fn instrJntup(self: *Self, instr: Instruction) RunError!void {
        const val = self.getA(instr);
        var match = false;
        if (val.is(.pointer)) {
            const obj = try val.asPtr();
            if (obj.kind == .tuple and Tuple.getCount(obj) == instr.B) match = true;
        }
        if (!match) self.ip += @as(usize, instr.C) * 4;
    }
};
