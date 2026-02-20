const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const ast = @import("ast.zig");

const log = std.log.scoped(.parser);

pub const Parser = struct {
    lexer: Lexer,
    curToken: Token,
    peekToken: Token,

    pub fn parseModule(self: *Parser, allocator: std.mem.Allocator) !ast.Module {
        var functions: std.ArrayList(ast.FuncDecl) = .empty;
        errdefer {
            for (functions.items) |*func| func.deinit(allocator);
            functions.deinit(allocator);
        }

        try self.consume(.l_paren, "Expected '('");
        try self.consume(.keyword_module, "Expected 'module' keyword");

        while (!self.check(.r_paren) and !self.check(.eof)) {
            try self.consume(.l_paren, "Expected '(' to start declaration");

            if (self.match(.keyword_func)) {
                const func = try self.parseFuncDecl(allocator);
                try functions.append(allocator, func);
            } else {
                log.err("Unknown declaration: {any}", .{self.curToken});
                return error.UnknownDeclaration;
            }
        }

        try self.consume(.r_paren, "Expected ')' to close module");

        return .{
            .functions = try functions.toOwnedSlice(allocator),
        };
    }

    fn parseFuncDecl(self: *Parser, allocator: std.mem.Allocator) !ast.FuncDecl {
        var params: std.ArrayList(ast.Identifier) = .empty;
        var nodes: std.ArrayList(ast.Node) = .empty;
        errdefer {
            for (nodes.items) |*node| node.deinit(allocator);
            nodes.deinit(allocator);
            params.deinit(allocator);
        }

        const name = try self.parseIdentifier();

        log.debug("Compiling func {s}", .{name});

        while (!self.check(.r_paren) and !self.check(.eof)) {
            try self.consume(.l_paren, "Expected '(' to start instruction or metadata");

            if (self.match(.keyword_param)) {
                const param = try self.parseIdentifier();
                try params.append(allocator, param);
                try self.consume(.r_paren, "Expected ')' closing param");
            } else {
                const node = try self.parseInstruction(allocator);
                try nodes.append(allocator, node);
            }
        }

        try self.consume(.r_paren, "Expected ')' to close function declaration");

        return ast.FuncDecl{
            .name = name,
            .params = try params.toOwnedSlice(allocator),
            .body = try nodes.toOwnedSlice(allocator),
        };
    }

    fn parseInstruction(self: *Parser, allocator: std.mem.Allocator) !ast.Node {
        const tag = self.curToken.tag;
        self.advance();
        const node: ast.Node = switch (tag) {
            .keyword_print => .{
                .print = try self.parseRValue(),
            },
            .keyword_return => .{
                .ret = self.parseRValue() catch ast.RValue{ .Val = .void },
            },
            .keyword_call => blk: {
                const target = try self.parseIdentifier();
                var args: std.ArrayList(ast.RValue) = .empty;
                errdefer args.deinit(allocator);

                while (!self.check(.r_paren) and !self.check(.eof)) {
                    const arg = try self.parseRValue();
                    try args.append(allocator, arg);
                }

                const owned_args = try args.toOwnedSlice(allocator);
                break :blk .{
                    .expr = .{
                        .call = .{
                            .target = target,
                            .args = owned_args,
                        },
                    },
                };
            },
            .keyword_let => blk: {
                const dest = try self.parseIdentifier();
                var expr: ast.Expression = undefined;

                if (self.check(.l_paren)) {
                    expr = try self.parseExpression(allocator);
                } else {
                    log.debug("got expr in let", .{});
                    const rval = try self.parseRValue();
                    expr = .{ .val = rval };
                    log.debug("{any}", .{self.curToken});
                }

                break :blk .{
                    .let = .{
                        .dest = dest,
                        .expr = expr,
                    },
                };
            },
            .keyword_if => blk: {
                const condition = try self.parseExpression(allocator);
                var body: std.ArrayList(ast.Node) = .empty;
                errdefer {
                    for (body.items) |*n| n.deinit(allocator);
                    body.deinit(allocator);
                }
                while (!self.check(.r_paren) and !self.check(.eof)) {
                    try self.consume(.l_paren, "Expected '(' to start instruction in if body");
                    try body.append(allocator, try self.parseInstruction(allocator));
                }
                break :blk .{
                    .@"if" = .{
                        .cond = condition,
                        .body = try body.toOwnedSlice(allocator),
                    },
                };
            },
            else => {
                log.err("Unknown instruction '{any}'", .{tag});
                return error.UnknownInstruction;
            },
        };

        try self.consume(.r_paren, "Expected ')' after instruction arguments");

        return node;
    }

    fn parseExpression(self: *Parser, allocator: std.mem.Allocator) !ast.Expression {
        try self.consume(.l_paren, "Expected '(' to start expresion");

        const tag = self.curToken.tag;
        self.advance();

        const expr: ast.Expression = switch (tag) {
            .keyword_call => bkl: {
                const target = try self.parseIdentifier();
                var args: std.ArrayList(ast.RValue) = .empty;
                errdefer args.deinit(allocator);

                while (!self.check(.r_paren) and !self.check(.eof)) {
                    try args.append(allocator, try self.parseRValue());
                }

                break :bkl .{ .call = .{ .target = target, .args = try args.toOwnedSlice(allocator) } };
            },
            .keyword_lt, .keyword_add, .keyword_sub => blk: {
                const op: ast.BinaryOp = switch (tag) {
                    .keyword_lt => .lt,
                    .keyword_add => .add,
                    .keyword_sub => .sub,
                    else => unreachable,
                };
                const lhs = try self.parseRValue();
                const rhs = try self.parseRValue();
                break :blk .{ .binary = .{
                    .op = op,
                    .lhs = lhs,
                    .rhs = rhs,
                } };
            },
            else => {
                log.err("Unknown expression operator {any}", .{tag});
                return error.UnknownExpression;
            },
        };

        try self.consume(.r_paren, "Expected ')' to close expression");

        return expr;
    }

    fn parseRValue(self: *Parser) !ast.RValue {
        if (self.check(.string_literal)) {
            const rawToken = self.lexer.getTokenStr(self.curToken);
            const content = rawToken[1 .. rawToken.len - 1]; // remove '"'
            self.advance();
            return ast.RValue{ .Val = .{ .string = content } };
        }
        if (self.check(.identifier)) {
            const rawToken = self.lexer.getTokenStr(self.curToken);
            self.advance();
            return ast.RValue{ .Ref = .{ .identifier = rawToken } };
        }
        if (self.check(.number_literal)) {
            const rawToken = self.lexer.getTokenStr(self.curToken);
            const value = try std.fmt.parseInt(i64, rawToken, 10);
            self.advance();
            return .{ .Val = .{ .integer = value } };
        }
        return error.ExpectedValue;
    }

    fn parseIdentifier(self: *Parser) !ast.Identifier {
        const ident = self.lexer.getTokenStr(self.curToken);
        try self.consume(.identifier, "Expected identifier");
        return ident;
    }

    fn advance(self: *Parser) void {
        self.curToken = self.peekToken;
        self.peekToken = self.lexer.next();
    }
    fn consume(self: *Parser, tag: Token.Tag, msg: []const u8) !void {
        if (self.check(tag)) {
            _ = self.advance();
            return;
        }
        log.err("Parse Error: {s} Got: {any}\n", .{ msg, self.curToken.tag }); //TODO: print location
        return error.ParseError;
    }
    fn match(self: *Parser, tag: Token.Tag) bool {
        if (self.check(tag)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn check(self: *Parser, tag: Token.Tag) bool {
        return self.curToken.tag == tag;
    }

    fn checkPeek(self: *Parser, tag: Token.Tag) bool {
        return self.peekToken.tag == tag;
    }

    fn peek(self: *Parser) Token {
        return self.curToken;
    }
};
