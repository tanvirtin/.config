const std = @import("std");
const yaml = @import("yaml");

const accepted_exit: u8 = 0;
const rejection_exit: u8 = 2;
const operational_exit: u8 = 1;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const path = args.next() orelse {
        std.debug.print("test_yaml_one: missing input path\n", .{});
        std.process.exit(operational_exit);
    };
    const content = std.Io.Dir.cwd().readFileAlloc(init.io, path, arena, .limited(64 * 1024 * 1024)) catch |e| {
        switch (e) {
            error.FileNotFound, error.AccessDenied => std.debug.print("test_yaml_one: cannot open {s}\n", .{path}),
            else => std.debug.print("test_yaml_one: cannot read {s}\n", .{path}),
        }
        std.process.exit(operational_exit);
    };
    if (yaml.parse(arena, content)) |doc| {
        _ = doc;
        std.process.exit(accepted_exit);
    } else |_| {
        std.process.exit(rejection_exit);
    }
}
