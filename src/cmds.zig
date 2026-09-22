const std = @import("std");
const zarg = @import("zarg");
const Arg = zarg.Cli.Arg;
const Allocator = std.mem.Allocator;

pub const Name = "Task Tracker";
pub const DESCRIPTION =
    "A task tracker written in Zig, inspired by tatr by @rexim: https://github.com/tsoding/tatr.";

pub const Cmds = enum {
    root,
    init,
    ls,
    new,
    id,
    summary,
    find,
    ref,
    graph,
    untag,
    // completion,
};

pub const CmdType = zarg.Cli.Cmd(Cmds);

pub const CMD_LIST = [_]CmdType{
    CmdType{
        .name = .root,
        .usage = "[COMMANDS] [OPTIONS]",
        .min_arg = 1,
        .print_help_for_min_pos_arg = true,
    },
    CmdType{
        .name = .init,
        .info = "Create tasks/ directory in the current working directory if it doesn't exist yet",
        .usage = "",
        .min_arg = 0,
    },
    CmdType{
        .name = .new,
        .info = "Create a new task",
        .usage = "[OPTIONS] [TITLE...]",
        .min_pos_arg = 0,
        .min_arg = 0,
        .options = &.{
            Arg{
                .long = "tags",
                .short = 't',
                .info = "tags to add to the new task",
                .value = .{ .str = null },
            },
            Arg{
                .long = "body",
                .short = 'b',
                .info = "Body of the new task",
                .value = .{ .str = null },
            },
            Arg{
                .long = "priority",
                .short = 'p',
                .info = "Priority of the new task Default: 100",
                .value = .{ .num = 100 },
            },
            Arg{
                .long = "suffix",
                .short = 's',
                .info = "Task ID optional suffix",
                .value = .{ .str = null },
            },
        },
    },
    CmdType{
        .name = .ls,
        .usage = "[OPTIONS] [QUERY...]",
        .info = "Lists open tasks, or tasks matching the given query.",
        .min_arg = 0,
        .options = &.{
            .{
                .long = "closed",
                .short = 'c',
                .info = "List the closed tasks",
                .value = .{ .bool = null },
            },
            .{
                .long = "all",
                .short = 'A',
                .info = "List all tasks, including closed ones",
                .value = .{ .bool = null },
            },
            .{
                .long = "ascending",
                .short = 'a',
                .info = "List tasks in ascending order",
                .value = .{ .bool = null },
            },
            .{
                .long = "id",
                .short = 'i',
                .info = "Sort tasks by ID",
                .value = .{ .bool = null },
            },
            .{
                .long = "debug",
                .short = 'd',
                .info = "Outputs opcodes of the query for debugging",
                .value = .{ .bool = null },
            },
            .{
                .long = "json",
                .short = 'j',
                .info = "Output the results in JSON format",
                .value = .{ .bool = null },
            },
        },
    },

    CmdType{
        .name = .id,
        .info = "Print the HUID of the task if your in side a task directory",
        .usage = "",
        .min_pos_arg = 0,
        .min_arg = 0,
    },

    CmdType{
        .name = .summary,
        .info = "Print the summary of the tasks",
        .usage = "[OPTIONS]",
        .min_pos_arg = 0,
        .min_arg = 0,
        .options = &.{
            Arg{
                .long = "closed",
                .short = 'c',
                .info = "List closed tasks",
                .value = .{ .bool = null },
            },
        },
    },

    CmdType{
        .name = .find,
        .info = "Find the task with a given HUID",
        .usage = "<HUID> [OPTIONS]",
        .min_pos_arg = 0,
        .min_arg = 0,
        .options = &.{
            Arg{
                .long = "path-only",
                .short = 'p',
                .info = "Print only the path to TASK.md",
                .value = .{ .bool = null },
            },
        },
    },
    CmdType{
        .name = .ref,
        .info = "Find referers of the task",
        .usage = "[HUID]",
        .min_pos_arg = 0,
        .min_arg = 0,
    },
    CmdType{
        .name = .graph,
        .info = "Generate graph of tasks cross-referring to each other. This command is largely useless right now.",
        .usage = "",
        .min_pos_arg = 0,
        .min_arg = 0,
    },
    CmdType{
        .name = .untag,
        .info = "Untag all the tasks filtered by a query",
        .usage = "untag [OPTIONS] [QUERY]",
        .min_pos_arg = 1,
        .min_arg = 0,
        .options = &.{
            Arg{
                .long = "closed",
                .short = 'c',
                .info = "List closed tasks",
                .value = .{ .bool = null },
            },
            Arg{
                .long = "tags",
                .short = 't',
                .info = "tags to remove to the task",
                .value = .{ .str = null },
            },
        },
    },
};
