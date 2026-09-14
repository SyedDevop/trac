const std = @import("std");

pub const Source = std.mem.TokenIterator(u8, .scalar);
pub const Map = std.StringHashMap([]const u8);

pub fn trimSpace(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " ");
}

pub fn expectAndChop(str: *[]const u8, ex: u8) bool {
    if (str.*.len <= 0) return false;
    if (str.*[0] == ex) {
        str.len -= 1;
        str.ptr += 1;
        return true;
    }
    return false;
}

pub const Properties = struct {
    K: []const u8,
    V: []const u8,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("Key |{s}|, Value |{s}|", .{ self.K, self.V });
    }
};

pub const PropertiesError = error{NotPropertiesStr};

pub fn parseProperties(str: []const u8) PropertiesError!?Properties {
    var safe_str = trimSpace(str);
    if (!expectAndChop(&safe_str, '-')) return PropertiesError.NotPropertiesStr;
    safe_str = trimSpace(safe_str);

    const key_idx = std.mem.indexOf(u8, safe_str, ":");
    if (key_idx == null) return null;

    const key = trimSpace(safe_str[0..key_idx.?]);
    const value = trimSpace(safe_str[key_idx.? + 1 ..]);
    return .{ .K = key, .V = value };
}

pub fn parseTitle(str: *Source, title: *[]const u8) bool {
    title.* = std.mem.trim(u8, str.next() orelse "", " \t\n\r");
    if (title.len <= 0) {
        title.* = "!!! INVALID: TASK TITLE IS EMPTY !!!";
        return false;
    } else if (title.*[0] != '#') {
        title.* = "!!! INVALID: TASK TITLE MUST START WITH # !!!";
        return false;
    }
    title.* = std.mem.trimStart(u8, title.*, "# ");
    return true;
}

pub fn parseBody(str: *Source, main_properties: *Map, extra_properties: *Map) !void {
    var cur_index = str.index;
    while (str.next()) |line| {
        defer cur_index = str.index;

        const safe_line = trimSpace(line);
        if (safe_line.len <= 0) unreachable;
        const prop = parseProperties(safe_line) catch |err| switch (err) {
            error.NotPropertiesStr => {
                str.index = cur_index;
                //return false;
                return;
            },
        };
        if (prop) |p| {
            if (main_properties.contains(p.K)) {
                try main_properties.put(p.K, p.V);
            } else {
                try extra_properties.put(p.K, p.V);
            }
        } else continue;
    }
    //return true;
}
