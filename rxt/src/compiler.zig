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
            const closure = try a.compileToClosure();
            try self.functions.put(func.name, closure);
        }

        if (self.functions.get("$_start")) |start_closure| {
            return start_closure;
        } else return error.NoStartFunction;
    }
};
