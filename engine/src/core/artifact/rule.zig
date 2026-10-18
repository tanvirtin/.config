const std = @import("std");
const yaml = @import("yaml");
const template = @import("../../lib/template.zig");

const Rule = @This();

id: []const u8 = "",
description: []const u8,
content: []const u8,

pub fn compose(allocator: std.mem.Allocator, text: []const u8, include: []const []const u8, rules: []const Rule) ![]const u8 {
    if (include.len == 0) return text;

    var vars: std.ArrayListUnmanaged(struct { []const u8, []const u8 }) = .{};
    defer vars.deinit(allocator);
    for (include) |rule_id| {
        for (rules) |rule| {
            if (std.mem.eql(u8, rule.id, rule_id)) {
                try vars.append(allocator, .{ rule_id, rule.content });
                break;
            }
        }
    }

    return template.render(allocator, text, vars.items);
}

test "decode succeeds with description and content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const doc = try yaml.parse(arena.allocator(), "description: clarity rules\ncontent: use early returns");
    const rule = try yaml.decode(Rule, arena.allocator(), doc);
    try std.testing.expectEqualStrings("clarity rules", rule.description);
    try std.testing.expectEqualStrings("use early returns", rule.content);
    try std.testing.expectEqualStrings("", rule.id);
}

test "decode fails without description" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const doc = try yaml.parse(arena.allocator(), "content: some content");
    try std.testing.expectError(yaml.DecodeError.MissingField, yaml.decode(Rule, arena.allocator(), doc));
}

test "decode fails without content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const doc = try yaml.parse(arena.allocator(), "description: no content");
    try std.testing.expectError(yaml.DecodeError.MissingField, yaml.decode(Rule, arena.allocator(), doc));
}

test "decode preserves multiline content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const doc = try yaml.parse(arena.allocator(), "description: design rules\ncontent: |\n  line one\n  line two\n");
    const rule = try yaml.decode(Rule, arena.allocator(), doc);
    try std.testing.expectEqualStrings("design rules", rule.description);
    try std.testing.expect(std.mem.indexOf(u8, rule.content, "line one") != null);
    try std.testing.expect(std.mem.indexOf(u8, rule.content, "line two") != null);
}
