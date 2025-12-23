pub const memory = struct {
    pub const Value = @import("memory/value.zig").Value;
    pub const HeapObject = @import("memory/value.zig").HeapObject;
    pub const Heap = @import("memory/heap.zig").Heap;
    pub const HeapError = @import("memory/heap.zig").HeapError;
    pub const ObjectError = @import("memory/heap.zig").ObjectError;

    pub const tuple = @import("memory/tuple.zig");
    pub const float = @import("memory/float.zig");
    pub const string = @import("memory/string.zig");
    pub const binary = @import("memory/binary.zig");
    pub const closure = @import("memory/closure.zig");
};

test {
    _ = @import("memory/value.zig");
    _ = @import("memory/heap.zig");
    _ = @import("memory/tuple.zig");
    _ = @import("memory/float.zig");
    _ = @import("memory/string.zig");
    _ = @import("memory/binary.zig");
    _ = @import("memory/closure.zig");
}

const std = @import("std");
