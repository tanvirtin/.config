const std = @import("std");
const scan = @import("scan.zig");
const scalar = @import("scalar.zig");

const Allocator = std.mem.Allocator;
const lanes = scan.lanes;
const Vec = scan.Vec;

pub const Error = error{
    Invalid,
    OutOfMemory,
};

pub const Kind = enum(u3) {
    map,
    seq,
    string,
    int,
    boolean,
    null,
};

pub const Entry = struct {
    ptr: [*]const u8,
    meta: u32,
    next: u32,

    pub const max_len: u32 = (1 << 29) - 1;

    inline fn make(tag: Kind, size: usize, ptr: [*]const u8, next: u32) Entry {
        return .{ .ptr = ptr, .meta = (@as(u32, @backingInt(tag)) << 29) | @as(u32, @intCast(size)), .next = next };
    }

    pub inline fn kind(self: Entry) Kind {
        return @fromBackingInt(@intCast(self.meta >> 29));
    }

    pub inline fn len(self: Entry) u32 {
        return self.meta & max_len;
    }
};

comptime {
    std.debug.assert(@sizeOf(Entry) == 16);
}

const max_depth = 64;

pub const Node = struct {
    tape: []const Entry,
    idx: u32,

    pub fn kind(self: Node) Kind {
        return self.tape[self.idx].kind();
    }

    pub fn text(self: Node) ?[]const u8 {
        const entry = self.tape[self.idx];
        return switch (entry.kind()) {
            .map, .seq => null,
            else => entry.ptr[0..entry.len()],
        };
    }

    pub fn string(self: Node) ?[]const u8 {
        return if (self.kind() == .string) self.text() else null;
    }

    pub fn int(self: Node) ?i64 {
        if (self.kind() != .int) return null;
        return std.fmt.parseInt(i64, self.text().?, 10) catch unreachable;
    }

    pub fn boolean(self: Node) ?bool {
        if (self.kind() != .boolean) return null;
        return self.text().?[0] == 't';
    }

    pub fn isNull(self: Node) bool {
        return self.kind() == .null;
    }

    pub fn len(self: Node) u32 {
        const entry = self.tape[self.idx];
        return switch (entry.kind()) {
            .map, .seq => entry.len(),
            else => 0,
        };
    }

    pub fn get(self: Node, key: []const u8) ?Node {
        const entry = self.tape[self.idx];
        if (entry.kind() != .map) return null;

        var child = self.idx + 1;
        while (child < entry.next) {
            const value = child + 1;
            const k = self.tape[child];
            if (k.len() == key.len and std.mem.eql(u8, k.ptr[0..key.len], key)) return .{ .tape = self.tape, .idx = value };
            child = self.tape[value].next;
        }
        return null;
    }

    pub fn children(self: Node) Children {
        const entry = self.tape[self.idx];
        const end = switch (entry.kind()) {
            .map, .seq => entry.next,
            else => self.idx + 1,
        };
        return .{ .tape = self.tape, .at = self.idx + 1, .end = end };
    }
};

pub const Children = struct {
    tape: []const Entry,
    at: u32,
    end: u32,

    pub fn next(self: *Children) ?Node {
        if (self.at >= self.end) return null;
        const node = Node{ .tape = self.tape, .idx = self.at };
        self.at = self.tape[self.at].next;
        return node;
    }
};

