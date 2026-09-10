const std = @import("std");

const Tokenizer = struct {
    src: []const u8,
    cursor: usize,
    pub fn init(src: []const u8) Tokenizer {
        return .{
            .src = src,
            .cursor = 0,
        };
    }

    pub fn next(self: *Tokenizer) []const u8 {
        if (!self.isSafeStep()) return "";
        self.trimLeft();
        if (self.isChar('[') or self.isChar(']')) return self.chopLeft(1);
        const start = self.cursor;
        while (self.isNotBracketOrSpace()) self.cursor += 1;
        return self.src[start..self.cursor];
    }

    pub fn peek(self: *Tokenizer) []const u8 {
        const start = self.cursor;
        const str = self.next();
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
};

const OpCode = union(enum) {
    op_any,
    op_not,
    op_or,
    op_and,
    op_tagged,
    op_priority,
    op_lt,
    op_gt,
    op_lte,
    op_gte,
    op_eq,
    op_neq,
    op_tag: []const u8,
    op_integer: u64,
};

const Op = struct {
    op: OpCode,
    loc: usize,
};

test {
    _ = Tokenizer;
}
