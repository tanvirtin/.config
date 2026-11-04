const std = @import("std");
const runtime = @import("../lib/runtime.zig");
const fs = @import("../lib/fs.zig");
const yaml = @import("yaml");
const output = @import("../lib/output.zig");
const process = @import("../lib/process.zig");
const Environment = @import("environment.zig");
const template = @import("../lib/template.zig");
const platform = @import("../platform/platform.zig");
const expression = @import("../schemalang/sublang/expression/mod.zig");
const apply = @import("apply.zig");
const diag = @import("../schemalang/diagnostic.zig");

const Recipe = @This();

pub const RecipeError = error{
    MissingName,
    MissingSteps,
    InvalidStep,
    ParseFailed,
    ExecutionFailed,
};

pub const Action = union(enum) {
    run: []const u8,
    install: []const u8,
    recipe: []const u8,
    link,
    fonts,
    mkdir: []const u8,
    download: struct { url: []const u8, to: []const u8 },
    clone: struct { repo: []const u8, to: []const u8 },
};

pub const Step = struct {
    name: ?[]const u8 = null,
    action: Action,
    condition: ?[]const u8 = null,
};

name: []const u8,
description: ?[]const u8,
steps: []const Step,

pub fn parse(allocator: std.mem.Allocator, content: []const u8) !Recipe {
    var doc = yaml.parse(allocator, content) catch return RecipeError.ParseFailed;
    defer doc.deinit();

    const name_raw = if (doc.getMapping("name")) |v| v.getString() orelse return RecipeError.MissingName else return RecipeError.MissingName;
    const name = try allocator.dupe(u8, name_raw);

    const description = if (doc.getMapping("description")) |v| blk: {
        const s = v.getString() orelse break :blk null;
        break :blk try allocator.dupe(u8, s);
    } else null;

    const steps_val = doc.getMapping("steps") orelse return RecipeError.MissingSteps;
    const steps_seq = steps_val.getSequence() orelse return RecipeError.MissingSteps;

    var steps: std.ArrayListUnmanaged(Step) = .empty;
    defer steps.deinit(allocator);

    for (steps_seq) |step_val| {
        const action = try parseAction(step_val, allocator);
        try steps.append(allocator, .{
            .name = if (step_val.getMapping("name")) |v| blk: {
                const s = v.getString() orelse break :blk null;
                break :blk try allocator.dupe(u8, s);
            } else null,
            .action = action,
            .condition = if (step_val.getMapping("if")) |v| blk: {
                const s = v.getString() orelse break :blk null;
                break :blk try allocator.dupe(u8, s);
            } else null,
        });
    }

    return .{
        .name = name,
        .description = description,
        .steps = try steps.toOwnedSlice(allocator),
    };
}

fn parseAction(step_val: yaml.Value, allocator: std.mem.Allocator) !Action {
    if (step_val.getMapping("run")) |v| {
        if (v.getString()) |s| return .{ .run = try allocator.dupe(u8, s) };
    }
    if (step_val.getMapping("install")) |v| {
        if (v.getString()) |s| return .{ .install = try allocator.dupe(u8, s) };
    }
    if (step_val.getMapping("recipe")) |v| {
        if (v.getString()) |s| return .{ .recipe = try allocator.dupe(u8, s) };
    }
    if (step_val.getMapping("link") != null) return .link;
    if (step_val.getMapping("fonts") != null) return .fonts;
    if (step_val.getMapping("mkdir")) |v| {
        if (v.getString()) |s| return .{ .mkdir = try allocator.dupe(u8, s) };
    }
    if (step_val.getMapping("download")) |dl| {
        const url = if (dl.getString()) |s|
            s
        else if (dl.getMapping("url")) |v|
            v.getString() orelse return RecipeError.InvalidStep
        else
            return RecipeError.InvalidStep;

        const to_val = if (dl.getString() != null)
            step_val.getMapping("to")
        else
            dl.getMapping("to");
        const to = (to_val orelse return RecipeError.InvalidStep).getString() orelse return RecipeError.InvalidStep;

        return .{ .download = .{
            .url = try allocator.dupe(u8, url),
            .to = try allocator.dupe(u8, to),
        } };
    }
    if (step_val.getMapping("clone")) |v| {
        if (v.getString()) |repo| {
            const to_val = step_val.getMapping("to") orelse return RecipeError.InvalidStep;
            const to_str = to_val.getString() orelse return RecipeError.InvalidStep;
            return .{ .clone = .{
                .repo = try allocator.dupe(u8, repo),
                .to = try allocator.dupe(u8, to_str),
            } };
        }
    }
    return RecipeError.InvalidStep;
}