pub const Parser = struct {
    allocator: Allocator,
    tape: std.ArrayListUnmanaged(Entry) = .empty,
    strings: std.ArrayListUnmanaged(u8) = .empty,

    pub fn init(allocator: Allocator) Parser {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Parser) void {
        self.tape.deinit(self.allocator);
        self.strings.deinit(self.allocator);
    }

    const Open = struct { idx: u32, count: u32, close: u8 };

    pub fn parse(self: *Parser, line: []const u8) Error!Node {
        if (line.len > Entry.max_len) return Error.Invalid;

        var end = line.len;
        while (end > 0 and line[end - 1] == ' ') end -= 1;
        if (end == 0 or (line[end - 1] != '}' and line[end - 1] != ']')) return Error.Invalid;
        const src = line[0..end];

        self.tape.clearRetainingCapacity();
        self.strings.clearRetainingCapacity();
        try self.tape.ensureTotalCapacity(self.allocator, src.len / 2 + 2);
        try self.strings.ensureTotalCapacity(self.allocator, src.len + src.len / 2 + lanes + 8);

        const tape = self.tape.items.ptr;
        var n: u32 = 0;
        var stack: [max_depth]Open = undefined;
        var depth: usize = 0;
        var p: usize = scan.skipSpaces(src, 0);

        const State = enum { value, key, after };
        var state: State = .value;

        while (true) {
            switch (state) {
                .value, .key => {
                    if (p >= src.len) return Error.Invalid;
                    const c = src[p];

                    if (state == .value and (c == '{' or c == '[')) {
                        if (depth == max_depth) return Error.Invalid;
                        const close: u8 = if (c == '{') '}' else ']';
                        tape[n] = Entry.make(if (c == '{') .map else .seq, 0, src.ptr, 0);
                        stack[depth] = .{ .idx = n, .count = 0, .close = close };
                        depth += 1;
                        n += 1;
                        p = scan.skipSpaces(src, p + 1);
                        state = if (src[p] == close) .after else if (c == '{') .key else .value;
                        continue;
                    }

                    var text: []const u8 = undefined;
                    var kind: Kind = .string;

                    if (c == '"') {
                        p = try self.quoted(src, p, &text);
                    } else {
                        const stop = scan.plainEnd(src, p);
                        if (stop == p) return Error.Invalid;
                        const t = src[stop];
                        if (t == ':') {
                            if (!scan.flowEnd(src[stop + 1])) return Error.Invalid;
                        } else if (!scan.flowEnd(t)) return Error.Invalid;

                        text = src[p..stop];
                        kind = switch (scalar.classify(text)) {
                            .string => .string,
                            .int => .int,
                            .boolean => .boolean,
                            .null => .null,
                            .ambiguous => return Error.Invalid,
                        };
                        p = stop;
                    }

                    tape[n] = Entry.make(kind, text.len, text.ptr, n + 1);
                    n += 1;

                    if (state == .key) {
                        if (kind != .string) return Error.Invalid;
                        p = scan.skipSpaces(src, p);
                        if (src[p] != ':') return Error.Invalid;
                        p = scan.skipSpaces(src, p + 1);
                        state = .value;
                    } else {
                        state = .after;
                    }
                },
                .after => {
                    if (depth == 0) break;
                    if (p >= src.len) return Error.Invalid;
                    p = scan.skipSpaces(src, p);

                    const top = &stack[depth - 1];
                    const c = src[p];
                    p += 1;

                    if (c == top.close) {
                        if (n > top.idx + 1) top.count += 1;
                        tape[top.idx].meta |= top.count;
                        tape[top.idx].next = n;
                        depth -= 1;
                        continue;
                    }

                    if (c != ',') return Error.Invalid;
                    top.count += 1;
                    p = scan.skipSpaces(src, p);
                    if (src[p] == top.close) return Error.Invalid;
                    state = if (top.close == '}') .key else .value;
                },
            }
        }

        if (p != src.len) return Error.Invalid;

        self.tape.items.len = n;
        return .{ .tape = self.tape.items, .idx = 0 };
    }

    inline fn scanStop(src: []const u8, from: usize, acc: *Vec) ?usize {
        var pos = from;

        while (pos + lanes <= src.len) {
            const v: Vec = src[pos..][0..lanes].*;
            acc.* |= v;
            if (scan.firstSet(scan.stopBytes(v))) |at| return pos + at;
            pos += lanes;
        }

        while (pos < src.len) : (pos += 1) {
            const c = src[pos];
            if (c == '"' or c == '\\' or c < 0x20) return pos;
            acc.*[0] |= c;
        }

        return null;
    }

    inline fn scanCopy(src: []const u8, from: usize, dst: *[*]u8, acc: *Vec) ?usize {
        var pos = from;
        var out = dst.*;
        defer dst.* = out;

        while (pos + lanes <= src.len) {
            const v: Vec = src[pos..][0..lanes].*;
            out[0..lanes].* = v;
            acc.* |= v;
            if (scan.firstSet(scan.stopBytes(v))) |at| {
                out += at;
                return pos + at;
            }
            pos += lanes;
            out += lanes;
        }

        while (pos < src.len) : (pos += 1) {
            const c = src[pos];
            if (c == '"' or c == '\\' or c < 0x20) return pos;
            acc.*[0] |= c;
            out[0] = c;
            out += 1;
        }

        return null;
    }

    fn quoted(self: *Parser, src: []const u8, at: usize, out: *[]const u8) Error!usize {
        const start = at + 1;
        var acc = scan.splat(0);
        var pos = scanStop(src, start, &acc) orelse return Error.Invalid;

        while (src[pos] == '\t') pos = scanStop(src, pos + 1, &acc) orelse return Error.Invalid;

        if (src[pos] == '"') {
            if (scan.anyHigh(acc) and !scan.validUtf8(src[start..pos])) return Error.Invalid;
            out.* = src[start..pos];
            return pos + 1;
        }

        const base = self.strings.items.ptr + self.strings.items.len;
        var dst = base;
        @memcpy(dst[0 .. pos - start], src[start..pos]);
        dst += pos - start;

        while (true) {
            switch (src[pos]) {
                '"' => {
                    if (scan.anyHigh(acc) and !scan.validUtf8(src[start..pos])) return Error.Invalid;
                    const size = dst - base;
                    self.strings.items.len += size;
                    out.* = base[0..size];
                    return pos + 1;
                },
                '\\' => {
                    if (pos + 1 >= src.len) return Error.Invalid;
                    const replacement = scan.simple_escapes[src[pos + 1]];
                    if (replacement != scan.no_escape) {
                        dst[0] = @intCast(replacement);
                        dst += 1;
                        pos += 2;
                    } else {
                        pos = try unicodeEscape(src, pos + 1, &dst);
                    }
                },
                '\t' => {
                    dst[0] = '\t';
                    dst += 1;
                    pos += 1;
                },
                else => return Error.Invalid,
            }
            pos = scanCopy(src, pos, &dst, &acc) orelse return Error.Invalid;
        }
    }

    fn unicodeEscape(src: []const u8, at: usize, dst: *[*]u8) Error!usize {
        const cp: u21, const next: usize = switch (src[at]) {
            'N' => .{ 0x85, at + 1 },
            '_' => .{ 0xa0, at + 1 },
            'L' => .{ 0x2028, at + 1 },
            'P' => .{ 0x2029, at + 1 },
            'x' => .{ try hex(src, at + 1, 2), at + 3 },
            'u' => .{ try hex(src, at + 1, 4), at + 5 },
            'U' => .{ try hex(src, at + 1, 8), at + 9 },
            else => return Error.Invalid,
        };

        var buf: [4]u8 = undefined;
        const size = std.unicode.utf8Encode(cp, &buf) catch return Error.Invalid;
        @memcpy(dst.*[0..size], buf[0..size]);
        dst.* += size;
        return next;
    }

    fn hex(src: []const u8, at: usize, digits: usize) Error!u21 {
        if (at + digits > src.len) return Error.Invalid;
        const v = std.fmt.parseInt(u32, src[at .. at + digits], 16) catch return Error.Invalid;
        if (v > 0x10ffff) return Error.Invalid;
        return @intCast(v);
    }
};

