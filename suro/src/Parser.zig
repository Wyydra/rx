const std = @import("std");
const ast = @import("ast.zig");
const Lexer = @import("Lexer.zig");
const Token = Lexer.Token;

const log = std.log.scoped(.parser);

pub fn parse(allocator: std.mem.Allocator, source: [:0]const u8) !ast.Module {
    var p = Parser.init(allocator, source);
    return p.parseModule();
}

pub const ParseError = error{
    UnexpectedToken,
    ExpectedEqual,
    ExpectedIdentifier,
    ExpectedModule,
    OutOfMemory,
} || std.fmt.ParseIntError;

const Parser = @This();

lexer: Lexer,
curToken: Token,
peekToken: Token,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, buffer: [:0]const u8) Parser {
    var lexer = Lexer.init(buffer);
    const cur = lexer.next();
    const peek = lexer.next();
    return Parser{
        .lexer = lexer,
        .curToken = cur,
        .peekToken = peek,
        .allocator = allocator,
    };
}

fn nextToken(self: *Parser) void {
    self.curToken = self.peekToken;
    self.peekToken = self.lexer.next();
}

fn match(self: *Parser, tag: Token.Tag) bool {
    if (self.curToken.tag == tag) {
        self.nextToken();
        return true;
    }
    return false;
}

fn consume(self: *Parser, tag: Token.Tag, comptime msg: []const u8) !void {
    if (self.curToken.tag == tag) {
        self.nextToken();
    } else {
        log.err("Parse error: {s}. Found {any}", .{ msg, self.curToken.tag });
        return error.UnexpectedToken;
    }
}

pub fn parseModule(self: *Parser) !ast.Module {
    var exprs: std.ArrayList(ast.Expr) = .empty;
    errdefer exprs.deinit(self.allocator); // TODO: deep deinit

    var moduleName: ?[]const u8 = null;

    if (self.match(.kw_module)) {
        moduleName = self.lexer.getTokenStr(self.curToken);
        try self.consume(.identifier, "Expected module name after 'module'");
    }

    while (self.curToken.tag != .eof) {
        const expr = try self.parseTopLevelExpr(); // for now a module is a sequence of top level bindings
        try exprs.append(self.allocator, expr);
    }

    return ast.Module{
        .name = moduleName,
        .exprs = try exprs.toOwnedSlice(self.allocator),
    };
}

fn parseTopLevelExpr(self: *Parser) !ast.Expr {
    const pat = try self.parsePattern();
    try self.consume(.equal, "Expected '=' in binding");
    const value = try self.parseExpr();

    return ast.Expr{
        .binding = .{
            .pattern = pat,
            .value = value,
        },
    };
}

fn parsePattern(self: *Parser) !ast.Pattern {
    if (self.curToken.tag == .identifier) {
        const name = self.lexer.getTokenStr(self.curToken);
        self.nextToken();

        if (std.mem.eql(u8, name, "_")) {
            return ast.Pattern{ .wildcard = {} };
        }

        // TODO: check for `name: Type`

        return ast.Pattern{ .identifier = name };
    }

    log.err("Expected pattern, found {any}", .{self.curToken.tag});
    return error.UnexpectedToken;
}

// ============================================================================
// EXPRESSIONS
// ============================================================================

fn parseExpr(self: *Parser) !*ast.Expr {
    const expr_ptr = try self.allocator.create(ast.Expr);
    errdefer self.allocator.destroy(expr_ptr);

    // TODO: Pratt Parser
    expr_ptr.* = try self.parsePrimary();

    return expr_ptr;
}

fn parsePrimary(self: *Parser) !ast.Expr {
    switch (self.curToken.tag) {
        .number_literal => {
            const str = self.lexer.getTokenStr(self.curToken);
            const val = try std.fmt.parseInt(i64, str, 10);
            self.nextToken();
            return ast.Expr{ .literal = .{ .integer = val } };
        },
        .identifier => {
            const name = self.lexer.getTokenStr(self.curToken);
            self.nextToken();
            return ast.Expr{ .identifier = name };
        },
        // TODO: implement l_paren for lambda/grouping, l_brace for block, etc.
        else => {
            log.err("Unexpected token in expression: {any}", .{self.curToken.tag});
            return error.UnexpectedToken;
        },
    }
}
