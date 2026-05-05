const std = @import("std");

const Lexer = @This();

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
        .{ "let", .kw_let },
        .{ "in", .kw_in },
        .{ "match", .kw_match },
        .{ "with", .kw_with },
        .{ "module", .kw_module },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        identifier,
        number_literal,
        string_literal,
        atom_literal,

        r_paren,
        l_paren,
        comma,
        equal,
        arrow,
        pipe,

        kw_let,
        kw_in,
        kw_match,
        kw_with,
        kw_module,

        comment,
        invalid,
        eof,
    };
};

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
    number_literal,
    string_literal,
    atom_literal,
    identifier,

    keyword,
    comment,
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
    token_loop: while (true) : (self.index += 1) {
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
                    break :token_loop;
                },
                ' ', '\n', '\t', '\r' => {
                    result.loc.start = self.index + 1;
                    if (c == '\n') {
                        self.currentLine += 1;
                        self.currentLineOffset = 0;
                    }
                    result.line = self.currentLine;
                    result.lineOffset = self.currentLineOffset;
                },
                '"' => {
                    state = .string_literal;
                    result.tag = .string_literal;
                },
                ';' => {
                    state = .comment;
                },
                ':' => {
                    state = .atom_literal;
                    result.tag = .atom_literal;
                },
                '$' => {
                    state = .identifier;
                    result.tag = .identifier;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    state = .keyword;
                },
                '(' => {
                    result.tag = .l_paren;
                    self.index += 1;
                    break :token_loop;
                },
                ')' => {
                    result.tag = .r_paren;
                    self.index += 1;
                    break :token_loop;
                },
                ',' => {
                    result.tag = .comma;
                    self.index += 1;
                    break :token_loop;
                },
                '|' => {
                    result.tag = .pipe;
                    self.index += 1;
                    break :token_loop;
                },
                '=' => {
                    if (self.index + 1 < self.buffer.len and self.buffer[self.index + 1] == '>') {
                        result.tag = .arrow;
                        self.index += 2;
                    } else {
                        result.tag = .equal;
                        self.index += 1;
                    }
                    break :token_loop;
                },
                '-' => {
                    if (self.index + 1 < self.buffer.len and self.buffer[self.index + 1] == '>') {
                        result.tag = .arrow;
                        self.index += 2;
                        break :token_loop;
                    } else if (self.index + 1 < self.buffer.len and (self.buffer[self.index + 1] >= '0' and self.buffer[self.index + 1] <= '9')) {
                        state = .number_literal;
                        result.tag = .number_literal;
                    } else {
                        result.tag = .invalid;
                        result.loc.end = self.index + 1;
                        self.index += 1;
                        return result;
                    }
                },
                '0'...'9' => {
                    state = .number_literal;
                    result.tag = .number_literal;
                },
                else => {
                    result.tag = .invalid;
                    result.loc.end = self.index + 1;
                    self.index += 1;
                    return result;
                },
            },
            .number_literal => switch (c) {
                '_', '0'...'9' => {},
                else => break :token_loop,
            },
            .string_literal => switch (c) {
                '"' => {
                    self.index += 1;
                    break :token_loop;
                },
                0 => {
                    result.tag = .invalid;
                    break :token_loop;
                },
                else => {},
            },
            .atom_literal => switch (c) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                else => break :token_loop,
            },
            .identifier => switch (c) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                else => break :token_loop,
            },
            .keyword => switch (c) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                else => {
                    if (Token.getKeyword(self.buffer[result.loc.start..self.index])) |tag| {
                        result.tag = tag;
                    } else {
                        result.tag = .identifier;
                    }
                    break :token_loop;
                },
            },
            .comment => switch (c) {
                '\n' => {
                    state = .start;
                    self.currentLine += 1;
                    self.currentLineOffset = 0;
                    result.loc.start = self.index + 1; // start of next potential token
                },
                0 => {
                    if (self.index == self.buffer.len) {
                        result.tag = .eof;
                    } else {
                        result.tag = .invalid;
                    }
                    break :token_loop;
                },
                else => {},
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