const testing = std.testing;
const yaml = @import("yaml");
const emit = @import("emit.zig");

fn sameAsYaml(full: yaml.Value, fast: Node) !void {
    const node = full.tree.nodes.items[full.idx];

    switch (fast.kind()) {
        .string, .int, .boolean, .null => {
            try testing.expectEqual(.scalar, node.tag);
            try testing.expectEqualStrings(full.getString().?, fast.text().?);
        },
        .seq => {
            try testing.expectEqual(.sequence, node.tag);
            var child = node.first_child;
            var it = fast.children();
            var items: u32 = 0;
            while (it.next()) |item| {
                items += 1;
                try testing.expect(child != 0);
                try sameAsYaml(.{ .tree = full.tree, .idx = child, .arena = full.arena }, item);
                child = full.tree.nodes.items[child].next_sibling;
            }
            try testing.expectEqual(@as(u32, 0), child);
            try testing.expectEqual(items, fast.len());
        },
        .map => {
            try testing.expectEqual(.mapping, node.tag);
            var child = node.first_child;
            var it = fast.children();
            var pairs: u32 = 0;
            while (it.next()) |key| {
                pairs += 1;
                const value = it.next().?;
                try testing.expect(child != 0);
                try sameAsYaml(.{ .tree = full.tree, .idx = child, .arena = full.arena }, key);
                const full_value = full.tree.nodes.items[child].next_sibling;
                try sameAsYaml(.{ .tree = full.tree, .idx = full_value, .arena = full.arena }, value);
                child = full.tree.nodes.items[full_value].next_sibling;
            }
            try testing.expectEqual(@as(u32, 0), child);
            try testing.expectEqual(pairs, fast.len());
        },
    }
}

