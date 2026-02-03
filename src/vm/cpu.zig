const std = @import("std");
const Process = @import("process.zig").Process;
const Closure = @import("../memory/closure.zig");
const Function = @import("../memory/function.zig");
const Instruction = @import("opcode.zig").Instruction;
const Value = @import("../memory/value.zig").Value;

// TODO: old struct remake it 
pub const ExecutionResult = packed struct {
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
    };

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

pub fn run(proc: *Process, limit: usize) ExecutionResult {
    var budget = limit;

    var stack = proc.stack.items;
    var frames = proc.frames.items;

    var frame_idx = proc.frames.items.len - 1;
    var frame = &frames[frame_idx];

    var closure = frame.closure;
    var function = Closure.getFunction(closure);
    var code = Function.getCode(function);
    var constants = Function.getConstants(function);

    var ip = frame.return_ip; // For the top frame, return_ip IS the current ip
    var base = frame.base;

    while (budget > 0) {
        if (ip + 4 >= code.len) {
            return ExecutionResult.terminated(0);
        }

        const raw_instr = std.mem.readInt(u32, code[ip..][0..4], .little); // TODO: ugly
        const instr = Instruction.decode(raw_instr);
        ip += 4; 

        std.debug.print("executing: {}\n", .{instr.getOpcode()});

        switch (instr.getOpcode()) {
            .PRINT => {
                const val = stack[base + instr.A];
                std.debug.print("> {f}\n", .{val});
            },
            .LOADK => {
                // R[A] = Constants[Bx]
                const val = constants[instr.getBx()];
                stack[base + instr.A] = val;
            },
            .ADD => {
                // R[A] = R[B] + R[C]
                const b = stack[base + instr.B];
                const c = stack[base + instr.C];

                const res = (b.asInteger() catch 0) + (c.asInteger() catch 0);
                stack[base + instr.A] = Value.integer(res);
            },
            .RET => {
                // RETURN A
                const result = stack[base + instr.A];

                _ = proc.frames.pop();

                if (proc.frames.items.len == 0) {
                    return ExecutionResult.terminated(0);
                }

                // restore parent
                frames = proc.frames.items; 
                frame_idx -= 1;
                frame = &frames[frame_idx];

                const caller_base = frame.base;

                // return value
                stack[base - 1] = result;

                base = caller_base;
                ip = frame.return_ip;

                closure = frame.closure;
                function = Closure.getFunction(closure);
                code = Function.getCode(function);
                constants = Function.getConstants(function);
            },
        }

        budget -= 1; // TODO: reduction depends on the instruction type
    } 
    frame.return_ip = ip;

    const val: u8 =  @intCast(limit - budget);
    return ExecutionResult.normal(val);
}
