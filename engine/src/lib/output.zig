const std = @import("std");
const runtime = @import("runtime.zig");

const Color = enum {
    green,
    blue,
    yellow,
    red,
    reset,
};

pub const Mode = enum { text, json };

pub const Level = enum { success, info, warn, err, plain };

pub const ExitCode = struct {
    pub const success: u8 = 0;
    pub const failure: u8 = 1;
    pub const usage: u8 = 2;
    pub const partial: u8 = 3;
};

pub const NoFields = struct {};

var current_mode: Mode = .text;
var current_command: []const u8 = "";

pub fn configure(mode: Mode, command: []const u8) void {
    current_mode = mode;
    current_command = command;
}

fn colorFor(level: Level) ?Color {
    return switch (level) {
        .success => .green,
        .info => .blue,
        .warn => .yellow,
        .err => .red,
        .plain => null,
    };
}

fn streamFor(level: Level) std.Io.File {
    return switch (level) {
        .success, .info, .plain => std.Io.File.stdout(),
        .warn, .err => std.Io.File.stderr(),
    };
}

fn levelString(level: Level) []const u8 {
    return switch (level) {
        .success => "success",
        .info => "info",
        .warn => "warn",
        .err => "error",
        .plain => "plain",
    };
}

fn colorCode(color: Color) []const u8 {
    return switch (color) {
        .green => "\x1b[32m",
        .blue => "\x1b[34m",
        .yellow => "\x1b[33m",
        .red => "\x1b[31m",
        .reset => "\x1b[0m",
    };
}

fn isTty() bool {
    return std.Io.File.stdout().isTty(runtime.io()) catch false;
}

fn printPrefix(writer: anytype, color: Color) void {
    if (isTty()) {
        writer.print("{s}[tin]{s} ", .{ colorCode(color), colorCode(.reset) }) catch return;
    } else {
        writer.print("[tin] ", .{}) catch return;
    }
}

fn writeJsonString(writer: anytype, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x08 => try writer.writeAll("\\b"),
            0x0c => try writer.writeAll("\\f"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn writeFields(writer: anytype, fields: anytype) !void {
    inline for (comptime std.meta.fieldNames(@TypeOf(fields))) |name| {
        const value = @field(fields, name);
        try writer.writeAll(",\"");
        try writer.writeAll(name);
        try writer.writeAll("\":");
        try writeJsonString(writer, value);
    }
}

fn emitText(level: Level, comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    var file_writer = streamFor(level).writerStreaming(runtime.io(), &buf);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    if (colorFor(level)) |c| printPrefix(writer, c);
    writer.print(fmt ++ "\n", args) catch return;
}

fn emitJson(level: Level, fields: anytype, comptime fmt: []const u8, args: anytype) void {
    var message: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer message.deinit();
    message.writer.print(fmt, args) catch {};

    var buf: [1024]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(runtime.io(), &buf);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};

    writer.writeAll("{\"command\":") catch return;
    writeJsonString(writer, current_command) catch return;
    writer.writeAll(",\"level\":") catch return;
    writeJsonString(writer, levelString(level)) catch return;
    writeFields(writer, fields) catch return;
    writer.writeAll(",\"message\":") catch return;
    writeJsonString(writer, message.written()) catch return;
    writer.writeAll("}\n") catch return;
}

fn line(level: Level, comptime fmt: []const u8, args: anytype) void {
    if (current_mode == .json) {
        emitJson(level, NoFields{}, fmt, args);
        return;
    }
    emitText(level, fmt, args);
}

pub fn record(level: Level, fields: anytype, comptime fmt: []const u8, args: anytype) void {
    if (current_mode == .json) {
        emitJson(level, fields, fmt, args);
        return;
    }
    emitText(level, fmt, args);
}

pub fn success(comptime fmt: []const u8, args: anytype) void {
    line(.success, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    line(.info, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    line(.warn, fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    line(.err, fmt, args);
}

pub fn plain(comptime fmt: []const u8, args: anytype) void {
    line(.plain, fmt, args);
}

test "isTty returns a boolean" {
    _ = isTty();
}

test "writeJsonString escapes quotes, backslashes, and control bytes" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try writeJsonString(&out.writer, "a\"b\\c\nd\te\x01");
    try std.testing.expectEqualStrings("\"a\\\"b\\\\c\\nd\\te\\u0001\"", out.written());
}

test "writeFields renders comma-prefixed key/value pairs" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try writeFields(&out.writer, .{ .action = "link", .status = "created" });
    try std.testing.expectEqualStrings(",\"action\":\"link\",\"status\":\"created\"", out.written());
}
