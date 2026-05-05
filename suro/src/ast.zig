const std = @import("std");

pub const Module = struct {
    name: ?[]const u8,
    exprs: []Expr,
};

pub const Value = union(enum) {
    integer: i64,
    string: []const u8,
    atom: []const u8,
    boolean: bool,
    nil: void,
};

pub const Expr = union(enum) {
    literal: Value,
    identifier: []const u8,

    tuple: []TupleElement,

    block: []Expr,

    lambda: struct { params: []Pattern, body: *Expr },
    call: struct { callee: *Expr, args: []Expr },

    binding: struct { pattern: Pattern, value: *Expr },

    match_expr: struct { subject: *Expr, cases: []MatchCase },
};

pub const TupleElement = struct {
    key: ?[]const u8,
    value: Expr,
};

pub const MatchCase = struct {
    pattern: Pattern,
    body: *Expr,
};

pub const Pattern = union(enum) {
    wildcard: void,
    identifier: []const u8,

    typed: struct { name: []const u8, type_expr: *Expr },

    literal: Value,
    tuple: []Pattern,
};
