const std = @import("std");
const output = @import("../lib/output.zig");
const shared = @import("shared.zig");
const apply = @import("../core/apply.zig");

pub const meta = .{
    .name = "fonts",
    .description = "Install fonts to system font directory",
};

pub fn execute(allocator: std.mem.Allocator, _: []const []const u8) u8 {
    const env = shared.environment(allocator) orelse return 1;
    return apply.installFonts(allocator, env.paths, env.config);
}
