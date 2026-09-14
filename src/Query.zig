const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const Tokenizer = @import("Tokenizer.zig");
const Task = @import("Task.zig");
const paths = @import("paths.zig");
const HUID = @import("huid.zig");
const messages = @import("messages.zig");

pub const Stack = std.ArrayList(StackItem);
pub const StackType = enum { boolean, integer };

pub const StackItem = struct {
    as: union(StackType) {
        boolean: bool,
        integer: u64,
    },
    loc: usize,

    pub fn ofBool(v: bool, loc: usize) StackItem {
        return .{ .as = .{ .boolean = v }, .loc = loc };
    }

    pub fn ofInt(v: u64, loc: usize) StackItem {
        return .{ .as = .{ .integer = v }, .loc = loc };
    }
};

pub const QueryOps = std.ArrayList(Op);
pub const OpCode = union(enum) {
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
    op_id: []const u8,
    op_integer: u64,

    inline fn fromTag(tag: []const u8) OpCode {
        return .{ .op_tag = tag };
    }

    inline fn fromId(id: []const u8) OpCode {
        return .{ .op_id = id };
    }
    inline fn fromInt(integer: u64) OpCode {
        return .{ .op_integer = integer };
    }
};

pub const Op = struct {
    code: OpCode,
    loc: usize,
};

pub fn printOp(op: Op, w: *std.Io.Writer) !void {
    switch (op.code) {
        .op_any => try w.writeAll("OP_ANY\n"),
        .op_not => try w.writeAll("OP_NOT\n"),
        .op_or => try w.writeAll("OP_OR\n"),
        .op_and => try w.writeAll("OP_AND\n"),
        .op_tagged => try w.writeAll("OP_TAGGED\n"),
        .op_priority => try w.writeAll("OP_PRIORITY\n"),
        .op_lt => try w.writeAll("OP_LT\n"),
        .op_gt => try w.writeAll("OP_GT\n"),
        .op_lte => try w.writeAll("OP_LTE\n"),
        .op_gte => try w.writeAll("OP_GTE\n"),
        .op_eq => try w.writeAll("OP_EQ\n"),
        .op_neq => try w.writeAll("OP_NEQ\n"),
        .op_tag => |t| try w.print("OP_TAG {s}\n", .{t}),
        .op_id => |id| try w.print("OP_ID {s}\n", .{id}),
        .op_integer => |nu| try w.print("OP_INTEGER {d}\n", .{nu}),
    }
}

pub const ParseError = error{
    EmptyTag,
    IntegerOverflow,
    UnexpectedToken,
    UnexpectedInfix,
    UnexpectedPrimary,
} || Allocator.Error;

pub const MatchError = error{
    InvalidStack,
} || Allocator.Error;

pub const Query = @This();
const ErrorLevel = enum { warn, err };
query: QueryOps,
source: []const u8,
alloc: Allocator,
tokenizer: Tokenizer,
err_msg: std.ArrayList(u8),

pub fn init(alloc: Allocator, source: []const u8) Query {
    return .{
        .query = .empty,
        .alloc = alloc,
        .source = source,
        .err_msg = .empty,
        .tokenizer = .init(source),
    };
}

pub fn addOp(self: *Query, opCode: Op) !void {
    try self.query.append(self.alloc, opCode);
}

pub fn addOpCode(self: *Query, code: OpCode) !void {
    try self.addOp(.{ .code = code, .loc = self.tokenizer.token_pos });
}

pub fn deinit(self: *Query, alloc: std.mem.Allocator) void {
    self.query.deinit(alloc);
    self.err_msg.deinit(alloc);
}

pub fn parse(self: *Query) ParseError!void {
    try self.parseExpr();
    const end = self.tokenizer.next();
    if (end.len != 0) {
        std.debug.print(messages.INFIX_OPERATORS, .{});
        try self.errorReport(.err, self.tokenizer.token_pos, "Unexpected infix operator `{s}`", .{end});
        return ParseError.UnexpectedInfix;
    }
}

