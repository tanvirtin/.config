
const std = @import("std");
const yaml = @import("yaml");
const mcp_mod = @import("../mcp.zig");
const Rule = @import("rule.zig");

const Agent = @This();

pub const Error = error{
    MissingDescription,
    MissingCommand,
    UnknownMcpServer,
};

pub const Policy = struct {
    auto_allow: ?bool = null,
};

id: []const u8 = "",
description: []const u8,
command: []const u8,
args: []const []const u8 = &.{},
env: []const mcp_mod.Field = &.{},
model: ?[]const u8 = null,
recipe: ?[]const u8 = null,
system: ?[]const u8 = null,
include: []const []const u8 = &.{},
mcp: []const []const u8 = &.{},
policy: Policy = .{},

pub fn parse(allocator: std.mem.Allocator, val: yaml.Value) !Agent {
    var agent = Agent{
        .description = (try mcp_mod.optStringDup(allocator, val, "description")) orelse return Error.MissingDescription,
        .command = (try mcp_mod.optStringDup(allocator, val, "command")) orelse return Error.MissingCommand,
    };

    agent.args = try mcp_mod.stringSeq(allocator, val, "args");
    if (val.getMapping("env")) |env| agent.env = try mcp_mod.mappingFields(allocator, env);
    agent.model = try mcp_mod.optStringDup(allocator, val, "model");
    agent.recipe = try mcp_mod.optStringDup(allocator, val, "recipe");
    agent.system = try mcp_mod.optStringDup(allocator, val, "system");
    agent.include = try mcp_mod.stringSeq(allocator, val, "include");
    agent.mcp = try mcp_mod.stringSeq(allocator, val, "mcp");

    if (val.getMapping("policy")) |policy| {
        if (mcp_mod.optString(policy, "auto_allow")) |flag| agent.policy.auto_allow = std.mem.eql(u8, flag, "true");
    }

    return agent;
}

pub fn resolveSystem(self: *const Agent, allocator: std.mem.Allocator, rules: []const Rule) ![]const u8 {
    const system = self.system orelse return "";
    return Rule.compose(allocator, system, self.include, rules);
}

fn isSecret(server: mcp_mod.Server, section: []const u8, key: []const u8) bool {
    for (server.secrets) |secret| {
        if (secret.len == section.len + 1 + key.len and
            std.mem.startsWith(u8, secret, section) and
            secret[section.len] == '.' and
            std.mem.eql(u8, secret[section.len + 1 ..], key)) return true;
    }
    return false;
}

fn namedValues(allocator: std.mem.Allocator, server: mcp_mod.Server, section: []const u8, fields: []const mcp_mod.Field) !std.json.Value {
    var array = std.json.Array.init(allocator);
    for (fields) |field| {
        const raw = switch (field.value) {
            .string => |s| s,
            else => continue,
        };
        const value = if (isSecret(server, section, field.key)) try std.fmt.allocPrint(allocator, "${s}", .{raw}) else raw;

        var pair = std.json.ObjectMap.init(allocator);
        try pair.put("name", .{ .string = field.key });
        try pair.put("value", .{ .string = value });
        try array.append(.{ .object = pair });
    }
    return .{ .array = array };
}

fn strings(allocator: std.mem.Allocator, items: []const []const u8) !std.json.Value {
    var array = std.json.Array.init(allocator);
    for (items) |item| try array.append(.{ .string = item });
    return .{ .array = array };
}

fn acpServer(allocator: std.mem.Allocator, server: mcp_mod.Server) !std.json.Value {
    var object = std.json.ObjectMap.init(allocator);
    const name = try allocator.dupe(u8, server.id);
    std.mem.replaceScalar(u8, name, '/', '-');

    switch (server.type) {
        .stdio => {
            try object.put("name", .{ .string = name });
            try object.put("command", .{ .string = server.command.? });
            try object.put("args", try strings(allocator, server.args));
            try object.put("env", try namedValues(allocator, server, "env", server.env));
        },
        .http => {
            try object.put("type", .{ .string = "http" });
            try object.put("name", .{ .string = name });
            try object.put("url", .{ .string = server.url.? });
            try object.put("headers", try namedValues(allocator, server, "headers", server.headers));
        },
    }
    return .{ .object = object };
}

