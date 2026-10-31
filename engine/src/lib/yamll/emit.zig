const std = @import("std");
const scalar = @import("scalar.zig");

const Allocator = std.mem.Allocator;

pub const Error = error{
    OutOfMemory,
    InvalidUtf8,
    TooDeep,
    Unbalanced,
};

const max_depth = 64;

const Frame = struct {
    is_map: bool,
    count: usize = 0,
    expect_value: bool = false,
};

pub const Emitter = struct {
    allocator: Allocator,
    out: *std.ArrayListUnmanaged(u8),
    stack: [max_depth]Frame = undefined,
    depth: usize = 0,

    pub fn init(allocator: Allocator, out: *std.ArrayListUnmanaged(u8)) Emitter {
        return .{ .allocator = allocator, .out = out };
    }

    pub fn beginMap(self: *Emitter) Error!void {
        try self.open('{', true);
    }

    pub fn endMap(self: *Emitter) Error!void {
        try self.close('}', true);
    }

    pub fn beginSeq(self: *Emitter) Error!void {
        try self.open('[', false);
    }

    pub fn endSeq(self: *Emitter) Error!void {
        try self.close(']', false);
    }

    pub fn key(self: *Emitter, name: []const u8) Error!void {
        const frame = &self.stack[self.depth - 1];
        if (!frame.is_map or frame.expect_value) return Error.Unbalanced;
        if (frame.count > 0) try self.out.appendSlice(self.allocator, ", ");
        try writeScalar(self.allocator, self.out, name);
        try self.out.appendSlice(self.allocator, ": ");
        frame.expect_value = true;
    }

    pub fn string(self: *Emitter, value: []const u8) Error!void {
        try self.before();
        try writeScalar(self.allocator, self.out, value);
    }

    pub fn int(self: *Emitter, value: i64) Error!void {
        try self.before();
        var buf: [24]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
        try self.out.appendSlice(self.allocator, text);
    }

    pub fn boolean(self: *Emitter, value: bool) Error!void {
        try self.before();
        try self.out.appendSlice(self.allocator, if (value) "true" else "false");
    }

    pub fn nil(self: *Emitter) Error!void {
        try self.before();
        try self.out.appendSlice(self.allocator, "null");
    }

    pub fn finish(self: *Emitter) Error!void {
        if (self.depth != 0) return Error.Unbalanced;
    }

    fn before(self: *Emitter) Error!void {
        if (self.depth == 0) return;
        const frame = &self.stack[self.depth - 1];
        if (frame.is_map) {
            if (!frame.expect_value) return Error.Unbalanced;
            frame.expect_value = false;
        } else if (frame.count > 0) {
            try self.out.appendSlice(self.allocator, ", ");
        }
        frame.count += 1;
    }

    fn open(self: *Emitter, ch: u8, is_map: bool) Error!void {
        try self.before();
        if (self.depth == max_depth) return Error.TooDeep;
        try self.out.append(self.allocator, ch);
        self.stack[self.depth] = .{ .is_map = is_map };
        self.depth += 1;
    }

    fn close(self: *Emitter, ch: u8, is_map: bool) Error!void {
        if (self.depth == 0) return Error.Unbalanced;
        const frame = self.stack[self.depth - 1];
        if (frame.is_map != is_map or frame.expect_value) return Error.Unbalanced;
        self.depth -= 1;
        try self.out.append(self.allocator, ch);
    }
};

pub fn writeScalar(allocator: Allocator, out: *std.ArrayListUnmanaged(u8), text: []const u8) Error!void {
    if (scalar.plainString(text)) return out.appendSlice(allocator, text);

    if (!std.unicode.utf8ValidateSlice(text)) return Error.InvalidUtf8;

    try out.append(allocator, '"');

    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];

        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f, 0x7f => {
                var buf: [4]u8 = undefined;
                try out.appendSlice(allocator, std.fmt.bufPrint(&buf, "\\x{x:0>2}", .{c}) catch unreachable);
            },
            0x80...0xff => {
                const len = std.unicode.utf8ByteSequenceLength(c) catch unreachable;
                const cp = std.unicode.utf8Decode(text[i .. i + len]) catch unreachable;

                if (cp == 0x85 or cp == 0x2028 or cp == 0x2029) {
                    var buf: [6]u8 = undefined;
                    try out.appendSlice(allocator, std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{cp}) catch unreachable);
                } else {
                    try out.appendSlice(allocator, text[i .. i + len]);
                }

                i += len;
                continue;
            },
            else => try out.append(allocator, c),
        }

        i += 1;
    }

    try out.append(allocator, '"');
}