pub fn execute(self: *const Recipe, allocator: std.mem.Allocator) anyerror!void {
    const paths = Environment.Paths.init(allocator) catch {
        output.err("could not resolve environment paths", .{});
        return RecipeError.ExecutionFailed;
    };

    const loaded_config = try Environment.Config.load(allocator, paths);
    const config = loaded_config orelse Environment.Config{ .doc = null };
    const vars = Environment.IdentityProvider.getTemplateVars(allocator, config) catch &[_]Environment.TemplateVar{};

    try self.runSteps(allocator, vars, paths, config);
}

pub fn runSteps(
    self: *const Recipe,
    allocator: std.mem.Allocator,
    vars: []const Environment.TemplateVar,
    paths: Environment.Paths,
    config: Environment.Config,
) anyerror!void {
    output.record(.info, .{ .action = "recipe", .target = self.name, .status = "running" }, "Executing recipe: {s}", .{self.name});
    if (self.description) |desc| {
        output.plain("  {s}", .{desc});
    }

    var cond_env: expression.EvalEnv = undefined;
    var cond_env_ready = false;

    for (self.steps) |step| {
        if (step.condition) |condition| {
            if (!cond_env_ready) {
                cond_env = buildConditionEnv(allocator) catch |err| {
                    output.err("could not build condition environment: {s}", .{@errorName(err)});
                    return RecipeError.ExecutionFailed;
                };
                cond_env_ready = true;
            }
            if (!checkCondition(condition, allocator, &cond_env)) {
                if (step.name) |name| {
                    output.record(.info, .{ .action = "step", .target = name, .status = "skipped" }, "  skip {s} (condition not met)", .{name});
                }
                continue;
            }
        }

        if (step.name) |name| {
            output.record(.info, .{ .action = "step", .target = name, .status = "running" }, "  Step: {s}", .{name});
        }

        executeAction(allocator, step.action, vars, paths, config) catch |err| {
            output.record(.err, .{ .action = "step", .target = step.name orelse "unnamed", .status = "failed" }, "  step failed: {s} ({s})", .{ step.name orelse "unnamed", @errorName(err) });
            return RecipeError.ExecutionFailed;
        };
    }
}

fn renderField(allocator: std.mem.Allocator, text: []const u8, vars: []const Environment.TemplateVar) []const u8 {
    return template.render(allocator, text, vars) catch |e| {
        output.record(.warn, .{ .action = "render", .target = text, .status = "failed" }, "template render failed ({s}); using raw text", .{@errorName(e)});
        return text;
    };
}

fn executeAction(allocator: std.mem.Allocator, action: Action, vars: []const Environment.TemplateVar, paths: Environment.Paths, config: Environment.Config) anyerror!void {
    switch (action) {
        .run => |cmd| {
            const rendered = renderField(allocator, cmd, vars);
            try process.runShell(allocator, rendered);
        },
        .install => |pkg| {
            try platform.installPackage(allocator, pkg);
        },
        .recipe => |recipe_name| {
            const rendered = renderField(allocator, recipe_name, vars);
            var search = try paths.recipeSearch(allocator);
            defer search.deinit(allocator);
            const found = (try search.resolve(allocator, rendered)) orelse {
                output.err("recipe not found: {s}", .{rendered});
                return error.RecipeNotFound;
            };
            defer allocator.free(found.path);
            const content = try fs.readFileAlloc(allocator, found.path);
            defer allocator.free(content);
            const sub = try parse(allocator, content);
            try sub.runSteps(allocator, vars, paths, config);
        },
        .link => {
            if (apply.linkManaged(allocator, paths, config) != 0) return error.LinkFailed;
        },
        .fonts => {
            if (apply.installFonts(allocator, paths, config) != 0) return error.FontsFailed;
        },
        .mkdir => |dir| {
            const rendered = renderField(allocator, dir, vars);
            const resolved = paths.absolutePath(allocator, rendered) catch rendered;
            try fs.ensureDirectoryExists(resolved);
        },
        .download => |dl| {
            const to_expanded = renderField(allocator, dl.to, vars);
            const to_resolved = paths.absolutePath(allocator, to_expanded) catch to_expanded;
            const rendered_url = renderField(allocator, dl.url, vars);
            try process.run(allocator, &.{ "curl", "-fsSL", "-o", to_resolved, rendered_url });
        },
        .clone => |cl| {
            const to_expanded = renderField(allocator, cl.to, vars);
            const to_resolved = paths.absolutePath(allocator, to_expanded) catch to_expanded;
            const rendered_repo = renderField(allocator, cl.repo, vars);
            if (fs.pathExists(to_resolved)) {
                output.info("  skip clone (already exists): {s}", .{to_resolved});
                return;
            }
            try process.run(allocator, &.{ "git", "clone", "--", rendered_repo, to_resolved });
        },
    }
}

