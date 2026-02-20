const std = @import("std");
const rx = @import("rx");
const Parser = @import("parser.zig").Parser;
const Lexer = @import("lexer.zig").Lexer;

const log = std.log.scoped(.parser);

pub const Identifier = []const u8;
pub const Register = u8;

pub const Literal = union(enum) {
    integer: i64,
    string: []const u8,
    void: void,
};

// locations in memory
pub const LValue = union(enum) {
    identifier: Identifier, // %msg
    register: Register, // @0
};

// data source
pub const RValue = union(enum) {
    Ref: LValue,
    Val: Literal,
};

pub const BinaryOp =  enum { add, sub, lt, gt };

pub const Expression = union(enum) {
    binary: struct {
        op: BinaryOp,
        lhs: RValue,
        rhs: RValue,
    },
    call: struct {
        target: Identifier,
        args: []RValue,
    },
    val: RValue,

    pub fn deinit(self: *Expression, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .call => |c| {
                log.debug("deinit call args", .{});
                allocator.free(c.args);
            },
            else => {},
        }
    }
};

pub const Node = union(enum) {
    expr: Expression,
    let: struct {
        dest: Identifier,
        expr: Expression,
    },
    recv: struct {
        target: LValue,
    },
    send: struct {
        target: RValue,
        msg: RValue,
    },
    print: RValue,
    ret: RValue,
    @"if": struct {
        cond: Expression,
        body: []Node,
    },

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .expr => |*e| {
                e.deinit(allocator);
            },
            else => {},
        }
    }
};

pub const FuncDecl = struct {
    name: Identifier,
    params: []Identifier,
    body: []Node,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{s} (params)", .{self.name});
    }
    pub fn deinit(self: *FuncDecl, allocator: std.mem.Allocator) void {
        log.debug("deinit FuncDecl", .{});
        for (self.body) |*node| {
            node.deinit(allocator);
        }
        allocator.free(self.body);
        allocator.free(self.params);
    }
};

pub const Module = struct {
    functions: []FuncDecl,

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
        log.debug("deinit module", .{});
        for (self.functions) |*func| {
            func.deinit(allocator);
        }
        allocator.free(self.functions);
    }
};

pub fn parse(allocator: std.mem.Allocator, source: [:0]const u8) !Module {
    var lexer = Lexer.init(source);
    const curToken = lexer.next();
    const peekToken = lexer.next();

    var parser = Parser{
        .lexer = lexer,
        .curToken = curToken,
        .peekToken = peekToken,
    };

    return try parser.parseModule(allocator);
}