fn expectEmits(expected: []const u8, comptime build: fn (*Emitter) Error!void) !void {
    const allocator = std.testing.allocator;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    var emitter = Emitter.init(allocator, &out);
    try build(&emitter);
    try emitter.finish();

    try std.testing.expectEqualStrings(expected, out.items);
}

test "emits flow mapping with plain and quoted scalars" {
    try expectEmits("{id: 20261030T091500Z-a41f09, topic: test.failed, hops: 0, ok: true, gone: null, summary: \"vusted failed: 3\"}", struct {
        fn build(e: *Emitter) Error!void {
            try e.beginMap();
            try e.key("id");
            try e.string("20261030T091500Z-a41f09");
            try e.key("topic");
            try e.string("test.failed");
            try e.key("hops");
            try e.int(0);
            try e.key("ok");
            try e.boolean(true);
            try e.key("gone");
            try e.nil();
            try e.key("summary");
            try e.string("vusted failed: 3");
            try e.endMap();
        }
    }.build);
}

test "emits nested maps and sequences" {
    try expectEmits("{payload: {files: [a/b.lua, \"c d\"], empty: {}}, tags: []}", struct {
        fn build(e: *Emitter) Error!void {
            try e.beginMap();
            try e.key("payload");
            try e.beginMap();
            try e.key("files");
            try e.beginSeq();
            try e.string("a/b.lua");
            try e.string("c d");
            try e.endSeq();
            try e.key("empty");
            try e.beginMap();
            try e.endMap();
            try e.endMap();
            try e.key("tags");
            try e.beginSeq();
            try e.endSeq();
            try e.endMap();
        }
    }.build);
}

test "quotes strings a resolver could read as another type" {
    const risky = [_][]const u8{ "true", "No", "off", "null", "~", "123", "1.5", "1e5", "0x1F", "-1", ".inf", "2026-10-30", "007", "", "a: b", "a #b", "- a", "{x}", "[x]", "a,b", "'q'", "@at", "!tag", "&anchor", "*alias", "%x", "|", ">", "?" };

    for (risky) |text| {
        try std.testing.expect(!scalar.plainString(text));
    }

    const safe = [_][]const u8{ "claude", "test.failed", "lua/harness/Session.lua", "20261030T091500Z-a41f09", "a-b_c", "x@y.com" };

    for (safe) |text| {
        try std.testing.expect(scalar.plainString(text));
    }
}

test "escapes control characters, line breaks and quotes" {
    const allocator = std.testing.allocator;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try writeScalar(allocator, &out, "a\"b\\c\nd\te\x01f\u{85}g\u{2028}h é");

    try std.testing.expectEqualStrings("\"a\\\"b\\\\c\\nd\\te\\x01f\\u0085g\\u2028h é\"", out.items);
}

test "rejects invalid utf8 and unbalanced structure" {
    const allocator = std.testing.allocator;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try std.testing.expectError(Error.InvalidUtf8, writeScalar(allocator, &out, "\xff\xfe"));

    var emitter = Emitter.init(allocator, &out);
    try emitter.beginMap();
    try std.testing.expectError(Error.Unbalanced, emitter.string("no key"));
    try std.testing.expectError(Error.Unbalanced, emitter.endSeq());
    try std.testing.expectError(Error.Unbalanced, emitter.finish());
}

test "emitted line parses back to the same strings" {
    const allocator = std.testing.allocator;
    const yaml = @import("yaml");

    const values = [_][]const u8{ "claude", "true", "123", "a: b", "line1\nline2", "tab\there", "q\"uote", "back\\slash", "{x}", "é ü", "\u{2028}", "", "#c", "- x" };

    for (values) |text| {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        defer out.deinit(allocator);

        var emitter = Emitter.init(allocator, &out);
        try emitter.beginMap();
        try emitter.key("k");
        try emitter.string(text);
        try emitter.key(text);
        try emitter.int(7);
        try emitter.endMap();
        try emitter.finish();

        try std.testing.expect(std.mem.indexOfScalar(u8, out.items, '\n') == null);

        var doc = try yaml.parse(allocator, out.items);
        defer doc.deinit();

        try std.testing.expectEqualStrings(text, doc.getMapping("k").?.getString().?);
        try std.testing.expectEqualStrings("7", doc.getMapping(text).?.getString().?);
    }
}