pub fn matchTask(self: *Query, alloc: Allocator, task: *const Task) MatchError!bool {
    var stack: Stack = .empty;
    defer stack.deinit(alloc);

    for (self.query.items) |op| {
        switch (op.code) {
            .op_tag => |tag| {
                try stack.append(
                    alloc,
                    .ofBool(task.hasTag(tag), op.loc),
                );
            },
            .op_integer => |v| {
                try stack.append(alloc, .ofInt(v, op.loc));
            },
            .op_priority => {
                try stack.append(alloc, .ofInt(task.priority, op.loc));
            },
            .op_id => |id| {
                try stack.append(alloc, .ofBool(strEq(task.id, id), op.loc));
            },
            .op_not => {
                std.debug.assert(stack.items.len >= 1);
                const a = try self.popStack(&stack, .boolean);
                try stack.append(
                    alloc,
                    .ofBool(!a, op.loc),
                );
            },
            .op_any => try stack.append(alloc, .ofBool(true, op.loc)),
            .op_or => {
                std.debug.assert(stack.items.len >= 2);
                const a = try self.popStack(&stack, .boolean);
                const b = try self.popStack(&stack, .boolean);
                try stack.append(alloc, .ofBool(a or b, op.loc));
            },
            .op_and => {
                std.debug.assert(stack.items.len >= 2);
                const a = try self.popStack(&stack, .boolean);
                const b = try self.popStack(&stack, .boolean);
                try stack.append(alloc, .ofBool(a and b, op.loc));
            },
            .op_tagged => {
                try stack.append(
                    alloc,
                    .ofBool(task.tags.items.len > 0, op.loc),
                );
            },
            .op_lt => {
                std.debug.assert(stack.items.len >= 2);
                const a = try self.popStack(&stack, .integer);
                const b = try self.popStack(&stack, .integer);
                try stack.append(alloc, .ofBool(a < b, op.loc));
            },
            .op_gt => {
                std.debug.assert(stack.items.len >= 2);
                const a = try self.popStack(&stack, .integer);
                const b = try self.popStack(&stack, .integer);
                try stack.append(alloc, .ofBool(a > b, op.loc));
            },
            .op_lte => {
                std.debug.assert(stack.items.len >= 2);
                const a = try self.popStack(&stack, .integer);
                const b = try self.popStack(&stack, .integer);
                try stack.append(alloc, .ofBool(a <= b, op.loc));
            },
            .op_gte => {
                std.debug.assert(stack.items.len >= 2);
                const a = try self.popStack(&stack, .integer);
                const b = try self.popStack(&stack, .integer);
                try stack.append(alloc, .ofBool(a >= b, op.loc));
            },
            .op_eq => {
                std.debug.assert(stack.items.len >= 2);
                const a = try self.popStack(&stack, .integer);
                const b = try self.popStack(&stack, .integer);
                try stack.append(alloc, .ofBool(a == b, op.loc));
            },
            .op_neq => {
                std.debug.assert(stack.items.len >= 2);
                const a = try self.popStack(&stack, .integer);
                const b = try self.popStack(&stack, .integer);
                try stack.append(alloc, .ofBool(a != b, op.loc));
            },
        }
    }

    std.debug.assert(stack.items.len == 1);
    const last_item = try self.popStack(&stack, .boolean);
    return last_item;
}

pub fn format(
    self: *Query,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    const save_cursor = self.tokenizer.cursor;
    self.tokenizer.cursor = 0;
    try writer.writeAll("TOKENS:\n");
    while (self.tokenizer.itNext()) |tok| {
        try writer.print("    {s}\n", .{tok});
    }
    try writer.writeByte('\n');
    try writer.writeAll("OPS:\n");
    for (self.query.items) |qu| {
        try writer.writeAll("    ");
        try printOp(qu, writer);
    }
    self.tokenizer.cursor = save_cursor;
}