fn findServer(servers: []const mcp_mod.Server, id: []const u8) ?mcp_mod.Server {
    for (servers) |server| {
        if (std.mem.eql(u8, server.id, id)) return server;
    }
    return null;
}

fn lessThan(_: void, a: Agent, b: Agent) bool {
    return std.mem.lessThan(u8, a.id, b.id);
}

pub fn renderExport(
    allocator: std.mem.Allocator,
    agents: []const Agent,
    rules: []const Rule,
    servers: []const mcp_mod.Server,
) ![]const u8 {
    const sorted = try allocator.dupe(Agent, agents);
    std.mem.sort(Agent, sorted, {}, lessThan);

    var by_id = std.json.ObjectMap.init(allocator);
    for (sorted) |agent| {
        var object = std.json.ObjectMap.init(allocator);
        try object.put("description", .{ .string = agent.description });
        try object.put("command", .{ .string = agent.command });
        try object.put("args", try strings(allocator, agent.args));

        var env = std.json.ObjectMap.init(allocator);
        for (agent.env) |field| switch (field.value) {
            .string => |s| try env.put(field.key, .{ .string = s }),
            else => {},
        };
        try object.put("env", .{ .object = env });

        const system = try agent.resolveSystem(allocator, rules);
        if (system.len > 0) try object.put("system", .{ .string = system });

        var mcp_servers = std.json.Array.init(allocator);
        for (agent.mcp) |id| {
            const server = findServer(servers, id) orelse return Error.UnknownMcpServer;
            try mcp_servers.append(try acpServer(allocator, server));
        }
        try object.put("mcp", .{ .array = mcp_servers });

        var policy = std.json.ObjectMap.init(allocator);
        if (agent.policy.auto_allow) |flag| try policy.put("auto_allow", .{ .bool = flag });
        try object.put("policy", .{ .object = policy });

        if (agent.model) |model| try object.put("model", .{ .string = model });
        if (agent.recipe) |recipe| try object.put("recipe", .{ .string = recipe });

        try by_id.put(agent.id, .{ .object = object });
    }

    var root = std.json.ObjectMap.init(allocator);
    try root.put("agents", .{ .object = by_id });

    var out = std.io.Writer.Allocating.init(allocator);
    try std.json.Stringify.value(std.json.Value{ .object = root }, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeAll("\n");
    return out.toOwnedSlice();
}

fn parseText(allocator: std.mem.Allocator, text: []const u8) !Agent {
    const doc = try yaml.parse(allocator, text);
    return parse(allocator, doc.value);
}

test "parse reads every field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const agent = try parseText(arena.allocator(),
        \\description: Claude over ACP
        \\command: claude-agent-acp
        \\args: [--verbose]
        \\env:
        \\  TOKEN: $CLAUDE_TOKEN
        \\model: claude-sonnet-5-5
        \\recipe: claude-code-acp
        \\include: [nvim/editor]
        \\system: "{{ nvim/editor }}"
        \\mcp: [mem0]
        \\policy:
        \\  auto_allow: true
    );
    try std.testing.expectEqualStrings("claude-agent-acp", agent.command);
    try std.testing.expectEqualStrings("--verbose", agent.args[0]);
    try std.testing.expectEqualStrings("TOKEN", agent.env[0].key);
    try std.testing.expectEqualStrings("claude-sonnet-5-5", agent.model.?);
    try std.testing.expectEqualStrings("claude-code-acp", agent.recipe.?);
    try std.testing.expectEqualStrings("mem0", agent.mcp[0]);
    try std.testing.expectEqual(@as(?bool, true), agent.policy.auto_allow);
}

