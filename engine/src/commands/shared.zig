const std = @import("std");
const output = @import("../lib/output.zig");
const Environment = @import("../core/environment.zig");
const Paths = Environment.Paths;

pub fn paths(allocator: std.mem.Allocator) ?Paths {
    return Paths.init(allocator) catch |e| {
        output.err("could not resolve environment paths: {s}", .{reason(e)});
        return null;
    };
}

pub fn environment(allocator: std.mem.Allocator) ?Environment {
    return Environment.init(allocator) catch |e| {
        output.err("could not resolve the environment: {s}", .{reason(e)});
        return null;
    };
}

fn reason(e: anyerror) []const u8 {
    return switch (e) {
        error.HomeNotSet => "HOME is not set",
        else => @errorName(e),
    };
}

test "reason names an unset HOME in words" {
    try std.testing.expectEqualStrings("HOME is not set", reason(error.HomeNotSet));
    try std.testing.expectEqualStrings("OutOfMemory", reason(error.OutOfMemory));
}
