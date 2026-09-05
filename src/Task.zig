const std = @import("std");
const Task = @This();

pub const Status = enum { OPEN, CLOSED };
pub const Tags = []const []const u8;

id: []const u8,
title: []const u8,
status: Status,
tags: []const []const u8,
priority: u8,
md_content: []const u8,

pub fn init(
    id: []const u8,
    title: []const u8,
    status: Status,
    tags: Tags,
    priority: u8,
    md_content: []const u8,
) Task {
    return Task{
        .id = id,
        .title = title,
        .status = status,
        .tags = tags,
        .priority = priority,
        .md_content = md_content,
    };
}

pub fn initEmpty(id: []const u8, title: []const u8, tags: Tags, priority: u8) Task {
    return init(id, title, .OPEN, tags, priority, "No description.\n");
}

pub fn newMdContent(self: *const Task, w: *std.Io.Writer) !void {
    try w.print("# {s}\n", .{self.title});
    try w.writeByte('\n');
    try w.print("- STATUS: {t}\n", .{self.status});
    try w.print("- PRIORITY: {d}\n", .{self.priority});

    try w.writeAll("- TAGS:");
    try writeTags(" ", self.tags, w);
    try w.writeByte('\n');

    try w.writeByte('\n');
    try w.writeAll("No description.\n");
    try w.flush();
}

const Dump = struct {
    relative_path: []const u8,
    task: *const Task,

    pub fn format(self: Dump, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const task = self.task;
        try writer.print("{s}/{s}/TASK.md:1: [PRIORITY: {d: >3}", .{ self.relative_path, task.id, task.priority });
        try writeTags(", TAGS: ", task.tags, writer);
        try writer.print("] {s}", .{task.title});
    }
};

pub fn dump(task: *const Task, relative_path: []const u8) Dump {
    return .{
        .task = task,
        .relative_path = relative_path,
    };
}

// @section:Tags------------------------------------

pub fn writeTags(prefix: []const u8, tags: Tags, w: *std.Io.Writer) !void {
    if (tags.len <= 0) return;
    try w.writeAll(prefix);
    for (tags, 0..) |tag, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll(tag);
    }
}

pub fn tagsHas(tags: Tags, tag: []const u8) bool {
    for (tags) |t| if (std.mem.eql(u8, t, tag)) return true;
    return false;
}
