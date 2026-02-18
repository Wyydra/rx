const std = @import("std");
const rx = @import("rx");
const ast = @import("ast.zig");

pub fn compile(allocator: std.mem.Allocator, heap: *rx.memory.Heap, mod: *const ast.Module) !*rx.memory.HeapObject {
    var compiler = try Compiler.init(allocator);
    defer compiler.deinit();
    return compiler.compile(allocator, heap, mod);
}

const Compiler = struct {
    functions: std.StringHashMap(*rx.memory.HeapObject),

    fn init(allocator: std.mem.Allocator) !Compiler {
        return .{
            .functions = std.StringHashMap(*rx.memory.HeapObject).init(allocator),
        };
    }
    fn deinit(self: *Compiler) void {
        self.functions.deinit();
    }

    fn compile(self: *Compiler, allocator: std.mem.Allocator, heap: *rx.memory.Heap, mod: *const ast.Module) !*rx.memory.HeapObject {
        for (mod.functions) |func| {
            var a = rx.bytecode.Assembler.init(allocator, heap);
            defer a.deinit();

            var ctx = FuncContext.init(allocator);
            defer ctx.deinit();

            try compileBody(&a, &ctx, func.body);
            const closure = try a.compileToClosure();
            try self.functions.put(func.name, closure);
        }

        if (self.functions.get("$_start")) |start_closure| {
            return start_closure;
        } else return error.NoStartFunction;
    }

    fn compileBody(a: *rx.bytecode.Assembler, ctx: *FuncContext, body: []const ast.Node) !void {
        for (body) |node| {
            switch (node) {
                .print => |p| {
                    const reg = try compileRValue(a, ctx, p);
                    try a.print(reg);
                },
                .ret => |r| {
                    const reg = try compileRValue(a, ctx, r);
                    try a.ret(reg);
                },
                else => return error.NotImplemented,
            }
        }
    }

    fn compileRValue(a: *rx.bytecode.Assembler, ctx: *FuncContext, rval: ast.RValue) !u8 {
        switch (rval) {
            .Ref => |lval| return try resolveLValue(ctx, lval),
            .Val => |lit| return try compileLiteral(a, ctx, lit),
        }
    }

    fn compileLiteral(a: *rx.bytecode.Assembler, ctx: *FuncContext, literal: ast.Literal) !u8 {
        const temp_reg = ctx.allocTempReg();
        switch (literal) {
            .integer => |i| try a.loadConstant(temp_reg, rx.memory.Value.integer(i)),
            .string => |s| try a.loadString(temp_reg, s),
            .void => try a.loadConstant(temp_reg, rx.memory.Value.nil()),
        }
        return temp_reg;
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
        return .{
            .aliases = std.StringHashMap(u8).init(allocator),
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
