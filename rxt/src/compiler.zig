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
        // Pass 0: Pre-register all functions with placeholders
        // This allows any function to reference any other function (forward refs/recursion)
        var placeholders = std.AutoHashMap(*rx.memory.HeapObject, *rx.memory.HeapObject).init(allocator);
        defer placeholders.deinit();

        for (mod.functions) |func| {
            const placeholder = try rx.memory.Function.alloc(allocator, 0, 0, 0, &.{}, &.{});
            placeholder.flags = rx.memory.HeapObject.FROZEN;
            try self.functions.put(func.name, placeholder);
        }

        // Pass 1: Compile all function bodies
        var compiled_funcs: std.ArrayList(*rx.memory.HeapObject) = .empty;
        defer compiled_funcs.deinit(allocator);

        for (mod.functions) |func| {
            const placeholder = self.functions.get(func.name).?;
            const real_func = try self.compileFunc(allocator, func, placeholder);
            try placeholders.put(placeholder, real_func);
            try compiled_funcs.append(allocator, real_func);

            // Update the name map to point to the real function for future lookups
            try self.functions.put(func.name, real_func);
        }

        // Pass 2: Patch all references to placeholders with the real function pointers
        for (compiled_funcs.items) |func_obj| {
            const mut_consts = rx.memory.Function.getConstantsMut(func_obj);
            for (mut_consts) |*c| {
                if (c.isPointer()) {
                    const ptr = c.asPointer() catch unreachable;
                    if (placeholders.get(ptr)) |real| {
                        c.* = rx.memory.Value.pointer(real);
                    }
                }
            }
        }

        return self.functions.get("$_start") orelse error.NoStartFunction;
    }

    fn compileFunc(self: *Compiler, allocator: std.mem.Allocator, func: ast.FuncDecl, placeholder_func: *rx.memory.HeapObject) !*rx.memory.HeapObject {
        var a = rx.bytecode.Assembler.init(allocator);
        defer a.deinit();

        var ctx = FuncContext.init(allocator);
        defer ctx.deinit();

        for (func.params, 0..) |param, index| {
            const reg: u8 = @intCast(index);
            try ctx.aliases.put(param, reg);
            if (reg >= ctx.next_temp_reg) ctx.next_temp_reg = reg + 1;
        }

        try self.compileBody(&a, &ctx, func.body, true);
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

    fn compileBody(self: *Compiler, a: *rx.bytecode.Assembler, ctx: *FuncContext, body: []const ast.Node, is_function: bool) !void {
        for (body, 0..) |node, index| {
            const is_last = index == body.len - 1;

            switch (node) {
                .print => |e| {
                    const saved_reg = ctx.next_temp_reg;
                    const dest_reg = ctx.allocTempReg();
                    try self.compileExpression(a, ctx, e, dest_reg);
                    try a.print(dest_reg);
                    ctx.next_temp_reg = saved_reg; // free the temp after printing
                },
                .ret => |e| {
                    const saved_reg = ctx.next_temp_reg;
                    const reg = ctx.allocTempReg();
                    try self.compileExpression(a, ctx, e, reg);
                    try a.ret(reg);
                    ctx.next_temp_reg = saved_reg;
                },
                .let => |l| {
                    const dest_reg = ctx.allocTempReg();
                    try ctx.aliases.put(l.dest, dest_reg);
                    try self.compileExpression(a, ctx, l.expr, dest_reg);
                },
                .expr => |e| {
                    const dest_reg = ctx.allocTempReg();
                    try self.compileExpression(a, ctx, e, dest_reg);

                    if (is_last and is_function) {
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

                    var saved_aliases = try ctx.aliases.clone();
                    defer saved_aliases.deinit();
                    const saved_next_reg = ctx.next_temp_reg;

                    try self.compileBody(a, ctx, i.body, false);

                    const high_water = ctx.next_temp_reg;
                    ctx.aliases.deinit();
                    ctx.aliases = saved_aliases.move();
                    ctx.next_temp_reg = high_water;
                    _ = saved_next_reg; // keep for documentation

                    try a.patchJump(jump_index);
                    ctx.next_temp_reg = cond_reg + 1;
                },
                .send => |s| {
                    const saved_reg = ctx.next_temp_reg;
                    const target_reg = ctx.allocTempReg();
                    try self.compileExpression(a, ctx, s.target, target_reg);
                    const msg_reg = ctx.allocTempReg();
                    try self.compileExpression(a, ctx, s.msg, msg_reg);
                    try a.send(target_reg, msg_reg);
                    ctx.next_temp_reg = saved_reg; // free any temps used for target/msg
                },
            }
        }

        if (is_function) {
            if (body.len == 0 or (std.meta.activeTag(body[body.len - 1]) != .ret and std.meta.activeTag(body[body.len - 1]) != .expr)) {
                const ret_reg = ctx.allocTempReg();
                try a.loadConstant(ret_reg, rx.memory.Value.nil());
                try a.ret(ret_reg);
            }
        }
    }

    fn compileExpression(self: *Compiler, a: *rx.bytecode.Assembler, ctx: *FuncContext, expr: ast.Expression, dest_reg: u8) !void {
        switch (expr) {
            .call => |c| {
                if (self.functions.get(c.target)) |func_obj| {
                    try a.closure(dest_reg, func_obj);
                } else {
                    log.err("Unknown function {s}", .{c.target});
                    return error.UnknownFunction;
                }

                for (c.args, 0..) |arg, i| {
                    const arg_reg = ctx.allocTempReg();
                    std.debug.assert(arg_reg == dest_reg + 1 + i);
                    try self.compileExpression(a, ctx, arg, arg_reg);
                }

                try a.call(dest_reg, @intCast(c.args.len));

                // free tempory registers
                ctx.next_temp_reg = dest_reg + 1;
            },
            .tuple => |t| {
                for (t.elements) |elem| {
                    const elem_reg = ctx.allocTempReg();
                    try self.compileExpression(a, ctx, elem, elem_reg);
                }
                try a.emit(.NEWTUPLE, dest_reg, @intCast(t.elements.len), 0);
                ctx.next_temp_reg = dest_reg + 1;
            },
            .tuple_get => |t| {
                const target_reg = ctx.allocTempReg();
                try self.compileExpression(a, ctx, t.target.*, target_reg);
                const index_reg = ctx.allocTempReg();
                try self.compileExpression(a, ctx, t.index.*, index_reg);
                
                try a.getTuple(dest_reg, target_reg, index_reg);
                
                ctx.next_temp_reg = dest_reg + 1;
            },
            .spawn => |s| {
                const closure_reg = ctx.allocTempReg();
                try self.compileExpression(a, ctx, s.target.*, closure_reg);

                for (s.args, 0..) |arg, i| {
                    const arg_reg = ctx.allocTempReg();
                    std.debug.assert(arg_reg == closure_reg + 1 + i); // sanity check, args placed immediately after closure
                    try self.compileExpression(a, ctx, arg, arg_reg);
                }

                try a.spawn(dest_reg, closure_reg, @intCast(s.args.len));
                ctx.next_temp_reg = dest_reg + 1; // free temps used by args and closure
            },
            .recv => {
                try a.recv(dest_reg);
            },
            .self => {
                try a.emit(.SELF, dest_reg, 0, 0);
            },
            .binary => |b| {
                const lhs_reg = ctx.allocTempReg();
                try self.compileExpression(a, ctx, b.lhs.*, lhs_reg);
                const rhs_reg = ctx.allocTempReg();
                try self.compileExpression(a, ctx, b.rhs.*, rhs_reg);
                switch (b.op) {
                    .lt => try a.emit(.LT, dest_reg, lhs_reg, rhs_reg),
                    .gt => try a.emit(.GT, dest_reg, lhs_reg, rhs_reg),
                    .add => try a.emit(.ADD, dest_reg, lhs_reg, rhs_reg),
                    .sub => try a.emit(.SUB, dest_reg, lhs_reg, rhs_reg),
                    .mul => try a.emit(.MUL, dest_reg, lhs_reg, rhs_reg),
                    .div => try a.emit(.DIV, dest_reg, lhs_reg, rhs_reg),
                    .eq => try a.emit(.EQ, dest_reg, lhs_reg, rhs_reg),
                }
                ctx.next_temp_reg = dest_reg + 1;
            },
            .tail_call => |c| {
                if (self.functions.get(c.target)) |func_obj| {
                    try a.closure(dest_reg, func_obj);
                } else {
                    log.err("Unknown function {s}", .{c.target});
                    return error.UnknownFunction;
                }

                for (c.args, 0..) |arg, i| {
                    const arg_reg = ctx.allocTempReg();
                    std.debug.assert(arg_reg == dest_reg + 1 + i);
                    try self.compileExpression(a, ctx, arg, arg_reg);
                }

                try a.tailCall(dest_reg, @intCast(c.args.len));
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
                            try a.closure(dest_reg, func_obj);
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
                    try a.closure(dest_reg, func_obj);
                } else {
                    try a.loadString(dest_reg, s);
                }
            },
            .atom => |s| try a.loadAtom(dest_reg, s),
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
