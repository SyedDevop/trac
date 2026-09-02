const std = @import("std");
const TimePart = @import("TimePart.zig");

pub const FMT = "{d:0>2}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}";

pub fn new(io: std.Io, alloc: std.mem.Allocator, suffix: ?[]const u8) ![]u8 {
    const now = try TimePart.now(io);
    const args = .{ now.year, now.month, now.day, now.hour, now.min, now.sec };
    if (suffix) |sfx| if (sfx.len > 0) {
        return try std.fmt.allocPrint(alloc, FMT ++ "-{s}", args ++ .{sfx});
    };
    return try std.fmt.allocPrint(alloc, FMT, args);
}

pub fn isAlphaNumOrDash(x: u8) bool {
    return std.ascii.isAlphanumeric(x) or x == '-';
}
const isDigit = std.ascii.isDigit;
pub fn isValid(huid: []const u8) bool {
    if (huid.len < 16) return false;
    for (huid, 0..) |v, i| {
        switch (i) {
            0...7 => if (!isDigit(v)) return false,
            8 => if (v != '-') return false,
            9...14 => if (!isDigit(v)) return false,
            else => {
                if (i == 15) {
                    if (huid.len < 17) return false;
                    if (v != '-') return false;
                }
                if (!isAlphaNumOrDash(v)) return false;
            },
        }
    }
    return true;
}

const testing = std.testing;
test "isValid: well-formed HUID with alnum tail" {
    try testing.expect(isValid("12345678-123456-AB12-cd"));
}
test "isValid: minimal 16-char HUID (both dashes only, no tail)" {
    try testing.expect(!isValid("12345678-123456-"));
}

test "isValid: tail may itself contain dashes" {
    try testing.expect(isValid("12345678-123456-a-b-c-9"));
}

test "isValid: rejects" {
    try testing.expect(!isValid(""));
    try testing.expect(!isValid("1234567A-123456-x"));
    try testing.expect(!isValid("123456780123456-x"));
    try testing.expect(!isValid("12345678-12345A-x"));
    try testing.expect(!isValid("12345678-123456Xx"));
    try testing.expect(!isValid("12345678-123456-A_B"));
    try testing.expect(!isValid("12345678-123456-A B"));
    try testing.expect(!isValid("1234567"));
    try testing.expect(!isValid("12345678"));
    try testing.expect(!isValid("12345678-"));
}
