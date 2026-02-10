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
        //.{ "print", .keyword_print },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        number_literal,
        int,
        r_paren,
        l_paren,
        identifier,
        comment,
        invalid,
        eof,
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
        int,
        identifier,
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
                    ';' => {
                        while (self.buffer[self.index + 1] != 0 and self.buffer[self.index + 1] != '\n') : (self.index += 1) {}
                        continue;
                    },
                    'a'...'z', 'A'...'Z', '_' => {
                        state = .identifier;
                        result.tag = .identifier;
                    },
                    '0'...'9' => {
                        state = .int;
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
                .int => switch (c) {
                    '_', '0'...'9' => {},
                    else => break,
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
};

const std = @import("std");
