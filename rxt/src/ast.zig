const std = @import("std");
const rx = @import("rx");
const Parser = @import("parser.zig").Parser;
const Lexer = @import("lexer.zig").Lexer;

const log = std.log.scoped(.parser);

pub const Identifier = [] const u8;
pub const Register = u8;

pub const Literal = union(enum) {
    integer: i64,
    string: []const u8,
    void: void,
};

// locations in memory
pub const LValue = union(enum) {
    identifier: Identifier, // %msg
    register: Register,     // @0
};

// data source
pub const RValue = union(enum) {
    Ref: LValue,
    Val: Literal,
};

pub const Node = union(enum) {
    alias: struct {
        name: Identifier,
        reg: Register,
    },
    recv: struct {
        target: LValue,
    },
    send: struct {
        target: RValue,
        msg: RValue,
    },
    call: struct {
        target: Literal,
        args: u8,
    },
    print: RValue,
    ret: RValue,
};

pub const FuncDecl = struct {
    name: Identifier,
    params: u8,
    body: [] const Node,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{s} (params)", .{self.name});
    }
};

pub const Module = struct {
    functions: []const FuncDecl, 

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {

        try writer.print("[\n", .{});
        for (self.functions) |func| {
            try writer.print("{f}\n", .{func});
        }
        try writer.print("]\n", .{});
    }

    pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
        for (self.functions) |func| {
            allocator.free(func.body);
        }
        defer allocator.free(self.functions);
    }
};

pub fn parse(allocator: std.mem.Allocator, source: [:0]const u8) !Module {
    var lexer = Lexer.init(source);
    const curToken = lexer.next();
    const peekToken = lexer.next();

    var parser = Parser {
        .lexer = lexer,
        .curToken = curToken,
        .peekToken = peekToken,
    };

    return try parser.parseModule(allocator);
}