test "parse requires a description and a command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(Error.MissingCommand, parseText(arena.allocator(), "description: x"));
    try std.testing.expectError(Error.MissingDescription, parseText(arena.allocator(), "command: x"));
}

test "renderExport composes the system prompt from rules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const agents = [_]Agent{.{
        .id = "claude",
        .description = "d",
        .command = "claude-agent-acp",
        .system = "Rules:\n{{ nvim/editor }}",
        .include = &.{"nvim/editor"},
        .model = "claude-sonnet-5-5",
        .policy = .{ .auto_allow = true },
    }};
    const rules = [_]Rule{.{ .id = "nvim/editor", .description = "r", .content = "use the editor" }};

    const json = try renderExport(a, &agents, &rules, &.{});
    const parsed = try std.json.parseFromSlice(std.json.Value, a, json, .{});
    const claude = parsed.value.object.get("agents").?.object.get("claude").?.object;

    try std.testing.expectEqualStrings("Rules:\nuse the editor", claude.get("system").?.string);
    try std.testing.expectEqualStrings("claude-agent-acp", claude.get("command").?.string);
    try std.testing.expect(claude.get("policy").?.object.get("auto_allow").?.bool);
    try std.testing.expectEqualStrings("claude-sonnet-5-5", claude.get("model").?.string);
}

test "renderExport hands MCP servers over in ACP shape, secrets as variable names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const servers = [_]mcp_mod.Server{
        .{
            .id = "tools/search",
            .type = .stdio,
            .command = "search-mcp",
            .env = &.{
                .{ .key = "API_KEY", .value = .{ .string = "SEARCH_API_KEY" } },
                .{ .key = "MODE", .value = .{ .string = "fast" } },
            },
            .secrets = &.{"env.API_KEY"},
        },
        .{
            .id = "mem0",
            .type = .http,
            .url = "https://mcp.mem0.ai/mcp",
            .headers = &.{.{ .key = "Authorization", .value = .{ .string = "MEM0_API_KEY" } }},
            .secrets = &.{"headers.Authorization"},
        },
    };
    const agents = [_]Agent{.{ .id = "claude", .description = "d", .command = "c", .mcp = &.{ "tools/search", "mem0" } }};

    const json = try renderExport(a, &agents, &.{}, &servers);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, json, .{});
    const list = parsed.value.object.get("agents").?.object.get("claude").?.object.get("mcp").?.array.items;

    const stdio = list[0].object;
    try std.testing.expectEqualStrings("tools-search", stdio.get("name").?.string);
    const env = stdio.get("env").?.array.items;
    try std.testing.expectEqualStrings("$SEARCH_API_KEY", env[0].object.get("value").?.string);
    try std.testing.expectEqualStrings("fast", env[1].object.get("value").?.string);

    const http = list[1].object;
    try std.testing.expectEqualStrings("http", http.get("type").?.string);
    try std.testing.expectEqualStrings("$MEM0_API_KEY", http.get("headers").?.array.items[0].object.get("value").?.string);
}

test "renderExport refuses an unknown MCP server and orders agents by id" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const missing = [_]Agent{.{ .id = "x", .description = "d", .command = "c", .mcp = &.{"nope"} }};
    try std.testing.expectError(Error.UnknownMcpServer, renderExport(a, &missing, &.{}, &.{}));

    const two = [_]Agent{
        .{ .id = "zed", .description = "d", .command = "c" },
        .{ .id = "claude", .description = "d", .command = "c" },
    };
    const json = try renderExport(a, &two, &.{}, &.{});
    try std.testing.expect(std.mem.indexOf(u8, json, "\"claude\"").? < std.mem.indexOf(u8, json, "\"zed\"").?);
    try std.testing.expectEqualStrings(json, try renderExport(a, &two, &.{}, &.{}));
}