fn checkCondition(cond: []const u8, allocator: std.mem.Allocator, env: *const expression.EvalEnv) bool {
    var diagnostics: std.ArrayListUnmanaged(diag.Diagnostic) = .empty;
    defer diagnostics.deinit(allocator);
    const v = expression.evaluateDetailed(allocator, cond, env, &diagnostics, .{ .file_id = 0, .start = 0, .end = 0 }) catch |err| {
        if (diagnostics.items.len > 0) {
            output.err("invalid condition '{s}': {s}", .{ cond, diagnostics.items[0].message });
        } else {
            output.err("invalid condition '{s}': {s}", .{ cond, @errorName(err) });
        }
        return false;
    };
    return v.truthy();
}

fn buildConditionEnv(allocator: std.mem.Allocator) !expression.EvalEnv {
    var env = expression.EvalEnv.init(allocator);
    const os_tag = @import("builtin").os.tag;
    const os_name: []const u8 = if (os_tag == .macos) "darwin" else @tagName(os_tag);
    try env.set("os", .{ .string = os_name });

    var map = std.StringHashMap(expression.Value).init(allocator);
    const env_map = runtime.envMap();
    var it = env_map.iterator();
    while (it.next()) |entry| {
        try map.put(try allocator.dupe(u8, entry.key_ptr.*), .{ .string = try allocator.dupe(u8, entry.value_ptr.*) });
    }
    try env.set("env", .{ .object = map });
    return env;
}

test "parse minimal recipe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const r = try parse(arena.allocator(), "name: test\nsteps:\n  - run: echo hello");
    try std.testing.expectEqualStrings("test", r.name);
    try std.testing.expectEqual(@as(usize, 1), r.steps.len);
    try std.testing.expectEqualStrings("echo hello", r.steps[0].action.run);
}

test "parse recipe step composes another recipe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const r = try parse(arena.allocator(), "name: parent\nsteps:\n  - recipe: child");
    switch (r.steps[0].action) {
        .recipe => |name| try std.testing.expectEqualStrings("child", name),
        else => @panic("expected recipe action"),
    }
}

const test_paths = Environment.Paths{ .tin_dir = "/nonexistent/.tin", .home_dir = "/nonexistent" };
const test_config = Environment.Config{ .doc = null };

test "a failing step fails the recipe instead of ending it quietly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const failing = try parse(a, "name: bad\nsteps:\n  - run: \"true\"\n  - name: breaks\n    run: \"false\"\n  - run: \"true\"");
    try std.testing.expectError(RecipeError.ExecutionFailed, failing.runSteps(a, &.{}, test_paths, test_config));

    const passing = try parse(a, "name: good\nsteps:\n  - run: \"true\"");
    try passing.runSteps(a, &.{}, test_paths, test_config);
}

test "download keeps a destination with spaces as one argument" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const root = try fs.realPathAlloc(a, tmp.parent_dir, &tmp.sub_path);
    const source = try std.fs.path.join(a, &.{ root, "source.txt" });
    const target = try std.fs.path.join(a, &.{ root, "a dir", "copy.txt" });
    try fs.writeFile(source, "payload");
    try fs.ensureDirectoryExists(std.fs.path.dirname(target).?);

    const text = try std.fmt.allocPrint(a, "name: dl\nsteps:\n  - download: file://{s}\n    to: \"{s}\"", .{ source, target });
    const r = try parse(a, text);
    try r.runSteps(a, &.{}, test_paths, test_config);

    const copied = try fs.readFileAlloc(a, target);
    try std.testing.expectEqualStrings("payload", copied);
}
