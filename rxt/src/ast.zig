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
    atom: []const u8,
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

pub const BinaryOp = enum { add, sub, mul, div, lt, gt, eq };

pub const Expression = union(enum) {
    binary: struct {
        op: BinaryOp,
        lhs: *Expression,
        rhs: *Expression,
    },
    call: struct {
        target: Identifier,
        args: []Expression,
    },
    tuple: struct {
        elements: []Expression,
    },
    tuple_get: struct {
        target: *Expression,
        index: *Expression,
    },
    tail_call: struct {
        target: Identifier,
        args: []Expression,
    },
    spawn: struct {
        target: *Expression,
        args: []Expression,
    },
    recv: void,
    self: void,
    val: RValue,

    pub fn deinit(self: *Expression, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .binary => |b| {
                b.lhs.deinit(allocator);
                b.rhs.deinit(allocator);
                allocator.destroy(b.lhs);
                allocator.destroy(b.rhs);
            },
            .call => |c| {
                for (c.args) |*arg| arg.deinit(allocator);
                allocator.free(c.args);
            },
            .tuple => |t| {
                for (t.elements) |*el| el.deinit(allocator);
                allocator.free(t.elements);
            },
            .tuple_get => |t| {
                t.target.deinit(allocator);
                t.index.deinit(allocator);
                allocator.destroy(t.target);
                allocator.destroy(t.index);
            },
            .spawn => |s| {
                s.target.deinit(allocator);
                allocator.destroy(s.target);
                for (s.args) |*arg| arg.deinit(allocator);
                allocator.free(s.args);
            },
            .tail_call => |c| {
                for (c.args) |*arg| arg.deinit(allocator);
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
    send: struct {
        target: Expression,
        msg: Expression,
    },
    print: Expression,
    ret: Expression,
    @"if": struct {
        cond: Expression,
        body: []Node,
    },

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .expr => |*e| e.deinit(allocator),
            .let => |*l| l.expr.deinit(allocator),
            .send => |*s| {
                s.target.deinit(allocator);
                s.msg.deinit(allocator);
            },
            .print => |*p| p.deinit(allocator),
            .ret => |*r| r.deinit(allocator),
            .@"if" => |*i| {
                i.cond.deinit(allocator);
                for (i.body) |*n| n.deinit(allocator);
                allocator.free(i.body);
            },
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
