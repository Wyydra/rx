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
        defer functions.deinit(allocator);

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
        const params: u8 = 0;
        var nodes: std.ArrayList(ast.Node) = .empty;
        defer nodes.deinit(allocator);

        const name = try self.parseIdentifier();

        while (!self.check(.r_paren) and !self.check(.eof)) {
            try self.consume(.l_paren, "Expected '(' to start instruction or metadata");

            if (self.match(.keyword_param)) {
                return error.NotImplemented;
                // try self.consume(.r_paren, "Closing param");
            } else {
                const node = try self.parseInstruction();
                try nodes.append(allocator, node);
            }
        }

        try self.consume(.r_paren, "Expected ')' to close function declaration");

        return ast.FuncDecl{
            .name = name,
            .params = params,
            .body = try nodes.toOwnedSlice(allocator),
        };
    }

    fn parseInstruction(self: *Parser) !ast.Node {
        const tag = self.curToken.tag;
        self.advance();
        const node: ast.Node = switch (tag) {
            .keyword_print => .{
                .print = try self.parseRValue(),
            },
            .keyword_return => .{
                .ret = self.parseRValue() catch ast.RValue{ .Val = .void },
            },
            else => {
                log.err("Unknown instruction '{any}'", .{tag});
                return error.UnknownInstruction;
            },
        };

        try self.consume(.r_paren, "Expected ')' after instruction arguments");

        return node;
    }

    fn parseRValue(self: *Parser) !ast.RValue {
        if (self.check(.string_literal)) {
            const rawToken = self.lexer.getTokenStr(self.curToken);
            const content = rawToken[1 .. rawToken.len - 1]; // remove '"'
            self.advance();
            return ast.RValue{ .Val = .{ .string = content } };
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
