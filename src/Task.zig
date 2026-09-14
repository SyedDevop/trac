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
priority: u64,
extra_properties: ?md.Map,
body: []const u8,
md_content: []const u8,

pub fn init(
    id: []const u8,
    title: []const u8,
    status: Status,
    tags: Tags,
    priority: u64,
    body: []const u8,
    md_content: []const u8,
) Task {
    return Task{
        .id = id,
        .title = title,
        .status = status,
        .tags = tags,
        .priority = priority,
        .body = body,
        .md_content = md_content,
        .extra_properties = null,
    };
}

pub fn initEmpty(id: []const u8, title: []const u8, tags: Tags, priority: u8) Task {
    return init(id, title, .OPEN, tags, priority, "No description.\n", "");
}

pub fn loadTasks(io: std.Io, alloc: std.mem.Allocator, tasks_re_path: []const u8) ![]Task {
    const cwd = std.Io.Dir.cwd();

    const tasks_dir = try cwd.openDir(io, tasks_re_path, .{ .iterate = true });
    defer tasks_dir.close(io);
    var tasks_it = tasks_dir.iterate();

    var stats: md.Map = .init(alloc);
    defer stats.deinit();

    var extra_properties: md.Map = .init(alloc);
    defer extra_properties.deinit();

    var tasks: std.ArrayList(Task) = .empty;
    while (try tasks_it.next(io)) |it| {
        if (!huid.isValid(it.name)) continue;
        // std.debug.print("Invalid HUID: {s}\n", .{it.name});

        if (it.kind != .directory) continue;
        // std.debug.print("Not a directory: {s}\n", .{it.name});

        const tasks_md_path = try std.fs.path.join(alloc, &.{ tasks_re_path, it.name, "TASK.md" });
        defer alloc.free(tasks_md_path);

        const tasks_md_file = cwd.readFileAlloc(io, tasks_md_path, alloc, .unlimited) catch |err| switch (err) {
            // std.debug.print("No TASK.md file in: {s}\n", .{it.name});
            error.FileNotFound => continue,
            else => return err,
        };

        var token = std.mem.tokenizeScalar(u8, tasks_md_file, '\n');

        stats.clearRetainingCapacity();
        extra_properties.clearRetainingCapacity();

        try stats.put("STATUS", "OPEN");
        try stats.put("PRIORITY", "999999");
        try stats.put("TAGS", "");

        var title: []const u8 = undefined;
        var content: []const u8 = "";

        if (md.parseTitle(&token, &title)) {
            try md.parseBody(&token, &stats, &extra_properties);
            content = token.rest();
        }

        const priority_i = try std.fmt.parseInt(u64, stats.get("PRIORITY").?, 10);
        var task = Task.init(
            try alloc.dupe(u8, it.name),
            title,
            .fromString(stats.get("STATUS").?),
            .empty,
            priority_i,
            content,
            tasks_md_file,
        );

        if (extra_properties.count() > 0) {
            task.extra_properties = try extra_properties.clone();
        }
        try task.tagsFromString(alloc, stats.get("TAGS").?);
        try tasks.append(alloc, task);
    }
    return tasks.toOwnedSlice(alloc);
}

pub fn newMdContent(self: *const Task, w: *std.Io.Writer) !void {
    try self.writeMd(w);
    try w.flush();
}

pub fn writeMd(self: *const Task, w: *std.Io.Writer) !void {
    try w.print("# {s}\n", .{self.title});
    try w.writeByte('\n');
    try w.print("- STATUS: {t}\n", .{self.status});
    try w.print("- PRIORITY: {d}\n", .{self.priority});

    try w.writeAll("- TAGS:");
    try writeTags(" ", self.tags.items, w);
    try w.writeByte('\n');
    if (self.extra_properties) |ep| {
        var it = ep.iterator();
        while (it.next()) |kv| {
            try w.print("- {s}: {s}\n", .{ kv.key_ptr.*, kv.value_ptr.* });
        }
    }
    try w.writeByte('\n');
    try w.writeAll(self.body);
}

pub fn tagsFromString(self: *Task, alloc: std.mem.Allocator, tags: []const u8) !void {
    if (tags.len <= 0) return;
    var tag_it = std.mem.splitAny(u8, tags, ", ");
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
pub fn removeTag(self: *Task, idx: usize) ![]const u8 {
    return self.tags.orderedRemove(idx);
}

pub fn tagIndex(self: *const Task, tag: []const u8) ?usize {
    for (self.tags.items, 0..) |t, i| if (std.mem.eql(u8, t, tag)) return i;
    return null;
}

pub fn hasTag(self: *const Task, tag: []const u8) bool {
    for (self.tags.items) |t| if (std.mem.eql(u8, t, tag)) return true;
    return false;
}

/// Frees a `Task` that was loaded from TASKS.md.
///
/// `md_content` owns the backing memory for the whole file; every
/// field in `Task` is just a slice into it, so freeing `md_content`
/// invalidates all of them. Call this only on a `Task` created by
/// loading TASKS.md from disk — i.e. via `loadTasks`.
pub fn deinit(self: *Task, alloc: std.mem.Allocator) void {
    alloc.free(self.id);
    self.tags.deinit(alloc);
    if (self.extra_properties) |*props| props.deinit();
    alloc.free(self.md_content);
}

const SortBy = enum { ID, PRIORITY };
const SortOrder = enum { ASC, DESC };
pub const SortCtx = struct { by: SortBy, order: SortOrder };

pub fn sortEq() fn (SortCtx, Task, Task) bool {
    return struct {
        pub fn inner(ctx: SortCtx, a: Task, b: Task) bool {
            switch (ctx.by) {
                .ID => {
                    return switch (ctx.order) {
                        .ASC => std.mem.lessThan(u8, a.id, b.id),
                        .DESC => std.mem.lessThan(u8, b.id, a.id),
                    };
                },
                .PRIORITY => {
                    return switch (ctx.order) {
                        .ASC => a.priority < b.priority,
                        .DESC => a.priority > b.priority,
                    };
                },
            }
        }
    }.inner;
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
