const std = @import("std");
const rx = @import("rx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var heap = try rx.memory.Heap.init(gpa.allocator(), rx.memory.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    std.debug.print("RX VM Memory System Demo\n", .{});
    std.debug.print("========================\n\n", .{});

    // Test tuple allocation
    std.debug.print("1. Tuple:\n", .{});
    const tuple = try rx.memory.tuple.alloc(&heap, 3);
    const elements = rx.memory.tuple.getElements(tuple);
    elements[0] = rx.memory.Value.integer(42);
    elements[1] = rx.memory.Value.boolean(true);
    elements[2] = rx.memory.Value.nil();
    std.debug.print("   Tuple[0] = {f}\n", .{elements[0]});
    std.debug.print("   Tuple[1] = {f}\n", .{elements[1]});
    std.debug.print("   Tuple[2] = {f}\n\n", .{elements[2]});

    // Test float allocation
    std.debug.print("2. Float:\n", .{});
    const float_obj = try rx.memory.float.alloc(&heap, 3.14159);
    const float_val = rx.memory.Value.pointer(float_obj);
    const retrieved_float = rx.memory.float.getValue(float_obj);
    std.debug.print("   Float value = {f} -> {d:.5}\n\n", .{ float_val, retrieved_float });

    // Test string allocation
    std.debug.print("3. String:\n", .{});
    const string_obj = try rx.memory.string.alloc(&heap, "Hello, RX VM!");
    const string_val = rx.memory.Value.pointer(string_obj);
    const string_bytes = rx.memory.string.getBytes(string_obj);
    std.debug.print("   String value = {f} -> \"{s}\"\n", .{ string_val, string_bytes });
    std.debug.print("   Length: {d} bytes\n\n", .{rx.memory.string.getLength(string_obj)});

    // Test empty string
    std.debug.print("4. Empty String:\n", .{});
    const empty_str = try rx.memory.string.alloc(&heap, "");
    std.debug.print("   Empty string length: {d}\n\n", .{rx.memory.string.getLength(empty_str)});

    // Test binary allocation
    std.debug.print("5. Binary:\n", .{});
    const binary_data = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE };
    const binary_obj = try rx.memory.binary.alloc(&heap, &binary_data);
    const binary_val = rx.memory.Value.pointer(binary_obj);
    const binary_bytes = rx.memory.binary.getBytes(binary_obj);
    std.debug.print("   Binary value = {f}\n", .{binary_val});
    std.debug.print("   Bytes: ", .{});
    for (binary_bytes) |byte| {
        std.debug.print("{X:0>2} ", .{byte});
    }
    std.debug.print("\n   Length: {d} bytes\n\n", .{rx.memory.binary.getLength(binary_obj)});

    // Test closure allocation
    std.debug.print("6. Closure:\n", .{});
    const closure_obj = try rx.memory.closure.alloc(&heap, 123, 3);
    const closure_val = rx.memory.Value.pointer(closure_obj);
    std.debug.print("   Closure value = {f}\n", .{closure_val});
    std.debug.print("   Function index: {d}\n", .{rx.memory.closure.getFunctionIndex(closure_obj)});
    std.debug.print("   Environment size: {d}\n", .{rx.memory.closure.getEnvCount(closure_obj)});

    // Set some environment values
    rx.memory.closure.setEnvValue(closure_obj, 0, rx.memory.Value.integer(100));
    rx.memory.closure.setEnvValue(closure_obj, 1, rx.memory.Value.boolean(false));
    rx.memory.closure.setEnvValue(closure_obj, 2, rx.memory.Value.pointer(string_obj));

    std.debug.print("   Env[0] = {f}\n", .{rx.memory.closure.getEnvValue(closure_obj, 0)});
    std.debug.print("   Env[1] = {f}\n", .{rx.memory.closure.getEnvValue(closure_obj, 1)});
    std.debug.print("   Env[2] = {f}\n\n", .{rx.memory.closure.getEnvValue(closure_obj, 2)});

    // Test nested tuple
    std.debug.print("7. Nested Tuple:\n", .{});
    const outer_tuple = try rx.memory.tuple.alloc(&heap, 2);
    const inner_tuple = try rx.memory.tuple.alloc(&heap, 2);

    const inner_elems = rx.memory.tuple.getElements(inner_tuple);
    inner_elems[0] = rx.memory.Value.integer(10);
    inner_elems[1] = rx.memory.Value.integer(20);

    const outer_elems = rx.memory.tuple.getElements(outer_tuple);
    outer_elems[0] = rx.memory.Value.pointer(inner_tuple);
    outer_elems[1] = rx.memory.Value.integer(30);

    std.debug.print("   Outer[0] = {f}\n", .{outer_elems[0]});
    std.debug.print("   Outer[1] = {f}\n\n", .{outer_elems[1]});

    // Summary
    std.debug.print("========================\n", .{});
    std.debug.print("Heap Summary:\n", .{});
    std.debug.print("  Bytes used: {d}\n", .{heap.byteUsed()});
    std.debug.print("  Objects allocated: {d}\n", .{heap.objectCount()});
    std.debug.print("  Heap capacity: {d}\n", .{heap.capacity});
}
