const std = @import("std");
const rx = @import("rx");
const ast = @import("ast.zig");

const log = std.log.scoped(.compiler);

pub fn compile(allocator: std.mem.Allocator, heap: *rx.memory.Heap, mod: *const ast.Module) !*rx.memory.HeapObject {
    var compiler = try Compiler.init(allocator);
    defer compiler.deinit();
    return compiler.compile(allocator, heap, mod);
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

    fn compile(self: *Compiler, allocator: std.mem.Allocator, heap: *rx.memory.Heap, mod: *const ast.Module) !*rx.memory.HeapObject {
        // Pass 1: compile all non-$_start functions so their closures are
        // available as constants when $_start is compiled.
        for (mod.functions) |func| {
            if (std.mem.eql(u8, func.name, "$_start")) continue;
            const closure = try self.compileFunc(allocator, heap, func);
            try self.functions.put(func.name, closure);
        }

        // Pass 2: compile $_start — callee closures are now in the map.
        for (mod.functions) |func| {
            if (!std.mem.eql(u8, func.name, "$_start")) continue;
            const closure = try self.compileFunc(allocator, heap, func);
            return closure;
        }

        return error.NoStartFunction;
    }

    fn compileFunc(self: *Compiler, allocator: std.mem.Allocator, heap: *rx.memory.Heap, func: ast.FuncDecl) !*rx.memory.HeapObject {
        // Pre-register a placeholder closure so self-calls can resolve `func.name`
        // during body compilation. LOADK will embed the placeholder's pointer —
        // after we patch it below, the VM will run the real function transparently.
        const placeholder_func = try rx.memory.Function.alloc(heap, 0, 0, 0, &.{}, &.{});
        const placeholder = try rx.memory.Closure.alloc(heap, placeholder_func, 0);
        try self.functions.put(func.name, placeholder);

        var a = rx.bytecode.Assembler.init(allocator, heap);
        defer a.deinit();

        var ctx = FuncContext.init(allocator);
        defer ctx.deinit();

        for (func.params, 0..) |param, index| {
            const reg: u8 = @intCast(index);
            try ctx.aliases.put(param, reg);
            if (reg >= ctx.next_temp_reg) ctx.next_temp_reg = reg + 1;
        }

        try self.compileBody(&a, &ctx, func.body);
        const real_closure = try a.compileToClosure();

        // Patch the placeholder
        rx.memory.Closure.setFunction(placeholder, rx.memory.Closure.getFunction(real_closure));

        // Update the map so future callers get the real closure directly
        try self.functions.put(func.name, real_closure);

        return real_closure;
    }

    fn compileBody(self: *Compiler, a: *rx.bytecode.Assembler, ctx: *FuncContext, body: []const ast.Node) !void {
        for (body) |node| {
            switch (node) {
                .print => |p| {
                    const reg = try self.compileRValue(a, ctx, p);
                    try a.print(reg);
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
                    ctx.next_temp_reg = dest_reg; // reset reg
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
                else => {
                    log.err("compilation not implemented for {}", .{node});
                    return error.NotImplemented;
                },
            }
        }
    }

    fn compileExpression(self: *Compiler, a: *rx.bytecode.Assembler, ctx: *FuncContext, expr: ast.Expression, dest_reg: u8) !void {
        switch (expr) {
            .call => |c| {
                if (self.functions.get(c.target)) |closure_obj| {
                    try a.loadConstant(dest_reg, rx.memory.Value.pointer(closure_obj));
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
                const src_reg = try resolveLValue(ctx, lval);
                if (src_reg != dest_reg) {
                    try a.move(src_reg, dest_reg);
                }
            }
        }
    }

    fn compileLiteralTo(self: *Compiler, a: *rx.bytecode.Assembler, literal: ast.Literal, dest_reg: u8) !void {
        switch (literal) {
            .integer => |i| try a.loadConstant(dest_reg, rx.memory.Value.integer(i)),
            .string => |s| {
                if (self.functions.get(s)) |closure_obj| {
                    try a.loadConstant(dest_reg, rx.memory.Value.pointer(closure_obj));
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