fn parsePrimary(self: *Query) ParseError!void {
    var token = self.tokenizer.next();
    var offset = self.tokenizer.token_pos;

    if (mem.startsWith(u8, token, ":")) {
        if (token.len == 1) {
            try self.errorReport(.err, offset, "empty tag\n", .{});
            return ParseError.EmptyTag;
        }
        try self.addOpCode(.fromTag(token[1..]));
        return;
    }

    if (strEq(token, "[")) {
        const open = token[0];
        try self.parseExpr();
        token = self.tokenizer.next();
        offset = self.tokenizer.token_pos;
        if (open == '[' and !strEq(token, "]")) {
            try self.errorReport(.err, offset, "expected ']'.", .{});
            return ParseError.UnexpectedToken;
        }
        return;
    }

    if (strEq(token, "not")) {
        try self.parsePrimary();
        try self.addOpCode(.op_not);
        return;
    }
    if (strEq(token, "any")) {
        try self.addOpCode(.op_any);
        return;
    }
    if (strEq(token, "tagged")) {
        try self.addOpCode(.op_tagged);
        return;
    }
    if (strEq(token, "priority")) {
        try self.addOpCode(.op_priority);
        return;
    }
    if (HUID.isValid(token)) {
        try self.addOpCode(.fromId(token));
        return;
    }

    const task_priority_type = @FieldType(Task, "priority");
    const integer = std.fmt.parseInt(task_priority_type, token, 10);
    if (integer) |v| {
        try self.addOpCode(.fromInt(v));
        return;
    } else |err| {
        if (err == error.Overflow) {
            try self.errorReport(.err, offset, "Number is too big max {d}", .{std.math.maxInt(task_priority_type)});
            return ParseError.IntegerOverflow;
        }
        // If we get here that means we have an invalid the primary expression.
        std.debug.print(messages.PRIMARY_EXPR, .{});
        if (token.len == 0) {
            try self.errorReport(.err, offset, "Primary expression is expected here.", .{});
        } else {
            try self.errorReport(.err, offset, "Unexpected start of a primary expression `{s}`.", .{token});
        }
        return ParseError.UnexpectedPrimary;
    }
    // We should never get here
    unreachable;
}

fn parseCompare(self: *Query) ParseError!void {
    try self.parsePrimary();
    while (true) {
        const savePoint = self.tokenizer.cursor;
        const token = self.tokenizer.next();
        if (strEq(token, "lt")) {
            try self.parsePrimary();
            try self.addOpCode(.op_lt);
            continue;
        }
        if (strEq(token, "le")) {
            try self.parsePrimary();
            try self.addOpCode(.op_lte);
            continue;
        }
        if (strEq(token, "gt")) {
            try self.parsePrimary();
            try self.addOpCode(.op_gt);
            continue;
        }
        if (strEq(token, "ge")) {
            try self.parsePrimary();
            try self.addOpCode(.op_gte);
            continue;
        }
        if (strEq(token, "eq")) {
            try self.parsePrimary();
            try self.addOpCode(.op_eq);
            continue;
        }
        if (strEq(token, "ne")) {
            try self.parsePrimary();
            try self.addOpCode(.op_neq);
            continue;
        }
        self.tokenizer.cursor = savePoint;
        break;
    }
}

fn parseAnd(self: *Query) ParseError!void {
    try self.parseCompare();
    while (true) {
        if (!strEq(self.tokenizer.peek(), "and")) return;
        _ = self.tokenizer.next();
        try self.parseCompare();
        try self.addOpCode(.op_and);
    }
}

fn parseOr(self: *Query) ParseError!void {
    try self.parseAnd();
    while (true) {
        if (!strEq(self.tokenizer.peek(), "or")) return;
        _ = self.tokenizer.next();
        try self.parseAnd();
        try self.addOpCode(.op_or);
    }
}

fn parseExpr(self: *Query) ParseError!void {
    try self.parseOr();
}

// @section:Private --------------------------

