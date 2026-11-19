# Sn client

The one layer the UI talks to. Transcript, composer, asks, picker and the shell
reach sessions, agents and their state only through `harness.client`; the
architecture spec fails if they require the session layer, agents, servers,
permissions or edits directly.

Today the client has one backend: the Lua harness in this tree. Milestone 2 adds
a second, the Sn engine process speaking msgpack-RPC, behind the same API. The UI
does not change when the backend does.

## API

| Area | Functions |
|---|---|
| Sessions | `dir()`, `start(opts)`, `load(opts)`, `fork(session, message_id)`, `list(dir, agent)`, `delete(opts)`, `close(key)`, `send(session, text, context, opts)`, `session(key)`, `sessions(dir)` |
| Events | `on(names, callback)`, `events()`, `notify(session, update)` |
| Agents | `agent(name)`, `agents()` |
| Following | `follow(session, opts)`, `unfollow(session)`, `following(session)` |
| Permissions | `describe_permission(request)`, `permission_choices(request)`, `rules_supported(agent)`, `rules(agent, dir)`, `remove_rule(rule)` |
| History | `edit_log(lines_of)`, `edit_tools(history, from, to)`, `turns(history, index)`, `active_subagent_states()` |

Async calls return a `harness.async` future, as the hub does.

## Thread contract

A session handed to the UI is a thread: the client-side state of one
conversation, in the sense of Zed's `AcpThread`. The UI reads these and nothing
else, so a remote backend must rebuild exactly these from the event stream.

| Kind | Members |
|---|---|
| Identity | `key`, `id`, `title`, `dir`, `agent`, `parent`, `depth`, `external` |
| History | `history` (event list), `times` (one timestamp per event), `log.turns` (turn index) |
| State | `state`, `queue`, `children`, `subagents`, `permissions`, `commands`, `edits`, `auto_edits` |
| Queries | `running()`, `waiting()`, `loading()`, `idle()`, `queued()`, `can(capability)`, `mode()`, `choice(key)`, `option(key)` |
| Actions | `cancel()`, `cycle_mode()`, `set_option(key, value)`, `subscribe(callback)` |
