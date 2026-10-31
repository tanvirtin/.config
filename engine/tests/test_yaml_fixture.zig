const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const path = args.next() orelse std.process.exit(1);
    const dir = std.fs.path.dirname(path) orelse std.process.exit(1);
    const base = std.fs.path.basename(dir);

    if (std.mem.endsWith(u8, base, "-crash")) std.process.exit(3);
    if (std.mem.endsWith(u8, base, "-hang")) {
        init.io.sleep(.fromSeconds(60), .awake) catch {};
        std.process.exit(0);
    }
    if (std.mem.endsWith(u8, base, "-misaccept")) std.process.exit(0);
    if (std.mem.endsWith(u8, base, "-misreject")) std.process.exit(2);

    const err = std.fs.path.join(allocator, &.{ dir, "error" }) catch std.process.exit(0);
    defer allocator.free(err);
    std.Io.Dir.cwd().access(init.io, err, .{}) catch std.process.exit(0);
    std.process.exit(2);
}
