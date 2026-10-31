const std = @import("std");
const runtime = @import("../lib/runtime.zig");
const fs = @import("../lib/fs.zig");

const Symlink = @This();

source: []const u8,
target: []const u8,
name: []const u8,

copy: bool = false,

pub const Status = enum {
    linked,
    missing,
    wrong_target,
    not_a_symlink,
    broken,
    source_missing,
};

pub fn status(self: *const Symlink) Status {
    if (self.copy) return self.copyStatus();

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const link_len = std.Io.Dir.readLinkAbsolute(runtime.io(), self.target, &buf) catch |e| switch (e) {
        error.FileNotFound => return .missing,
        error.NotLink => return .not_a_symlink,
        else => return .broken,
    };
    const link_target = buf[0..link_len];

    if (std.mem.eql(u8, link_target, self.source)) {
        if (!fs.pathExists(self.source)) return .source_missing;
        return .linked;
    }

    return .wrong_target;
}

fn copyStatus(self: *const Symlink) Status {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    if (std.Io.Dir.readLinkAbsolute(runtime.io(), self.target, &buf)) |_| {
        return .wrong_target;
    } else |e| switch (e) {
        error.FileNotFound => return .missing,
        error.NotLink => {},
        else => return .broken,
    }

    const equal = fs.filesEqual(self.source, self.target) catch |e| switch (e) {
        error.NotAFile => return .not_a_symlink,
        error.FileNotFound => return .source_missing,
        else => return .broken,
    };

    return if (equal) .linked else .wrong_target;
}

pub fn link(self: *const Symlink) !void {
    if (self.copy) return self.copyInto();

    try fs.ensureParentDirExists(self.target);
    std.Io.Dir.symLinkAbsolute(runtime.io(), self.source, self.target, .{}) catch |e| switch (e) {
        error.PathAlreadyExists => {
            try self.unlink();
            try std.Io.Dir.symLinkAbsolute(runtime.io(), self.source, self.target, .{});
        },
        else => return e,
    };
}

fn copyInto(self: *const Symlink) !void {
    try self.unlink();
    try fs.copyFile(self.source, self.target);
}

pub const RepairError = error{ BackupFailed, LinkFailed };

pub fn repair(self: *const Symlink, allocator: std.mem.Allocator, current: Status) RepairError!bool {
    const backed_up = self.backupBeforeRepair(current);
    if (backed_up) self.backup(allocator) catch return error.BackupFailed;
    self.link() catch return error.LinkFailed;
    return backed_up;
}

pub fn backupBeforeRepair(self: *const Symlink, current: Status) bool {
    if (current == .broken) return false;
    if (current == .not_a_symlink) return true;
    return !self.copy;
}

pub fn unlink(self: *const Symlink) !void {
    std.Io.Dir.deleteFileAbsolute(runtime.io(), self.target) catch |e| switch (e) {
        error.FileNotFound => return,
        error.IsDir => {
            std.Io.Dir.cwd().deleteTree(runtime.io(), self.target) catch return;
        },
        else => return e,
    };
}

pub fn backup(self: *const Symlink, allocator: std.mem.Allocator) !void {
    const backup_path = try std.fmt.allocPrint(allocator, "{s}.tin.bak", .{self.target});
    defer allocator.free(backup_path);
    std.Io.Dir.renameAbsolute(self.target, backup_path, runtime.io()) catch |e| switch (e) {
        error.FileNotFound => return,
        else => return e,
    };
}

pub fn restore(self: *const Symlink, allocator: std.mem.Allocator) !void {
    const backup_path = try std.fmt.allocPrint(allocator, "{s}.tin.bak", .{self.target});
    defer allocator.free(backup_path);
    std.Io.Dir.renameAbsolute(backup_path, self.target, runtime.io()) catch |e| switch (e) {
        error.FileNotFound => return,
        else => return e,
    };
}

test "status returns missing for nonexistent path" {
    const s = Symlink{
        .source = "/nonexistent/source",
        .target = "/nonexistent/target",
        .name = "test",
    };
    try std.testing.expectEqual(Status.missing, s.status());
}

test "link creates symlink and status is linked" {
    const source = "/tmp/tin_test_symlink_source";
    const target = "/tmp/tin_test_symlink_target";
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
    std.Io.Dir.deleteFileAbsolute(runtime.io(), source) catch {};
    const f = try std.Io.Dir.createFileAbsolute(runtime.io(), source, .{});
    f.close(runtime.io());
    const s = Symlink{ .source = source, .target = target, .name = "test" };
    try s.link();
    try std.testing.expectEqual(Status.linked, s.status());
    try s.unlink();
    try std.testing.expectEqual(Status.missing, s.status());
    std.Io.Dir.deleteFileAbsolute(runtime.io(), source) catch {};
}

test "status returns wrong_target for mismatched symlink" {
    const target = "/tmp/tin_test_wrong_target";
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
    std.Io.Dir.symLinkAbsolute(runtime.io(), "/some/other/path", target, .{}) catch return;
    const s = Symlink{ .source = "/expected/path", .target = target, .name = "test" };
    try std.testing.expectEqual(Status.wrong_target, s.status());
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
}

