const std = @import("std");
const scan = @import("scan.zig");

pub const Class = enum {
    string,
    int,
    boolean,
    null,
    ambiguous,
};

fn pack(text: []const u8) u64 {
    var v: u64 = 0;
    for (text, 0..) |c, i| v |= @as(u64, c | 0x20) << @intCast(i * 8);
    return v;
}

const w_y = pack("y");
const w_n = pack("n");
const w_no = pack("no");
const w_on = pack("on");
const w_yes = pack("yes");
const w_off = pack("off");
const w_true = pack("true");
const w_null = pack("null");
const w_false = pack("false");

inline fn word(text: []const u8) Class {
    if (text.len > 5) return .string;

    switch (text[0] | 0x20) {
        'y', 'n', 'o', 't', 'f' => {},
        else => return .string,
    }

    const v = pack(text);
    const reserved = switch (text.len) {
        1 => v == w_y or v == w_n,
        2 => v == w_no or v == w_on,
        3 => v == w_yes or v == w_off,
        4 => v == w_true or v == w_null,
        5 => v == w_false,
        else => unreachable,
    };
    if (!reserved) return .string;

    if (std.mem.eql(u8, text, "null")) return .null;
    if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) return .boolean;
    return .ambiguous;
}

pub fn decimalInt(text: []const u8) bool {
    const digits = if (text[0] == '-') text[1..] else text;
    if (digits.len == 0 or digits.len > 19) return false;
    if (digits[0] == '0' and digits.len > 1) return false;
    for (digits) |c| if (c < '0' or c > '9') return false;
    if (digits.len == 19) _ = std.fmt.parseInt(i64, text, 10) catch return false;
    return true;
}

fn timestampLike(text: []const u8) bool {
    if (text.len < 8) return false;
    for (text[0..4]) |c| if (c < '0' or c > '9') return false;
    return text[4] == '-' and text[5] >= '0' and text[5] <= '9';
}

const number_table = blk: {
    var table: [256]bool = @splat(false);
    for ("0123456789abcdefABCDEFxXoO_.+-") |c| table[c] = true;
    break :blk table;
};

fn numberLike(text: []const u8) bool {
    if (timestampLike(text)) return true;
    for (text) |c| if (!number_table[c]) return false;
    if (std.fmt.parseInt(i128, text, 0)) |_| return true else |_| {}
    if (std.fmt.parseFloat(f64, text)) |_| return true else |_| {}
    return false;
}

pub inline fn classify(text: []const u8) Class {
    return switch (text[0]) {
        'a'...'z', 'A'...'Z' => word(text),
        '0'...'9' => if (decimalInt(text)) .int else if (numberLike(text)) .ambiguous else .string,
        '-' => if (decimalInt(text)) .int else .ambiguous,
        '_', '/' => .string,
        else => .ambiguous,
    };
}

pub fn plainString(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!scan.plainChar(c)) return false;
    return classify(text) == .string;
}

const testing = std.testing;

test "classify resolves only the unambiguous forms" {
    const cases = [_]struct { text: []const u8, class: Class }{
        .{ .text = "claude", .class = .string },
        .{ .text = "test.failed", .class = .string },
        .{ .text = "lua/harness/Session.lua", .class = .string },
        .{ .text = "20261030T091500Z-a41f09", .class = .string },
        .{ .text = "x@y.com", .class = .string },
        .{ .text = "_private", .class = .string },
        .{ .text = "/abs/path", .class = .string },
        .{ .text = "nan", .class = .string },
        .{ .text = "toolong", .class = .string },
        .{ .text = "topic", .class = .string },
        .{ .text = "nulls", .class = .string },
        .{ .text = "1dd70fc", .class = .string },
        .{ .text = "2026-10-30t09", .class = .ambiguous },
        .{ .text = "1e", .class = .string },
        .{ .text = "0", .class = .int },
        .{ .text = "42", .class = .int },
        .{ .text = "-7", .class = .int },
        .{ .text = "9223372036854775807", .class = .int },
        .{ .text = "true", .class = .boolean },
        .{ .text = "false", .class = .boolean },
        .{ .text = "null", .class = .null },
        .{ .text = "True", .class = .ambiguous },
        .{ .text = "NULL", .class = .ambiguous },
        .{ .text = "yes", .class = .ambiguous },
        .{ .text = "No", .class = .ambiguous },
        .{ .text = "on", .class = .ambiguous },
        .{ .text = "y", .class = .ambiguous },
        .{ .text = "007", .class = .ambiguous },
        .{ .text = "1.5", .class = .ambiguous },
        .{ .text = "1e5", .class = .ambiguous },
        .{ .text = "0x1F", .class = .ambiguous },
        .{ .text = "0o17", .class = .ambiguous },
        .{ .text = "1_000", .class = .ambiguous },
        .{ .text = "9223372036854775808", .class = .ambiguous },
        .{ .text = "2026-10-30", .class = .ambiguous },
        .{ .text = "-", .class = .ambiguous },
        .{ .text = "-x", .class = .ambiguous },
        .{ .text = "+1", .class = .ambiguous },
        .{ .text = ".inf", .class = .ambiguous },
        .{ .text = "@ref", .class = .ambiguous },
    };

    for (cases) |case| {
        testing.expectEqual(case.class, classify(case.text)) catch |err| {
            std.debug.print("classify({s})\n", .{case.text});
            return err;
        };
    }
}
