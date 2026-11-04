const std = @import("std");
const fs = @import("fs.zig");
const runtime = @import("runtime.zig");

pub const FsError = error{
    HomeNotSet,
};

pub fn homeDir() FsError![]const u8 {
    return runtime.env("HOME") orelse return FsError.HomeNotSet;
}

pub fn ensureDirectoryExists(path: []const u8) !void {
    std.Io.Dir.createDirAbsolute(runtime.io(), path, .default_dir) catch |e| switch (e) {
        error.PathAlreadyExists => return,
        error.FileNotFound => {
            const parent = std.fs.path.dirname(path) orelse return e;
            if (parent.len > 0 and !std.mem.eql(u8, parent, path)) {
                try ensureDirectoryExists(parent);
                try ensureDirectoryExists(path);
            }
        },
        else => return e,
    };
}

pub fn ensureParentDirExists(path: []const u8) !void {
    const dir = std.fs.path.dirname(path) orelse return;
    ensureDirectoryExists(dir) catch |e| {
        switch (e) {
            error.FileNotFound => {
                try ensureParentDirExists(dir);
                try ensureDirectoryExists(dir);
            },
            else => return e,
        }
    };
}

pub fn realPathAlloc(allocator: std.mem.Allocator, dir: std.Io.Dir, sub_path: []const u8) ![]u8 {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const len = try dir.realPathFile(runtime.io(), sub_path, &buffer);
    return allocator.dupe(u8, buffer[0..len]);
}

pub fn pathExists(path: []const u8) bool {
    std.Io.Dir.cwd().access(runtime.io(), path, .{}) catch return false;
    return true;
}

pub fn pathPresent(path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(runtime.io(), path, .{ .follow_symlinks = false }) catch |e| switch (e) {
        error.FileNotFound => return false,
        else => return true,
    };
    return true;
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(runtime.io(), path, allocator, .limited(256 * 1024));
}

pub fn writeFile(path: []const u8, content: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(runtime.io(), .{ .sub_path = path, .data = content });
}

pub fn copyFile(source: []const u8, target: []const u8) !void {
    try ensureParentDirExists(target);
    try std.Io.Dir.copyFileAbsolute(source, target, runtime.io(), .{});
}

pub fn filesEqual(source: []const u8, target: []const u8) !bool {
    const io = runtime.io();
    const source_file = try std.Io.Dir.openFileAbsolute(io, source, .{});
    defer source_file.close(io);
    const target_file = try std.Io.Dir.openFileAbsolute(io, target, .{});
    defer target_file.close(io);

    const source_stat = try source_file.stat(io);
    const target_stat = try target_file.stat(io);
    if (source_stat.kind != .file or target_stat.kind != .file) return error.NotAFile;
    if (source_stat.size != target_stat.size) return false;

    var source_buf: [64 * 1024]u8 = undefined;
    var target_buf: [64 * 1024]u8 = undefined;
    var offset: u64 = 0;
    while (true) {
        const source_read = try source_file.readPositionalAll(io, &source_buf, offset);
        const target_read = try target_file.readPositionalAll(io, &target_buf, offset);
        if (source_read != target_read) return false;
        if (!std.mem.eql(u8, source_buf[0..source_read], target_buf[0..target_read])) return false;
        if (source_read == 0) return true;
        offset += source_read;
    }
}

test "homeDir returns a value or error" {
    if (homeDir()) |home| {
        try std.testing.expect(home.len > 0);
    } else |_| {}
}

test "pathExists for root directory" {
    try std.testing.expect(pathExists("/"));
}

fn tmpDirAbs() !struct { dir: []const u8, tmp: std.testing.TmpDir } {
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();
    const dir = try realPathAlloc(std.testing.allocator, tmp.parent_dir, &tmp.sub_path);
    return .{ .dir = dir, .tmp = tmp };
}

fn join(dir: []const u8, name: []const u8) ![]const u8 {
    return try std.fs.path.join(std.testing.allocator, &.{ dir, name });
}

test "filesEqual compares contents and tolerates missing files" {
    var t = try tmpDirAbs();
    defer std.testing.allocator.free(t.dir);
    defer t.tmp.cleanup();

    const a = try join(t.dir, "a");
    defer std.testing.allocator.free(a);
    const b = try join(t.dir, "b");
    defer std.testing.allocator.free(b);
    const c = try join(t.dir, "missing");
    defer std.testing.allocator.free(c);

    try writeFile(a, "hello");
    try writeFile(b, "hello");
    try std.testing.expect(try filesEqual(a, b));
    try writeFile(b, "world");
    try std.testing.expect(!try filesEqual(a, b));
    try std.testing.expectError(error.FileNotFound, filesEqual(a, c));
}

test "copyFile overwrites the destination" {
    var t = try tmpDirAbs();
    defer std.testing.allocator.free(t.dir);
    defer t.tmp.cleanup();

    const source = try join(t.dir, "source");
    defer std.testing.allocator.free(source);
    const target = try join(t.dir, "target");
    defer std.testing.allocator.free(target);

    try writeFile(source, "fresh");
    try writeFile(target, "stale");
    try copyFile(source, target);
    try std.testing.expect(try filesEqual(source, target));
}

test "pathExists for nonexistent path" {
    try std.testing.expect(!pathExists("/nonexistent_path_that_should_not_exist"));
}

test "ensureDirectoryExists creates and tolerates existing" {
    var t = try tmpDirAbs();
    defer std.testing.allocator.free(t.dir);
    defer t.tmp.cleanup();

    const path = try join(t.dir, "nested_dir");
    defer std.testing.allocator.free(path);

    try ensureDirectoryExists(path);
    try std.testing.expect(pathExists(path));
    try ensureDirectoryExists(path);
}

test "ensureParentDirExists creates parent chain" {
    var t = try tmpDirAbs();
    defer std.testing.allocator.free(t.dir);
    defer t.tmp.cleanup();

    const path = try join(t.dir, "parent/child/file.txt");
    defer std.testing.allocator.free(path);

    try ensureParentDirExists(path);
    const child = try join(t.dir, "parent/child");
    defer std.testing.allocator.free(child);
    try std.testing.expect(pathExists(child));
}

test "pathPresent sees a dangling symlink that pathExists does not" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const root = try realPathAlloc(a, tmp.parent_dir, &tmp.sub_path);
    const link = try std.fs.path.join(a, &.{ root, "dangling" });
    const file = try std.fs.path.join(a, &.{ root, "file" });
    try std.Io.Dir.symLinkAbsolute(runtime.io(), "/nonexistent/target", link, .{});
    try writeFile(file, "x");

    try std.testing.expect(pathPresent(file));
    try std.testing.expect(pathPresent(link));
    try std.testing.expect(!pathExists(link));
    try std.testing.expect(!pathPresent(try std.fs.path.join(a, &.{ root, "missing" })));
}