test "backup and restore round-trips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const target = "/tmp/tin_test_backup_target";
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
    std.Io.Dir.deleteFileAbsolute(runtime.io(), "/tmp/tin_test_backup_target.tin.bak") catch {};
    const f = try std.Io.Dir.createFileAbsolute(runtime.io(), target, .{});
    f.close(runtime.io());
    const s = Symlink{ .source = "/x", .target = target, .name = "test" };
    try s.backup(arena.allocator());
    try std.testing.expect(!fs.pathExists(target));
    try std.testing.expect(fs.pathExists("/tmp/tin_test_backup_target.tin.bak"));
    try s.restore(arena.allocator());
    try std.testing.expect(fs.pathExists(target));
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
}

test "unlink tolerates missing target" {
    const s = Symlink{ .source = "/x", .target = "/tmp/tin_test_unlink_missing", .name = "test" };
    try s.unlink();
}

test "status returns not_a_symlink for regular file" {
    const target = "/tmp/tin_test_not_symlink";
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
    const f = try std.Io.Dir.createFileAbsolute(runtime.io(), target, .{});
    f.close(runtime.io());
    const s = Symlink{ .source = "/x", .target = target, .name = "test" };
    try std.testing.expectEqual(Status.not_a_symlink, s.status());
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
}

test "copy link installs a real file and status tracks drift" {
    const source = "/tmp/tin_test_copy_link_source";
    const target = "/tmp/tin_test_copy_link_target";
    try fs.writeFile(source, "version one");
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};

    const s = Symlink{ .source = source, .target = target, .name = "test", .copy = true };
    try std.testing.expectEqual(Status.missing, s.status());
    try s.link();
    try std.testing.expectEqual(Status.linked, s.status());
    try std.testing.expect(!isSymlink(target));

    try fs.writeFile(source, "version two");
    try std.testing.expectEqual(Status.wrong_target, s.status());
    try s.link();
    try std.testing.expectEqual(Status.linked, s.status());

    try s.unlink();
    try std.testing.expectEqual(Status.missing, s.status());
    std.Io.Dir.deleteFileAbsolute(runtime.io(), source) catch {};
}

test "copy link replaces a stale symlink" {
    const source = "/tmp/tin_test_copy_replace_source";
    const target = "/tmp/tin_test_copy_replace_target";
    try fs.writeFile(source, "payload");
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
    try std.Io.Dir.symLinkAbsolute(runtime.io(), source, target, .{});

    const s = Symlink{ .source = source, .target = target, .name = "test", .copy = true };
    try std.testing.expectEqual(Status.wrong_target, s.status());
    try s.link();
    try std.testing.expectEqual(Status.linked, s.status());
    try std.testing.expect(!isSymlink(target));

    try s.unlink();
    std.Io.Dir.deleteFileAbsolute(runtime.io(), source) catch {};
}

test "status returns source_missing for dangling symlink" {
    const source = "/tmp/tin_test_src_missing_source";
    const target = "/tmp/tin_test_src_missing_target";
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
    std.Io.Dir.deleteFileAbsolute(runtime.io(), source) catch {};
    try std.Io.Dir.symLinkAbsolute(runtime.io(), source, target, .{});

    const s = Symlink{ .source = source, .target = target, .name = "test" };
    try std.testing.expectEqual(Status.source_missing, s.status());

    const f = try std.Io.Dir.createFileAbsolute(runtime.io(), source, .{});
    f.close(runtime.io());
    try std.testing.expectEqual(Status.linked, s.status());

    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
    std.Io.Dir.deleteFileAbsolute(runtime.io(), source) catch {};
}

test "copy status returns source_missing when source gone" {
    const source = "/tmp/tin_test_copy_src_missing_source";
    const target = "/tmp/tin_test_copy_src_missing_target";
    std.Io.Dir.deleteFileAbsolute(runtime.io(), source) catch {};
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
    const f = try std.Io.Dir.createFileAbsolute(runtime.io(), target, .{});
    f.close(runtime.io());

    const s = Symlink{ .source = source, .target = target, .name = "test", .copy = true };
    try std.testing.expectEqual(Status.source_missing, s.status());

    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
}

test "repair replaces a wrong-target symlink" {
    const source = "/tmp/tin_test_repair_source";
    const target = "/tmp/tin_test_repair_target";
    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
    std.Io.Dir.deleteFileAbsolute(runtime.io(), source) catch {};
    const f = try std.Io.Dir.createFileAbsolute(runtime.io(), source, .{});
    f.close(runtime.io());
    try std.Io.Dir.symLinkAbsolute(runtime.io(), "/some/other/path", target, .{});

    const s = Symlink{ .source = source, .target = target, .name = "test" };
    try std.testing.expectEqual(Status.wrong_target, s.status());
    const backed_up = try s.repair(std.testing.allocator, s.status());
    try std.testing.expect(backed_up);
    try std.testing.expectEqual(Status.linked, s.status());

    std.Io.Dir.deleteFileAbsolute(runtime.io(), target) catch {};
    std.Io.Dir.deleteFileAbsolute(runtime.io(), source) catch {};
    std.Io.Dir.deleteFileAbsolute(runtime.io(), "/tmp/tin_test_repair_target.tin.bak") catch {};
}

fn isSymlink(path: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    _ = std.Io.Dir.readLinkAbsolute(runtime.io(), path, &buf) catch return false;
    return true;
}
