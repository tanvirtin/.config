const std = @import("std");
const builtin = @import("builtin");

const Io = std.Io;
const Environ = std.process.Environ;

var process_io: ?Io = null;
var process_environ: ?*const Environ.Map = null;
var test_environ: ?Environ.Map = null;

pub fn init(init_args: std.process.Init) void {
    process_io = init_args.io;
    process_environ = init_args.environ_map;
}

pub fn io() Io {
    if (process_io) |value| return value;
    if (builtin.is_test) return std.testing.io;
    @panic("runtime.init was not called");
}

fn environment() *const Environ.Map {
    if (process_environ) |map| return map;
    if (builtin.is_test) {
        if (test_environ == null) test_environ = std.testing.environ.createMap(std.heap.page_allocator) catch @panic("out of memory");
        return &test_environ.?;
    }
    @panic("runtime.init was not called");
}

pub fn envMap() *const Environ.Map {
    return environment();
}

pub fn env(name: []const u8) ?[]const u8 {
    return environment().get(name);
}

pub fn getEnvVarOwned(allocator: std.mem.Allocator, name: []const u8) error{ EnvironmentVariableNotFound, OutOfMemory }![]u8 {
    const value = env(name) orelse return error.EnvironmentVariableNotFound;
    return allocator.dupe(u8, value);
}

test "env reads the process environment" {
    try std.testing.expect(env("PATH") != null);
    try std.testing.expect(env("TIN_NO_SUCH_VARIABLE_SET") == null);
    const owned = try getEnvVarOwned(std.testing.allocator, "PATH");
    defer std.testing.allocator.free(owned);
    try std.testing.expect(owned.len > 0);
    try std.testing.expectError(error.EnvironmentVariableNotFound, getEnvVarOwned(std.testing.allocator, "TIN_NO_SUCH_VARIABLE_SET"));
}
