pub const Token = struct {
    tag: Tag,
    loc: Loc,
    line: usize,
    lineOffset: usize,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    const keywords = std.StaticStringMap(Tag).initComptime(.{
        .{ "print", .keyword_print },
        .{ "module", .keyword_module },
        .{ "func", .keyword_func },
        .{ "param", .keyword_param },
        .{ "return", .keyword_return },
        .{ "call", .keyword_call },
        .{ "let", .keyword_let },
        .{ "if", .keyword_if },
        .{ "lt", .keyword_lt },
        .{ "sub", .keyword_sub },
        .{ "add", .keyword_add },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        number_literal,
        string_literal,
        r_paren,
        l_paren,
        identifier,
        comment,
        invalid,
        eof,

        keyword_print,
        keyword_module,
        keyword_func,
        keyword_param,
        keyword_return,
        keyword_call,
        keyword_let,
        keyword_if,
        keyword_lt,
        keyword_sub,
        keyword_add,
    };
};

pub const Lexer = struct {
    buffer: [:0]const u8,
    index: usize,
    currentLine: usize,
    currentLineOffset: usize,

    pub fn init(buffer: [:0]const u8) Lexer {
        return Lexer{
            .buffer = buffer,
            .currentLine = 1,
            .currentLineOffset = 0,
            .index = 0,
        };
    }

    const State = enum {
        start,
        invalid,
        number_literal,
        string_literal,
        identifier,
        keyword,
    };

    pub fn next(self: *Lexer) Token {
        var state: State = .start;
        var result = Token{
            .tag = .eof,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
            .line = self.currentLine,
            .lineOffset = self.currentLineOffset,
        };
        while (true) : (self.index += 1) {
            const c = self.buffer[self.index];
            self.currentLineOffset += 1;
            switch (state) {
                .start => switch (c) {
                    0 => {
                        if (self.index != self.buffer.len) {
                            result.tag = .invalid;
                            result.loc.end = self.index;
                            self.index += 1;
                            return result;
                        }
                        break;
                    },
                    ' ', '\n', '\t', '\r' => {
                        result.loc.start = self.index + 1;
                        if (c == '\n') {
                            self.currentLine += 1;
                            self.currentLineOffset = 0;
                        }
                    },
                    '"' => {
                        state = .string_literal;
                        result.tag = .string_literal;
                    },
                    '$' => {
                        state = .identifier;
                        result.tag = .identifier;
                    },
                    'a'...'z', 'A'...'Z', '_' => {
                        state = .keyword;
                    },
                    '0'...'9' => {
                        state = .number_literal;
                        result.tag = .number_literal;
                    },
                    '(' => {
                        result.tag = .l_paren;
                        self.index += 1;
                        break;
                    },
                    ')' => {
                        result.tag = .r_paren;
                        self.index += 1;
                        break;
                    },
                    else => {
                        result.tag = .invalid;
                        result.loc.end = self.index;
                        self.index = std.unicode.utf8ByteSequenceLength(c) catch 1;
                        return result;
                    },
                },
                .number_literal => switch (c) {
                    '_', '0'...'9' => {},
                    else => break,
                },
                .string_literal => switch (c) {
                    '"' => {
                        self.index += 1;
                        break;
                    },
                    0 => {
                        result.tag = .invalid;
                        break;
                    },
                    else => {}
                },
                .identifier => switch (c) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                    else => {
                        if (Token.getKeyword(self.buffer[result.loc.start..self.index])) |tag| {
                            result.tag = tag;
                        }
                        break;
                    },
                },
                .keyword => switch (c) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                    else => {
                        if (Token.getKeyword(self.buffer[result.loc.start..self.index])) |tag| {
                            result.tag = tag;
                        } else {
                            result.tag = .identifier;
                        }
                        break;
                    },
                },
                .invalid => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        0 => if (self.index == self.buffer.len) {
                            result.tag = .invalid;
                        },
                        '\n' => result.tag = .invalid,
                        else => {},
                    }
                },
            }
        }
        if (result.tag == .eof) {
            result.loc.end = self.index;
        }
        result.loc.end = self.index;
        return result;
    }

    pub fn getTokenStr(self: *Lexer, token: Token) []const u8 {
        return self.buffer[token.loc.start..token.loc.end];
    }
};

const std = @import("std");