fn errorReport(self: *Query, error_level: ErrorLevel, offset: usize, comptime fmt: []const u8, args: anytype) !void {
    const cursor = offset;
    try self.err_msg.appendSlice(self.alloc, self.source);
    try self.err_msg.append(self.alloc, '\n');
    try self.err_msg.appendNTimes(self.alloc, ' ', cursor);
    try self.err_msg.appendSlice(self.alloc, "^\n");
    switch (error_level) {
        .err => try self.err_msg.appendSlice(self.alloc, "ERROR: "),
        .warn => try self.err_msg.appendSlice(self.alloc, "WARNING: "),
    }
    try self.err_msg.print(self.alloc, fmt, args);
    try self.err_msg.append(self.alloc, '\n');
}

fn popStack(self: *Query, stack: *Stack, comptime expect: StackType) MatchError!switch (expect) {
    .boolean => bool,
    .integer => u64,
} {
    const item = stack.pop().?;
    if (item.as != expect) {
        try self.errorReport(
            .err,
            item.loc,
            "Expected {t}, found {t}",
            .{ expect, item.as },
        );
        return error.InvalidStack;
    }

    return switch (expect) {
        .boolean => item.as.boolean,
        .integer => item.as.integer,
    };
}

inline fn strEq(a: []const u8, b: []const u8) bool {
    return mem.eql(u8, a, b);
}

test "ls_query_negation_of_complex_expression_in_parens" {
    const alloc = std.testing.allocator;
    var query = Query.init(alloc, "not [tagged or :bug and :test and :foo and :bar]");
    defer query.deinit(alloc);
    try query.parse();
    const output = try std.fmt.allocPrint(alloc, "{f}", .{&query});
    defer alloc.free(output);

    try std.testing.expectEqualStrings(
        \\TOKENS:
        \\    not
        \\    [
        \\    tagged
        \\    or
        \\    :bug
        \\    and
        \\    :test
        \\    and
        \\    :foo
        \\    and
        \\    :bar
        \\    ]
        \\
        \\OPS:
        \\    OP_TAGGED
        \\    OP_TAG bug
        \\    OP_TAG test
        \\    OP_AND
        \\    OP_TAG foo
        \\    OP_AND
        \\    OP_TAG bar
        \\    OP_AND
        \\    OP_OR
        \\    OP_NOT
        \\
    , output);
}

test "ls_query_not_stuck_to_open_paren" {
    const alloc = std.testing.allocator;
    var query = Query.init(alloc, "not[:bug and :test] and :query");
    defer query.deinit(alloc);
    try query.parse();
    const output = try std.fmt.allocPrint(alloc, "{f}", .{&query});
    defer alloc.free(output);

    try std.testing.expectEqualStrings(
        \\TOKENS:
        \\    not
        \\    [
        \\    :bug
        \\    and
        \\    :test
        \\    ]
        \\    and
        \\    :query
        \\
        \\OPS:
        \\    OP_TAG bug
        \\    OP_TAG test
        \\    OP_AND
        \\    OP_NOT
        \\    OP_TAG query
        \\    OP_AND
        \\
    , output);
}

test "ls_query_priority_above_20" {
    const alloc = std.testing.allocator;
    var query = Query.init(alloc, "priority gt 20");
    defer query.deinit(alloc);
    try query.parse();
    const output = try std.fmt.allocPrint(alloc, "{f}", .{&query});
    defer alloc.free(output);

    try std.testing.expectEqualStrings(
        \\TOKENS:
        \\    priority
        \\    gt
        \\    20
        \\
        \\OPS:
        \\    OP_PRIORITY
        \\    OP_INTEGER 20
        \\    OP_GT
        \\
    , output);
}

// test "ls_query_report_error_utf8" {
//
//     const alloc = std.testing.allocator;
//     var query = Query.init(alloc, ":привет hello");
//     defer query.deinit(alloc);
//     const err = query.parse();
//     try std.testing.expectError(ParseError.UnexpectedInfix, err);
//     const output = try std.fmt.allocPrint(alloc, "{s}", .{query.err_msg.items});
//     defer alloc.free(output);
//
//     try std.testing.expectEqualStrings(
//         \\:привет hello
//         \\        ^
//         \\ERROR: Unexpected infix operator `hello`
//         \\
//     , output);
// }
