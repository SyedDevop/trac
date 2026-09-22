const std = @import("std");

const zarg = @import("zarg");
const Cli = zarg.Cli;
const Arg = Cli.Arg;
const Cmd = @import("cmds.zig");
const Task = @import("Task.zig");
const HUID = @import("huid.zig");
const paths = @import("paths.zig");
const md = @import("md.zig");
const Tokenizer = @import("Tokenizer.zig");
const Query = @import("Query.zig");

pub fn main(init: std.process.Init) !u8 {
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
        return 1;
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
                    return 1;
                }
                return err;
            };
            std.log.info("Tasks '" ++ paths.TASKS_DIR ++ "' directory initialized.", .{});
        },
        .ls => {
            if (!tasks_db.foundPath()) return 1;

            const closed = try cli.getBoolArg("closed");
            const state: Task.Status = if (closed) .CLOSED else .OPEN;

            const tasks = try Task.loadTasks(init.io, allocator, tasks_db.relative_path);
            defer {
                for (tasks) |*ta| ta.deinit(allocator);
                allocator.free(tasks);
            }

            if (tasks.len == 0) {
                std.log.info("No tasks found.", .{});
                return 0;
            }

            const order_asc = try cli.getBoolArg("ascending");
            const by_id = try cli.getBoolArg("id");

            std.mem.sortUnstable(
                Task,
                tasks,
                Task.SortCtx{
                    .by = if (by_id) .ID else .PRIORITY,
                    .order = if (order_asc) .ASC else .DESC,
                },
                Task.sortEq(),
            );

            var input = try cli.getAllPosArgAsStr() orelse "";
            defer allocator.free(input);
            if (input.len == 0) {
                input = try allocator.dupe(u8, "any");
            }

            var query = Query.init(allocator, input);
            defer query.deinit(allocator);
            query.parse() catch {
                std.debug.print("{s}", .{query.err_msg.items});
                return 1;
            };

            const debug = try cli.getBoolArg("debug");
            if (debug) {
                try stdout.print("{f}", .{&query});
                try stdout.flush();
                return 0;
            }
            const all = try cli.getBoolArg("A");
            const json = try cli.getBoolArg("json");
            if (json) try stdout.writeAll("[");
            var i: usize = 0;
            for (tasks) |ta| {
                if (!all and ta.status != state) continue;
                const matched = query.matchTask(allocator, &ta) catch |err| switch (err) {
                    error.InvalidStack => {
                        std.debug.print("{s}", .{query.err_msg.items});
                        return 1;
                    },
                    else => return err,
                };
                if (matched) {
                    if (json) {
                        if (i > 0) try stdout.writeByte(',');
                        try stdout.print("\n{f}", .{ta.dump(tasks_db.relative_path, .json)});
                        i += 1;
                    } else {
                        try stdout.print("{f}\n", .{ta.dump(tasks_db.relative_path, .default)});
                    }
                }
            }
            if (json) try stdout.writeAll("]\n");
            try stdout.flush();
        },

        .untag => {
            if (!tasks_db.foundPath()) return 1;

            const closed = try cli.getBoolArg("closed");
            var tags = try findAllTags(cli.computed_args.data.items, allocator);
            defer tags.deinit(allocator);

            const state: Task.Status = if (closed) .CLOSED else .OPEN;

            const tasks = try Task.loadTasks(init.io, allocator, tasks_db.relative_path);
            defer {
                for (tasks) |*ta| ta.deinit(allocator);
                allocator.free(tasks);
            }

            if (tasks.len == 0) {
                std.log.info("No tasks found.", .{});
                return 0;
            }

            std.mem.sortUnstable(
                Task,
                tasks,
                Task.SortCtx{ .by = .PRIORITY, .order = .ASC },
                Task.sortEq(),
            );
            const input = try cli.getAllPosArgAsStr() orelse "";
            defer allocator.free(input);
            if (input.len == 0) {
                std.log.err("No query is provided\n", .{});
            }

            var query = Query.init(allocator, input);
            defer query.deinit(allocator);
            query.parse() catch {
                std.debug.print("{s}", .{query.err_msg.items});
                return 1;
            };

            var writeBuf: [1024]u8 = undefined;
            var needUpdate = false;
            var updates: usize = 0;
            for (tasks) |*ta| {
                if (ta.status != state) continue;
                const matched = query.matchTask(allocator, ta) catch |err| switch (err) {
                    error.InvalidStack => {
                        std.debug.print("{s}", .{query.err_msg.items});
                        return 1;
                    },
                    else => return err,
                };
                if (!matched) continue;

                needUpdate = false;
                for (tags.items) |it| {
                    if (ta.tagIndex(it)) |idx| {
                        _ = try ta.removeTag(idx);
                        needUpdate = true;
                    }
                }
                if (needUpdate) {
                    const path = try tasks_db.tasksMdPath(allocator, ta.id);
                    defer allocator.free(path);

                    const file = try std.Io.Dir.cwd().openFile(init.io, path, .{ .mode = .read_write });
                    defer file.close(init.io);
                    try file.setLength(init.io, 0);
                    var file_w = file.writer(init.io, &writeBuf);
                    try ta.writeMd(&file_w.interface);
                    try file_w.flush();
                    updates += 1;
                }
            }

            std.log.info("{d} tasks updated\n", .{updates});
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

            var tags = try findAllTags(cli.computed_args.data.items, allocator);
            defer tags.deinit(allocator);

            const suffix = try cli.getStrArg("suffix");
            const huid = try HUID.new(init.io, allocator, suffix);
            defer allocator.free(huid);

            var task = Task.initEmpty(huid, safe_title, tags, priority);
            //defer task.deinit(allocator);
            const body = try cli.getStrArg("body") orelse "";
            if (body.len > 0) task.body = body;

            const cwd = std.Io.Dir.cwd();

            if (!tasks_db.foundPath()) return 1;

            const tasks_db_dir = try cwd.openDir(init.io, tasks_db.relative_path, .{});
            defer tasks_db_dir.close(init.io);

            const new_task_dir = tasks_db_dir.createDirPathOpen(init.io, huid, .{}) catch |err| {
                if (err == error.PathAlreadyExists) {
                    std.log.err("Task '{s}' already exists. This can happen if tasks are created to fast, or if system time is off — try again.", .{huid});
                    return 1;
                }
                return err;
            };
            defer new_task_dir.close(init.io);

            const file = new_task_dir.createFile(init.io, "TASK.md", .{ .exclusive = true }) catch |err| {
                if (err == error.PathAlreadyExists) {
                    std.log.err("Task '{s}' exists but its TASK.md is missing or was already created — refusing to overwrite.", .{huid});
                    return 1;
                }
                return err;
            };
            defer file.close(init.io);

            var file_w = file.writer(init.io, &.{});
            const sb_w = &file_w.interface;
            try task.newMdContent(sb_w);

            try stdout.print("{f}\n", .{task.dump(tasks_db.relative_path, .default)});
            try stdout.flush();
        },

        .ref => {
            if (!tasks_db.foundPath()) return 1;

            var huid: ?[]const u8 = null;
            if (cli.pos_args) |pos_args| for (pos_args) |pos_arg| {
                if (huid != null) {
                    std.log.err("Several HUIDs is not supported", .{});
                    return 1;
                }
                if (!HUID.isValid(pos_arg)) {
                    std.log.err("`{s}` is not a valid HUID. Valid HUID matches regexp `{s}`", .{ pos_arg, HUID.REGEX });
                    return 1;
                }
                huid = pos_arg;
            };

            var path: []const u8 = tasks_db.cwd;

            if (huid == null) {
                var comp = std.fs.path.componentIterator(tasks_db.cwd);
                comp.start_index = comp.path.len;
                comp.end_index = 0;
                huid = while (comp.previous()) |c| {
                    if (HUID.isValid(c.name)) {
                        path = c.path;
                        break c.name;
                    }
                } else {
                    std.log.err("You are not inside any task folder. Pass the ID of a task as an argument to search for referers of that task.", .{});
                    return 1;
                };
            }

            const grep_path = try std.fs.path.join(
                allocator,
                &.{ tasks_db.relative_path, "/.." },
            );

            defer allocator.free(grep_path);
            const argv: []const []const u8 = &.{
                "grep",
                "--exclude-dir=.git",
                "-Irn",
                huid.?,
                grep_path,
            };

            try stdout.writeAll("CMD: ");
            for (argv) |v| try stdout.print("{s} ", .{v});
            try stdout.writeByte('\n');
            try stdout.flush();

            const ter = try std.process.run(allocator, init.io, .{
                .cwd = .{ .path = path },
                .argv = argv,
            });
            defer allocator.free(ter.stdout);
            defer allocator.free(ter.stderr);

            try stdout.print("{s}", .{ter.stdout});
            try stdout.print("{s}", .{ter.stderr});
            try stdout.flush();
        },

        .summary => {
            if (!tasks_db.foundPath()) return 1;

            const closed = try cli.getBoolArg("closed");
            const state: Task.Status = if (closed) .CLOSED else .OPEN;

            const arena = init.arena.allocator();
            defer {
                // printArenaState(init.arena);
                _ = init.arena.reset(.free_all);
            }

            const tasks = try Task.loadTasks(init.io, arena, tasks_db.relative_path);
            var tag_map = std.StringHashMap(usize).init(allocator);
            defer tag_map.deinit();

            var total: usize = 0;
            var untagged: usize = 0;
            for (tasks) |task| {
                if (task.status != state) continue;

                total += 1;
                if (task.tags.items.len == 0) untagged += 1;

                for (task.tags.items) |tag| {
                    const entry = try tag_map.getOrPut(tag);
                    if (entry.found_existing) entry.value_ptr.* += 1 else entry.value_ptr.* = 1;
                }
            }

            try stdout.print("STATUS:    {t}\n", .{state});
            try stdout.print("TOTAL:     {d}\n", .{total});
            if (untagged > 0)
                try stdout.print("UNTAGGED:  {d}\n", .{untagged});

            if (tag_map.count() > 0) try stdout.print("TAGGED:\n", .{});
            var tag_it = tag_map.iterator();
            while (tag_it.next()) |it| {
                try stdout.print(" {s:>7} => {d}\n", .{ it.key_ptr.*, it.value_ptr.* });
            }
            try stdout.flush();
        },

        .find => {
            if (!tasks_db.foundPath()) return 1;

            var huid: ?[]const u8 = null;
            if (cli.pos_args) |pos_args| for (pos_args) |pos_arg| {
                if (huid != null) {
                    std.log.err("Several HUIDs is not supported", .{});
                    return 1;
                }
                if (!HUID.isValid(pos_arg)) {
                    std.log.err("`{s}` is not a valid HUID. Valid HUID matches regexp `{s}`", .{ pos_arg, HUID.REGEX });
                    return 1;
                }
                huid = pos_arg;
            };

            if (huid == null) {
                std.log.err("No HUID was provided", .{});
                try cli.help(stdout);
                try stdout.flush();
                return 1;
            }

            const arena = init.arena.allocator();
            defer {
                // printArenaState(init.arena);
                _ = init.arena.reset(.free_all);
            }
            const tasks = try Task.loadTasks(init.io, arena, tasks_db.relative_path);
            if (tasks.len == 0) {
                std.log.err("No tasks found.", .{});
                return 0;
            }
            var found = false;
            for (tasks) |ta| {
                if (std.mem.eql(u8, ta.id, huid.?)) {
                    try stdout.print("{f}\n", .{ta.dump(tasks_db.relative_path, .default)});
                    try stdout.flush();
                    found = true;
                    break;
                }
            }
            if (!found) {
                std.log.err("No task with with HUID `{s}` was found", .{huid.?});
            }
        },
        .graph => std.log.info("TODO: {t} cmd is not implemented yet", .{cli.running_cmd.name}),
    }
    return 0;
}

fn findAllTags(args: []Arg, alloc: std.mem.Allocator) !Task.Tags {
    var tags_list: Task.Tags = .empty;
    for (args) |arg| {
        if (arg.long != null and !std.mem.eql(u8, arg.long.?, "tags")) continue;
        if (arg.value != .str) continue;
        if (arg.value.str) |t| {
            try tags_list.append(alloc, t);
        }
    }
    return tags_list;
}

fn printArenaState(arena: *std.heap.ArenaAllocator) void {
    std.debug.print("Arena: {B}\n", .{arena.queryCapacity()});
    var free = arena.state.free_list;
    var i: usize = 1;
    while (free) |fl| : (i += 1) {
        std.debug.print("Free-- [{d:0>2}]: End Index: {d}\n", .{ i, fl.end_index });
        free = fl.next;
    }
    i = 1;
    var used = arena.state.used_list;
    while (used) |fl| : (i += 1) {
        std.debug.print("Used-- [{d:0>2}]: End Index: {d}\n", .{ i, fl.end_index });
        used = fl.next;
    }
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

test {
    _ = HUID;
    _ = Tokenizer;
    _ = Query;
}