fn expectAgrees(src: []const u8) !void {
    var parser = Parser.init(testing.allocator);
    defer parser.deinit();

    var doc = yaml.parse(testing.allocator, src) catch |err| {
        std.debug.print("yaml rejected: {s}\n", .{src});
        return err;
    };
    defer doc.deinit();

    const fast = parser.parse(src) catch |err| {
        std.debug.print("yamll rejected: {s}\n", .{src});
        return err;
    };
    try sameAsYaml(doc.value, fast);
}

fn expectInvalid(src: []const u8) !void {
    var parser = Parser.init(testing.allocator);
    defer parser.deinit();
    _ = parser.parse(src) catch |err| {
        try testing.expectEqual(Error.Invalid, err);
        return;
    };
    std.debug.print("yamll accepted: {s}\n", .{src});
    return error.TestUnexpectedResult;
}

test "every yamll line means the same to a yaml parser" {
    const lines = [_][]const u8{
        "{id: 20261030T091500Z-a41f09, topic: test.failed, hops: 0, ok: true, gone: null}",
        "{payload: {files: [a/b.lua, \"c d\"], empty: {}}, tags: []}",
        "{text: \"line1\\nline2\\ttab \\\"q\\\" back\\\\slash\", u: \"caf\u{e9} \\u2028 \\x01\"}",
        "{\"a: b\": \"{x}\", \"\": \"\", neg: -1, f: \"1.5e3\", at: x@y.com, under: _x, path: /a/b}",
        "{\"key\":\"json style\",\"list\":[1,2,3],\"nested\":{\"deep\":[{\"a\":null}]}}",
        "[a, [b, [c, {d: e}]], \"f\"]",
        "{k: \"long string that is longer than sixteen bytes to cross a vector boundary \\\" with an escape near the end\"}",
        "{k: \"caf\u{e9} na\u{ef}ve \u{2192} long enough to fill several vector lanes of input\"}",
    };

    for (lines) |line| try expectAgrees(line);
}

test "yamll rejects what is outside its grammar" {
    const lines = [_][]const u8{
        "{a:b}",
        "{a: b c}",
        "{a: 'single'}",
        "{a: b} # comment",
        "a: b",
        "{a: &x b, c: *x}",
        "{a: !tag b}",
        "{a: @b}",
        "{a: b,}",
        "{a: \"unterminated}",
        "{a: \"bad \\q escape\"}",
        "{a: \"raw \x01 control\"}",
        "{a: \"bad \xff utf8\"}",
        "[a: b]",
        "{a: - }",
        "",
        "{a: [b]",
        "{a: [b}",
        "{a: {b: c}",
        "[[a]",
        "{a: b} x}",
        "[a] ]",
        "   ",
        "plain",
        "{",
        "}",
        "{a: yes}",
        "{a: No}",
        "{a: True}",
        "{a: NULL}",
        "{a: 1.5}",
        "{a: 0x1F}",
        "{a: 007}",
        "{a: 1_000}",
        "{a: +1}",
        "{a: .inf}",
        "{a: 2026-10-30}",
        "{a: 99999999999999999999}",
        "{a: -}",
        "{a: -x}",
        "{1: a}",
        "{true: a}",
        "{null: a}",
        "{a: ~}",
        "{n: 1}",
        "{Y: 1}",
    };

    for (lines) |line| try expectInvalid(line);
}

