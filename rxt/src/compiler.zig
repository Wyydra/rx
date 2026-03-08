const std = @import("std");
const rx = @import("rx");
const ast = @import("ast.zig");

const log = std.log.scoped(.compiler);

pub fn compile(allocator: std.mem.Allocator, mod: *const ast.Module) !*rx.memory.HeapObject {
    var compiler = try Compiler.init(allocator);
    defer compiler.deinit();
    return compiler.compile(allocator, mod);
}

const Compiler = struct {
    functions: std.StringHashMap(*rx.memory.HeapObject),

    fn init(allocator: std.mem.Allocator) !Compiler {
        var functions = std.StringHashMap(*rx.memory.HeapObject).init(allocator);
        // Reserve space for a typical module (avoids rehash for small programs).
        try functions.ensureTotalCapacity(8);
        return .{
            .functions = functions,
        };
    }
    fn deinit(self: *Compiler) void {
        self.functions.deinit();
    }

    fn compile(self: *Compiler, allocator: std.mem.Allocator, mod: *const ast.Module) !*rx.memory.HeapObject {
        // Pass 1: compile all non-$_start functions so their closures are
        // available as constants when $_start is compiled.
        for (mod.functions) |func| {
            if (std.mem.eql(u8, func.name, "$_start")) continue;
            const func_obj = try self.compileFunc(allocator, func);
            try self.functions.put(func.name, func_obj);
        }

        // Pass 2: compile $_start — callee closures are now in the map.
        for (mod.functions) |func| {
            if (!std.mem.eql(u8, func.name, "$_start")) continue;
            const func_obj = try self.compileFunc(allocator, func);
            return func_obj;
        }

        return error.NoStartFunction;
    }

    fn compileFunc(self: *Compiler, allocator: std.mem.Allocator, func: ast.FuncDecl) !*rx.memory.HeapObject {
        const placeholder_func = try rx.memory.Function.alloc(allocator, 0, 0, 0, &.{}, &.{});
        placeholder_func.flags = rx.memory.HeapObject.FROZEN;
        try self.functions.put(func.name, placeholder_func);

        var a = rx.bytecode.Assembler.init(allocator);
        defer a.deinit();

        var ctx = FuncContext.init(allocator);
        defer ctx.deinit();

        for (func.params, 0..) |param, index| {
            const reg: u8 = @intCast(index);
            try ctx.aliases.put(param, reg);
            if (reg >= ctx.next_temp_reg) ctx.next_temp_reg = reg + 1;
        }

        try self.compileBody(&a, &ctx, func.body);
        const real_func = try a.compileToFunction();

        const mut_consts = rx.memory.Function.getConstantsMut(real_func);
        for (mut_consts) |*c| {
            if (c.isPointer() and (c.asPointer() catch unreachable) == placeholder_func) {
                c.* = rx.memory.Value.pointer(real_func);
            }
        }

        // Update the map so future callers get the real function directly
        try self.functions.put(func.name, real_func);

        return real_func;
    }

    fn compileBody(self: *Compiler, a: *rx.bytecode.Assembler, ctx: *FuncContext, body: []const ast.Node) !void {
        for (body, 0..) |node, index| {
            const is_last = index == body.len - 1;

            switch (node) {
                .print => |e| {
                    const dest_reg = ctx.allocTempReg();
                    try self.compileExpression(a, ctx, e, dest_reg);
                    try a.print(dest_reg);
                },
                .ret => |r| {
                    const reg = try self.compileRValue(a, ctx, r);
                    try a.ret(reg);
                },
                .let => |l| {
                    const dest_reg = ctx.allocTempReg();
                    try ctx.aliases.put(l.dest, dest_reg);
                    try self.compileExpression(a, ctx, l.expr, dest_reg);
                },
                .expr => |e| {
                    const dest_reg = ctx.allocTempReg();
                    try self.compileExpression(a, ctx, e, dest_reg);

                    if (is_last) {
                        try a.ret(dest_reg);
                    } else {
                        ctx.next_temp_reg = dest_reg; // reset reg
                    }
                },
                .@"if" => |i| {
                    const cond_reg = ctx.allocTempReg();
                    try self.compileExpression(a, ctx, i.cond, cond_reg);
                    const jump_index = a.code.items.len;
                    try a.emit(.JF, cond_reg, 0, 0);
                    try self.compileBody(a, ctx, i.body);
                    try a.patchJump(jump_index);
                    ctx.next_temp_reg = cond_reg;
                },
                .send => |s| {
                    const target_reg = try self.compileRValue(a, ctx, s.target);
                    const msg_reg = try self.compileRValue(a, ctx, s.msg);
                    try a.send(target_reg, msg_reg);
                    ctx.next_temp_reg = target_reg;
                },
            }
        }

        if (body.len == 0 or (std.meta.activeTag(body[body.len - 1]) != .ret and std.meta.activeTag(body[body.len - 1]) != .expr)) {
            const ret_reg = ctx.allocTempReg();
            try a.loadConstant(ret_reg, rx.memory.Value.nil());
            try a.ret(ret_reg);
        }
    }

    fn compileExpression(self: *Compiler, a: *rx.bytecode.Assembler, ctx: *FuncContext, expr: ast.Expression, dest_reg: u8) !void {
        switch (expr) {
            .call => |c| {
                if (self.functions.get(c.target)) |func_obj| {
                    try a.loadConstant(dest_reg, rx.memory.Value.pointer(func_obj));
                } else {
                    log.err("Unknown function {s}", .{c.target});
                    return error.UnknownFunction;
                }

                for (c.args, 0..) |arg, i| {
                    const arg_reg = ctx.allocTempReg();
                    std.debug.assert(arg_reg == dest_reg + 1 + i);

                    switch (arg) {
                        .Val => |lit| {
                            try self.compileLiteralTo(a, lit, arg_reg);
                        },
                        .Ref => |lval| {
                            const src_reg = try resolveLValue(ctx, lval);
                            try a.move(src_reg, arg_reg);
                        },
                    }
                }

                try a.call(dest_reg, @intCast(c.args.len));

                // free tempory registers
                ctx.next_temp_reg = dest_reg + 1;
            },
            .tuple => |t| {
                for (t.elements) |elem| {
                    const elem_reg = ctx.allocTempReg();
                    try self.compileRValueTo(a, ctx, elem, elem_reg);
                }
                try a.emit(.NEWTUPLE, dest_reg, @intCast(t.elements.len), 0);
                ctx.next_temp_reg = dest_reg + 1;
            },
            .spawn => |s| {
                const closure_reg = ctx.allocTempReg();
                try self.compileRValueTo(a, ctx, s.target, closure_reg);

                for (s.args, 0..) |arg, i| {
                    const arg_reg = ctx.allocTempReg();
                    std.debug.assert(arg_reg == closure_reg + 1 + i); // sanity check, args placed immediately after closure

                    switch (arg) {
                        .Val => |lit| {
                            try self.compileLiteralTo(a, lit, arg_reg);
                        },
                        .Ref => |lval| {
                            const src_reg = try resolveLValue(ctx, lval);
                            try a.move(src_reg, arg_reg);
                        },
                    }
                }

                try a.spawn(dest_reg, closure_reg, @intCast(s.args.len));
                ctx.next_temp_reg = dest_reg + 1; // free temps used by args and closure
            },
            .recv => {
                try a.recv(dest_reg);
            },
            .binary => |b| {
                const lhs_reg = try self.compileRValue(a, ctx, b.lhs);
                const rhs_reg = try self.compileRValue(a, ctx, b.rhs);
                switch (b.op) {
                    .lt => try a.emit(.LT, dest_reg, lhs_reg, rhs_reg),
                    .gt => try a.emit(.GT, dest_reg, lhs_reg, rhs_reg),
                    .add => try a.emit(.ADD, dest_reg, lhs_reg, rhs_reg),
                    .sub => try a.emit(.SUB, dest_reg, lhs_reg, rhs_reg),
                }
            },
            .val => |v| try self.compileRValueTo(a, ctx, v, dest_reg),
        }
    }

    fn compileRValue(self: *Compiler, a: *rx.bytecode.Assembler, ctx: *FuncContext, rval: ast.RValue) !u8 {
        switch (rval) {
            .Ref => |lval| return try resolveLValue(ctx, lval),
            .Val => |lit| {
                const temp_reg = ctx.allocTempReg();
                try self.compileLiteralTo(a, lit, temp_reg);
                return temp_reg;
            },
        }
    }

    fn compileRValueTo(self: *Compiler, a: *rx.bytecode.Assembler, ctx: *FuncContext, rval: ast.RValue, dest_reg: u8) !void {
        switch (rval) {
            .Val => |lit| try self.compileLiteralTo(a, lit, dest_reg),
            .Ref => |lval| {
                switch (lval) {
                    .register => |reg| {
                        if (reg != dest_reg) try a.move(reg, dest_reg);
                    },
                    .identifier => |name| {
                        // First, try local variable aliases
                        if (ctx.aliases.get(name)) |src_reg| {
                            if (src_reg != dest_reg) try a.move(src_reg, dest_reg);
                            // Then, try function map (e.g. `$worker` as a closure reference)
                        } else if (self.functions.get(name)) |func_obj| {
                            try a.loadConstant(dest_reg, rx.memory.Value.pointer(func_obj));
                        } else {
                            log.err("Unknown variable or function: {s}", .{name});
                            return error.UnknownVariable;
                        }
                    },
                }
            },
        }
    }

    fn compileLiteralTo(self: *Compiler, a: *rx.bytecode.Assembler, literal: ast.Literal, dest_reg: u8) !void {
        switch (literal) {
            .integer => |i| try a.loadConstant(dest_reg, rx.memory.Value.integer(i)),
            .string => |s| {
                if (self.functions.get(s)) |func_obj| {
                    try a.loadConstant(dest_reg, rx.memory.Value.pointer(func_obj));
                } else {
                    try a.loadString(dest_reg, s);
                }
            },
            .void => try a.loadConstant(dest_reg, rx.memory.Value.nil()),
        }
    }

    fn resolveLValue(ctx: *FuncContext, lval: ast.LValue) !u8 {
        switch (lval) {
            .register => |reg| return reg,
            .identifier => |name| return ctx.aliases.get(name) orelse error.UnknownVariable,
        }
    }
};

const FuncContext = struct {
    aliases: std.StringHashMap(u8),
    next_temp_reg: u8 = 0,

    pub fn init(allocator: std.mem.Allocator) FuncContext {
        var aliases = std.StringHashMap(u8).init(allocator);
        // Most functions have few parameters; pre-allocate to avoid rehash.
        aliases.ensureTotalCapacity(8) catch {};
        return .{
            .aliases = aliases,
        };
    }
    pub fn deinit(self: *FuncContext) void {
        self.aliases.deinit();
    }
    pub fn allocTempReg(self: *FuncContext) u8 {
        const reg = self.next_temp_reg;
        self.next_temp_reg += 1;
        return reg;
    }
};
