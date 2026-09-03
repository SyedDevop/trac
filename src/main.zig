const std = @import("std");

const zarg = @import("zarg");
const Cli = zarg.Cli;
const Arg = Cli.Arg;
const Cmd = @import("cmds.zig");
const Task = @import("Task.zig");
const HUID = @import("huid.zig");
const paths = @import("paths.zig");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_io = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    var stdout = &stdout_io.interface;

    const allocator = init.gpa;

    var cli = try Cli.CliInit(Cmd.Cmds).init(
        allocator,
        Cmd.Name,
        Cmd.DESCRIPTION,
        .{ .str = "v0.0.1" },
        &Cmd.CMD_LIST,
    );
    defer cli.deinit();

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    cli.parse(args) catch |err| {
        try cli.printParseError(err, stdout);
        try stdout.flush();
        return;
    };

    const tasks_db = try paths.TasksDbPaths.init(init.io, allocator);
    defer tasks_db.deinit(allocator);

    switch (cli.running_cmd.name) {
        .root => unreachable,
        .init => {
            const cwd = std.Io.Dir.cwd();
            cwd.createDir(init.io, paths.TASKS_DIR, .default_dir) catch |err| {
                if (err == error.PathAlreadyExists) {
                    std.log.info("Tasks '" ++ paths.TASKS_DIR ++ "' directory already exists.", .{});
                    return;
                }
                return err;
            };
            std.log.info("Tasks '" ++ paths.TASKS_DIR ++ "' directory initialized.", .{});
        },
        .ls => {
            std.debug.print("{f}", .{tasks_db});
        },
        .new => {
            var title = try cli.getAllPosArgAsStr();
            if (title == null or title.?.len <= 0) {
                title = try allocator.dupe(u8, "New task");
            }
            defer allocator.free(title.?);
            const safe_title = std.mem.trim(u8, title.?, " \t\n\r");
            const priority_i = try cli.getNumArg("priority") orelse 100;
            const priority = absClampToUnsigned(u8, priority_i);

            const tags = try findAllTags(cli.computed_args.data.items, allocator);
            defer allocator.free(tags);

            const suffix = try cli.getStrArg("suffix");
            const huid = try HUID.new(init.io, allocator, suffix);
            defer allocator.free(huid);

            const task = Task.initEmpty(huid, safe_title, tags, priority);
            const cwd = std.Io.Dir.cwd();

            if (!tasks_db.found) {
                std.log.err("'" ++ paths.TASKS_DIR ++ "' directory not found. Run `init` first to set up the tasks database.", .{});
                return;
            }

            const tasks_db_dir = try cwd.openDir(init.io, tasks_db.relative_path, .{});
            defer tasks_db_dir.close(init.io);

            const new_task_dir = tasks_db_dir.createDirPathOpen(init.io, huid, .{}) catch |err| {
                if (err == error.PathAlreadyExists) {
                    std.log.err("Task '{s}' already exists. This can happen if tasks are created to fast, or if system time is off — try again.", .{huid});
                    return;
                }
                return err;
            };
            defer new_task_dir.close(init.io);

            const file = new_task_dir.createFile(init.io, "TASK.md", .{ .exclusive = true }) catch |err| {
                if (err == error.PathAlreadyExists) {
                    std.log.err("Task '{s}' exists but its TASK.md is missing or was already created — refusing to overwrite.", .{huid});
                    return;
                }
                return err;
            };
            defer file.close(init.io);

            var file_w = file.writer(init.io, &.{});
            const sb_w = &file_w.interface;
            try task.newMdContent(sb_w);

            try stdout.print("{f}\n", .{task.dump(tasks_db.relative_path)});
            try stdout.flush();
        },
        .find => std.log.info("TODO: {t} cmd is not implemented yet", .{cli.running_cmd.name}),
        .graph => std.log.info("TODO: {t} cmd is not implemented yet", .{cli.running_cmd.name}),
        .ref => std.log.info("TODO: {t} cmd is not implemented yet", .{cli.running_cmd.name}),
        .summary => std.log.info("TODO: {t} cmd is not implemented yet", .{cli.running_cmd.name}),
    }
}

fn findAllTags(args: []Arg, alloc: std.mem.Allocator) ![][]const u8 {
    var tags_list: std.ArrayList([]const u8) = .empty;
    for (args) |arg| {
        if (arg.long != null and !std.mem.eql(u8, arg.long.?, "tags")) continue;
        if (arg.value != .str) continue;
        if (arg.value.str) |t| {
            try tags_list.append(alloc, t);
        }
    }
    return try tags_list.toOwnedSlice(alloc);
}
fn absClampToUnsigned(T: type, value: anytype) T {
    comptime {
        switch (@typeInfo(T)) {
            .int => |i| if (i.signedness != .unsigned)
                @compileError("T must be an unsigned integer type"),
            else => @compileError("T must be an integer type"),
        }
    }

    return @min(std.math.maxInt(T), @abs(value));
}
