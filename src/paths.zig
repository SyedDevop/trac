const std = @import("std");

var base: [std.fs.max_path_bytes]u8 = undefined;
pub const TASKS_DIR = "tasks";

pub const TasksDbPaths = struct {
    found: bool,
    cwd: []u8,
    tasks_path: []u8,
    relative_path: []u8,

    pub fn init(io: std.Io, alloc: std.mem.Allocator) !TasksDbPaths {
        const pwd = try getCwdPath(io);
        const tasks_path = try findTasksDatabase(pwd, io, alloc);
        const relative_path = try std.fs.path.relativePosix(alloc, TASKS_DIR, pwd, tasks_path);
        return .{
            .found = tasks_path.len > 0,
            .cwd = pwd,
            .tasks_path = tasks_path,
            .relative_path = relative_path,
        };
    }

    pub fn deinit(self: TasksDbPaths, alloc: std.mem.Allocator) void {
        alloc.free(self.tasks_path);
        alloc.free(self.relative_path);
    }

    pub fn format(
        self: TasksDbPaths,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        const found = if (self.found) "Found" else "Did Not find";
        try writer.print("{s} {s} directory.\n", .{ found, TASKS_DIR });
        try writer.print("Paths: \n", .{});
        try writer.print("  Cwd      : {s}\n", .{self.cwd});
        try writer.print("  Tasks    : {s}\n", .{self.tasks_path});
        try writer.print("  Relative : {s}\n", .{self.relative_path});
    }
};

pub fn getCwdPath(io: std.Io) ![]u8 {
    const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer cwd.close(io);
    const path_len = try cwd.realPath(io, &base);
    return base[0..path_len];
}

pub fn findTasksDatabase(path: []const u8, io: std.Io, alloc: std.mem.Allocator) ![]u8 {
    var comp = std.fs.path.componentIterator(path);
    comp.start_index = comp.path.len;
    comp.end_index = 0;
    const cwd_dir = std.Io.Dir.cwd();

    while (comp.previous()) |c| {
        var cwd = try cwd_dir.openDir(io, c.path, .{ .iterate = true });
        defer cwd.close(io);
        var cwd_it = cwd.iterate();
        while (try cwd_it.next(io)) |it| {
            if (it.kind == .directory and std.mem.eql(u8, it.name, TASKS_DIR)) {
                return try std.fs.path.join(alloc, &.{ c.path, it.name });
            }
        }
    }
    return "";
}
