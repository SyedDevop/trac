const std = @import("std");
const huid = @import("huid.zig");
const md = @import("md.zig");
const Task = @This();

pub const Status = enum {
    OPEN,
    CLOSED,

    /// Returns the Status from a string
    /// Returns OPEN if the string is not a valid Status
    pub fn fromString(str: []const u8) Status {
        return std.meta.stringToEnum(Task.Status, str) orelse .OPEN;
    }
};

pub const Tags = std.ArrayList([]const u8);

id: []const u8,
title: []const u8,
status: Status,
tags: Tags,
priority: u32,
md_content: []const u8,

pub fn init(
    id: []const u8,
    title: []const u8,
    status: Status,
    tags: Tags,
    priority: u32,
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

/// Make shore the `Allocator` is from ArenaAllocator
/// Because we wont free the TASKS.md and path and etc..
/// The Task hold's the slices for all the string data
pub fn loadTasks(io: std.Io, arena: std.mem.Allocator, tasks_re_path: []const u8) ![]Task {
    const cwd = std.Io.Dir.cwd();

    const tasks_dir = try cwd.openDir(io, tasks_re_path, .{ .iterate = true });
    defer tasks_dir.close(io);

    var tasks: std.ArrayList(Task) = .empty;

    var tasks_it = tasks_dir.iterate();
    while (try tasks_it.next(io)) |it| {
        if (!huid.isValid(it.name)) continue;
        // std.debug.print("Invalid HUID: {s}\n", .{it.name});

        if (it.kind != .directory) continue;
        // std.debug.print("Not a directory: {s}\n", .{it.name});

        const tasks_md_path = try std.fs.path.join(arena, &.{ tasks_re_path, it.name, "TASK.md" });
        const tasks_md_file = cwd.readFileAlloc(io, tasks_md_path, arena, .unlimited) catch |err| switch (err) {
            // std.debug.print("No TASK.md file in: {s}\n", .{it.name});
            error.FileNotFound => continue,
            else => return err,
        };

        //TODO: Can This be initialized before the loop?
        var token = std.mem.tokenizeScalar(u8, tasks_md_file, '\n');
        var stats = std.StringHashMap([]const u8).init(arena);
        try stats.put("STATUS", "OPEN");
        try stats.put("PRIORITY", "999999");
        try stats.put("TAGS", "");

        var title: []const u8 = undefined;
        var content: []const u8 = "";

        if (md.parseTitle(&token, &title)) {
            _ = try md.parseBody(&token, &stats);
            content = token.rest();
        }

        const priority_i = try std.fmt.parseInt(u32, stats.get("PRIORITY").?, 10);
        var task = Task.init(
            try arena.dupe(u8, it.name),
            title,
            .fromString(stats.get("STATUS").?),
            .empty,
            priority_i,
            content,
        );
        try task.tagsFromString(arena, stats.get("TAGS").?);
        try tasks.append(arena, task);
    }
    return tasks.toOwnedSlice(arena);
}

pub fn newMdContent(self: *const Task, w: *std.Io.Writer) !void {
    try w.print("# {s}\n", .{self.title});
    try w.writeByte('\n');
    try w.print("- STATUS: {t}\n", .{self.status});
    try w.print("- PRIORITY: {d}\n", .{self.priority});

    try w.writeAll("- TAGS:");
    try writeTags(" ", self.tags.items, w);
    try w.writeByte('\n');

    try w.writeByte('\n');
    try w.writeAll("No description.\n");
    try w.flush();
}

pub fn tagsFromString(self: *Task, alloc: std.mem.Allocator, tags: []const u8) !void {
    if (tags.len <= 0) return;
    var tag_it = std.mem.splitScalar(u8, tags, ',');
    while (tag_it.next()) |tag| {
        const safe_tag = md.trimSpace(tag);
        if (safe_tag.len > 0) {
            try self.addTags(alloc, safe_tag);
        }
    }
}

pub fn addTags(self: *Task, alloc: std.mem.Allocator, tag: []const u8) !void {
    try self.tags.append(alloc, tag);
}

pub fn deinit(self: *Task, alloc: std.mem.Allocator) void {
    self.tags.deinit(alloc);
}

const Dump = struct {
    relative_path: []const u8,
    task: *const Task,

    pub fn format(self: Dump, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const task = self.task;
        try writer.print("{s}/{s}/TASK.md:1: ({t:>6}) [PRIORITY: {d: >3}", .{ self.relative_path, task.id, task.status, task.priority });
        try writeTags(", TAGS: ", task.tags.items, writer);
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

pub fn writeTags(prefix: []const u8, tags: []const []const u8, w: *std.Io.Writer) !void {
    if (tags.len <= 0) return;
    try w.writeAll(prefix);
    for (tags, 0..) |tag, i| {
        if (i > 0) try w.writeAll(", ");
        try w.writeAll(tag);
    }
}

pub fn tagsHas(tags: Tags, tag: []const u8) bool {
    for (tags) |t| if (std.mem.eql(u8, t, tag)) return true;
    return false;
}
