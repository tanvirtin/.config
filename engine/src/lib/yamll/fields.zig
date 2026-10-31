const std = @import("std");
const scan = @import("scan.zig");
const scalar = @import("scalar.zig");
const parse = @import("parse.zig");

const Error = parse.Error;
const Kind = parse.Kind;
const lanes = scan.lanes;
const Vec = scan.Vec;

pub const Scalar = struct {
    kind: Kind,
    raw: []const u8,
    escaped: bool,
};

pub const Value = union(enum) {
    scalar: Scalar,
    container: []const u8,
};

pub const Field = struct {
    key: []const u8,
    value: Value,
};

pub const Fields = struct {
    src: []const u8,
    pos: usize,
    done: bool = false,

    pub fn init(line: []const u8) Error!Fields {
        var end = line.len;
        while (end > 0 and line[end - 1] == ' ') end -= 1;
        if (end == 0 or line[end - 1] != '}') return Error.Invalid;
        const src = line[0..end];

        const pos = scan.skipSpaces(src, 0);
        if (src[pos] != '{') return Error.Invalid;
        return .{ .src = src, .pos = pos + 1 };
    }

    pub fn next(self: *Fields) Error!?Field {
        if (self.done) return null;

        self.pos = scan.skipSpaces(self.src, self.pos);
        if (self.src[self.pos] == '}') {
            self.done = true;
            return null;
        }

        const key = try self.scalarAt();
        if (key.kind != .string or key.escaped) return Error.Invalid;
        self.pos = scan.skipSpaces(self.src, self.pos);
        if (self.src[self.pos] != ':') return Error.Invalid;
        self.pos = scan.skipSpaces(self.src, self.pos + 1);

        const value: Value = switch (self.src[self.pos]) {
            '{', '[' => .{ .container = try self.skipContainer() },
            else => .{ .scalar = try self.scalarAt() },
        };

        if (self.pos >= self.src.len) return Error.Invalid;
        self.pos = scan.skipSpaces(self.src, self.pos);
        switch (self.src[self.pos]) {
            ',' => self.pos += 1,
            '}' => {
                self.pos += 1;
                self.done = true;
            },
            else => return Error.Invalid,
        }

        return .{ .key = key.raw, .value = value };
    }

    fn scalarAt(self: *Fields) Error!Scalar {
        const src = self.src;

        if (src[self.pos] == '"') {
            const start = self.pos + 1;
            var pos = start;
            var escaped = false;

            while (true) {
                while (pos + lanes <= src.len) {
                    const v: Vec = src[pos..][0..lanes].*;
                    if (scan.firstSet(scan.quoteOrEscape(v))) |at| {
                        pos += at;
                        break;
                    }
                    pos += lanes;
                } else {
                    while (pos < src.len and src[pos] != '"' and src[pos] != '\\') pos += 1;
                    if (pos >= src.len) return Error.Invalid;
                }

                if (src[pos] == '"') break;
                escaped = true;
                pos += 2;
                if (pos >= src.len) return Error.Invalid;
            }

            self.pos = pos + 1;
            return .{ .kind = .string, .raw = src[start..pos], .escaped = escaped };
        }

        const start = self.pos;
        const stop = scan.plainEnd(src, start);
        if (stop == start) return Error.Invalid;
        if (src[stop] != ':' and !scan.flowEnd(src[stop])) return Error.Invalid;

        const text = src[start..stop];
        const kind: Kind = switch (scalar.classify(text)) {
            .string => .string,
            .int => .int,
            .boolean => .boolean,
            .null => .null,
            .ambiguous => return Error.Invalid,
        };

        self.pos = stop;
        return .{ .kind = kind, .raw = text, .escaped = false };
    }

    fn skipContainer(self: *Fields) Error![]const u8 {
        const src = self.src;
        const start = self.pos;
        var depth: usize = 0;
        var pos = start;

        while (pos < src.len) : (pos += 1) {
            switch (src[pos]) {
                '{', '[' => depth += 1,
                '}', ']' => {
                    depth -= 1;
                    if (depth == 0) {
                        self.pos = pos + 1;
                        return src[start..self.pos];
                    }
                },
                '"' => {
                    pos += 1;
                    while (pos < src.len and src[pos] != '"') : (pos += 1) {
                        if (src[pos] == '\\') pos += 1;
                    }
                },
                else => {},
            }
        }

        return Error.Invalid;
    }
};

const testing = std.testing;

test "fields reads the envelope without scanning the payload" {
    var fields = try Fields.init("{id: x1, topic: session.s_1, hops: 2, ok: true, payload: {text: \"a } ] \\\" b\", list: [1, {x: y}]}, tail: \"t\\\\\"}");

    const expected = [_]struct { key: []const u8, raw: []const u8, kind: ?Kind }{
        .{ .key = "id", .raw = "x1", .kind = .string },
        .{ .key = "topic", .raw = "session.s_1", .kind = .string },
        .{ .key = "hops", .raw = "2", .kind = .int },
        .{ .key = "ok", .raw = "true", .kind = .boolean },
        .{ .key = "payload", .raw = "{text: \"a } ] \\\" b\", list: [1, {x: y}]}", .kind = null },
        .{ .key = "tail", .raw = "t\\\\", .kind = .string },
    };

    for (expected) |want| {
        const field = (try fields.next()).?;
        try testing.expectEqualStrings(want.key, field.key);
        switch (field.value) {
            .scalar => |s| {
                try testing.expectEqualStrings(want.raw, s.raw);
                try testing.expectEqual(want.kind.?, s.kind);
            },
            .container => |raw| {
                try testing.expectEqualStrings(want.raw, raw);
                try testing.expect(want.kind == null);
            },
        }
    }

    try testing.expect((try fields.next()) == null);
}

test "fields rejects ambiguous scalars and non-string keys" {
    const lines = [_][]const u8{ "{a: yes}", "{1: a}", "{a: 1.5}", "{\"k\\n\": v}", "{a: b", "a: b" };
    for (lines) |line| {
        var fields = Fields.init(line) catch continue;
        while (fields.next() catch break) |_| {} else return error.TestUnexpectedResult;
    }
}