test "scalars carry their type" {
    var parser = Parser.init(testing.allocator);
    defer parser.deinit();

    const root = try parser.parse("{s: claude, q: \"42\", i: 42, neg: -7, t: true, f: false, z: null, qt: \"true\", qn: \"null\"}");

    try testing.expectEqualStrings("claude", root.get("s").?.string().?);
    try testing.expectEqualStrings("42", root.get("q").?.string().?);
    try testing.expectEqual(@as(?i64, 42), root.get("i").?.int());
    try testing.expectEqual(@as(?i64, -7), root.get("neg").?.int());
    try testing.expectEqual(@as(?bool, true), root.get("t").?.boolean());
    try testing.expectEqual(@as(?bool, false), root.get("f").?.boolean());
    try testing.expect(root.get("z").?.isNull());
    try testing.expectEqualStrings("true", root.get("qt").?.string().?);
    try testing.expectEqualStrings("null", root.get("qn").?.string().?);
    try testing.expect(root.get("q").?.int() == null);
    try testing.expect(root.get("i").?.string() == null);
}

test "random emitted lines round-trip with types and agree with yaml" {
    var prng = std.Random.DefaultPrng.init(42);
    const rng = prng.random();

    const pieces = [_][]const u8{ "a", "true", "no", "1.5", "a: b", "#x", "\"q\"", "\\", "\n", "\t", "\x01", "caf\u{e9}", "\u{2028}", "{", "]", ",", " ", "@", "-", "~", "null", "x/y.z", "7", "2026-10-30", "Yes", "0x1F" };

    const Value = union(enum) { string: []const u8, int: i64, boolean: bool, nil };

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(testing.allocator);
    var texts: [6]std.ArrayListUnmanaged(u8) = @splat(.empty);
    defer for (&texts) |*t| t.deinit(testing.allocator);
    var values: [6]Value = undefined;

    var parser = Parser.init(testing.allocator);
    defer parser.deinit();

    for (0..3000) |_| {
        out.clearRetainingCapacity();
        var e = emit.Emitter.init(testing.allocator, &out);
        try e.beginMap();

        const count = rng.intRangeAtMost(usize, 1, 6);
        for (0..count) |i| {
            texts[i].clearRetainingCapacity();
            for (0..rng.uintLessThan(usize, 6)) |_| try texts[i].appendSlice(testing.allocator, pieces[rng.uintLessThan(usize, pieces.len)]);

            var key_buf: [8]u8 = undefined;
            try e.key(try std.fmt.bufPrint(&key_buf, "k{d}", .{i}));

            values[i] = switch (rng.uintLessThan(u8, 5)) {
                0 => .{ .int = rng.int(i64) },
                1 => .{ .boolean = rng.boolean() },
                2 => .nil,
                else => .{ .string = texts[i].items },
            };
            switch (values[i]) {
                .string => |s| try e.string(s),
                .int => |v| try e.int(v),
                .boolean => |v| try e.boolean(v),
                .nil => try e.nil(),
            }
        }

        try e.endMap();
        try e.finish();
        try expectAgrees(out.items);

        const root = try parser.parse(out.items);
        for (0..count) |i| {
            var key_buf: [8]u8 = undefined;
            const node = root.get(try std.fmt.bufPrint(&key_buf, "k{d}", .{i})).?;
            switch (values[i]) {
                .string => |s| try testing.expectEqualStrings(s, node.string().?),
                .int => |v| try testing.expectEqual(@as(?i64, v), node.int()),
                .boolean => |v| try testing.expectEqual(@as(?bool, v), node.boolean()),
                .nil => try testing.expect(node.isNull()),
            }
        }
    }
}
