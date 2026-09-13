const std = @import("std");

const Tokenizer = @This();

src: []const u8,
cursor: usize,

/// This holds the start of the token position. While cursor is the current
/// position aka end of the token
token_pos: usize,

pub fn init(src: []const u8) Tokenizer {
    return .{
        .src = src,
        .cursor = 0,
        .token_pos = 0,
    };
}

pub fn itNext(self: *Tokenizer) ?[]const u8 {
    const tok = self._next();
    if (tok.len == 0) return null;
    return tok;
}

fn _next(self: *Tokenizer) []const u8 {
    if (!self.isSafeStep()) return "";
    self.trimLeft();
    if (self.isChar('[') or self.isChar(']')) return self.chopLeft(1);
    const start = self.cursor;
    while (self.isNotBracketOrSpace()) self.cursor += 1;
    return self.src[start..self.cursor];
}

pub fn next(self: *Tokenizer) []const u8 {
    const tok = self._next();
    self.token_pos = self.cursor - tok.len;
    return tok;
}

pub fn reset(self: *Tokenizer) void {
    self.cursor = 0;
    self.token_pos = 0;
}

pub fn peek(self: *Tokenizer) []const u8 {
    const start = self.cursor;
    const str = self._next();
    self.cursor = start;
    return str;
}

pub fn trimLeft(self: *Tokenizer) void {
    while (self.isSafeStep() and self.isSpace()) {
        self.cursor += 1;
    }
}

pub fn isNotBracketOrSpace(self: Tokenizer) bool {
    return !self.isBracket() and !self.isSpace();
}

pub fn isBracket(self: Tokenizer) bool {
    return self.isChar('[') or self.isChar(']');
}

pub fn isSpace(self: Tokenizer) bool {
    if (!self.isSafeStep()) return true;
    return std.ascii.isWhitespace(self.src[self.cursor]);
}

pub fn isSafeStep(self: Tokenizer) bool {
    return self.cursor < self.src.len;
}

pub fn char(self: Tokenizer) u8 {
    const cur = @min(self.src.len - 1, self.cursor);
    return self.src[cur];
}

pub fn isChar(self: Tokenizer, x: u8) bool {
    return x == self.char();
}

pub fn chopLeft(self: *Tokenizer, n: usize) []const u8 {
    const num = @min(self.src.len - self.cursor, n);
    defer self.cursor += num;
    return self.src[self.cursor .. self.cursor + num];
}

test "itNext" {
    var t = Tokenizer.init(" world [Hahaha] ");
    try std.testing.expectEqualSlices(u8, "world", t.itNext().?);
    try std.testing.expectEqualSlices(u8, "[", t.itNext().?);
    try std.testing.expectEqualSlices(u8, "Hahaha", t.itNext().?);
    try std.testing.expectEqualSlices(u8, "]", t.itNext().?);
    try std.testing.expectEqual(null, t.itNext());
    try std.testing.expectEqual(null, t.itNext());
}

test "next" {
    var t = Tokenizer.init(" Hello This is my world [Hahaha] ");
    try std.testing.expectEqualSlices(u8, "Hello", t.next());
    try std.testing.expectEqualSlices(u8, "This", t.next());
    try std.testing.expectEqualSlices(u8, "is", t.next());
    try std.testing.expectEqualSlices(u8, "my", t.next());
    try std.testing.expectEqualSlices(u8, "world", t.next());
    try std.testing.expectEqualSlices(u8, "[", t.next());
    try std.testing.expectEqualSlices(u8, "Hahaha", t.next());
    try std.testing.expectEqualSlices(u8, "]", t.next());
    try std.testing.expectEqualSlices(u8, "", t.next());
}
test "chopLeft" {
    var t = Tokenizer.init("abc ");
    try std.testing.expectEqualSlices(u8, "ab", t.chopLeft(2));
    try std.testing.expectEqualSlices(u8, "c ", t.chopLeft(2));
    try std.testing.expectEqualSlices(u8, "", t.chopLeft(2));
}

test "trimLeft" {
    var t = Tokenizer.init("abc ");
    try std.testing.expectEqualSlices(u8, "abc", t.next());
    try std.testing.expectEqualSlices(u8, "", t.next());
}
