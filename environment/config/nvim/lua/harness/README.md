# harness

Neovim hosts ACP agents and gives each one the running editor as an MCP server. Neovim controls everything: every agent process, every session, every tool. Sessions belong to a directory.

tin defines the agents, and Neovim runs them. The default agent is Claude, through `claude-agent-acp` (installed by the `claude-code-acp` recipe); `exports.nvim.default` in tinrc.yml changes it. It runs on the Claude subscription, so no API key is involved, and the user's Claude Code settings, skills and CLAUDE.md all apply. opencode is built in too (`opencode acp`, `:HarnessNew opencode`); it uses whatever models and logins opencode itself is set up with.

```
tin                                       Neovim
artifacts/agents/*.yml ── export ──► agents.json ──► harness.agent
artifacts/rules/nvim/*.yml (system prompts)              │
                                                         ▼
:Harness ──► cli.router ──► hub ──► Workspace(dir) ──► Connection(agent process) ══ ACP ══► agent
                             │           └─ Session* (history of events) ──► session_store ──► TranscriptView
                             ▼
               nvim_mcp/run.lua (child nvim) ◄══ MCP stdio ══ agent
                     │ RPC socket
                     ▼
               this editor: nvim_mcp.tools (toolsets) runs the tools
```

## Layers

Bottom up. A layer only requires layers below it, and no harness module calls Neovim directly: every `vim.api`, `vim.fn`, `vim.cmd`, timer and notification goes through `lua/core` (`Buffer`, `Window`, `event`, `Timer`, `FileWatch`, `console`, `keymap`, `fs`, `register`, ...) or `lua/ui`. `architecture_spec.lua` enforces both: it ranks every module and fails on an upward require or a raw Neovim call.

| Rank | Layer | Module | What it is |
| --- | --- | --- | --- |
| 1 | protocol | `servers/acp/jsonrpc.lua`, `servers/acp/transport.lua`, `servers/acp/connection.lua` | A **Connection** is one agent process serving many sessions. It routes updates and requests by `sessionId`. It covers new, load, list, prompt, cancel and close, and nothing else: no UI and no policy. |
| 1 | settings | `settings/*.lua` | Every tunable as a `core.Config`, read at use time (see Settings). |
| 1 | vgit | `vgit.lua` | The only module that talks to vgit, the diff engine: `patch` and `patch_text` (from `vgit.api`), `show` (vgit's diff views for in-memory content) and `git_diff`. The architecture spec rejects a `vgit` require anywhere else. |
| 2 | events | `events.lua` | Typed events (`message`, `tool_call`, `plan`, `permission`, `stop`, ...) normalized from `session/update`, as dataclasses with a `KIND` enum. Views never parse ACP. |
| 2 | agent | `agent.lua` | **Agent** definitions, loaded from tin's `~/.local/share/tin/nvim/agents.json`, with built-in `claude` and `opencode` as fallbacks. It spawns the process and reads `$NAME` env values at spawn time. |
| 3 | session | `session.lua`, `session/*.lua` | **Session**: one conversation, a coordinator over its parts: `History` (events, times, replay and adoption), `PermissionGate` (open requests, cancel), `PromptQueue` (queue, drain, steer), `SessionConfig` (options, modes, commands) and `Subagents` (child sessions). Its `history` is the source of truth. It provides `subscribe`, `prompt`, `enqueue`, `steer`, `cancel` and `close`. |
| 4 | workspace | `workspace.lua` | **Workspace**: the sessions of one directory. It runs one process per agent, shared by that agent's sessions. `list()` merges live sessions with the agent's stored ones (`session/list`), and `load_session` replays a stored one. |
| 4 | store | `session_store.lua` | Every session in the editor, with lifecycle dispatch that features subscribe to (see Store events). It fires `User HarnessEvent`. |
| 5 | hub | `hub.lua` | Policy: what a session gets (agent, permissions, the editor as the `nvim` MCP server), `max_running` and `max_depth`. |
| 6 | transcript | `transcript/*.lua` | The render pipeline, pure data with no buffers: `BlockBuilder` (history to typed `Block`s), `calculators/` (`Layout`, `FoldCalculator`), `EditResolver` and `EditPatches` (an edit's whole file before and after, laid out by vgit), `EditLog` (the session's completed edits), `SessionChanges`, `Revert` (undoing edits in the files as they are now), `EditLocations` (edits as quickfix entries), `CodeBlocks` (the code blocks of replies), `decorators/` (prompt, tool, diff, thought, plan, note, stop, collapsed and nesting, each returning `MarkSpec`s; titles and replies are drawn by the markdown renderer), `StatusLine`, `PlanSummary`, `theme`, and `TextRenderer` (compact text for agents). |
| 6 | features | `features/*.lua`, `follow.lua` | Behaviour that reacts to the store: reload buffers after an agent's edit (`EditCheckTime`), follow sessions driven elsewhere. |
| 6 | tools | `tools.lua` | The `session` toolset, which lets an agent run sessions (see below). |
| 7 | ui | `ui/*.lua` | `TranscriptView` (one transcript buffer: render loop, timer, keymaps, folds, winbar), `display` (which view shows where, reveal), `document` (applies the pipeline's marks to the buffer), `composer`, `permission_prompt`, `winbar`, `PlanPanel`, `links`, `sessions`, `code_blocks` (motions, text objects, insert, apply), `edits` (vgit views, revert and quickfix of edits), and `transcript`, the facade the rest of the editor calls. |
| 8 | cli | `cli/router.lua`, `cli/commands/*.lua` | One module per `:Harness*` command, with a name, options and `execute(args)`; the router registers them. |

`context.lua` captures where the user is (file, cursor, selection). It is sent ahead of each prompt inside an `<editor-context>` tag, so the agent always sees fresh context. With a range (`:'<,'>Harness …`) the selected lines go along as content: an ACP embedded resource (`file://…#L10-20`) when the agent advertises `embeddedContext`, else a fenced block. Transcripts strip the tag when a session replays.

**Reverting.** `gR` and `:HarnessRevert` undo agent edits in the files as they are now, newest first, by putting each edit's old text back where its new text sits, like `git revert`: changes made since, by you or the agent, are kept, and an edit whose text changed since is skipped and named. The plan opens in vgit, current against reverted, and `<C-y>` applies it: one undo step per buffer, saving buffers that had no unsaved changes of yours and leaving the others modified. From outside a transcript the commands work on the whole session.

**Quickfix.** `gl`, `gL` and `:HarnessQuickfix` put edits in the quickfix list, one entry per changed hunk at its file line, as `+2 −1  · <the turn's prompt>`. Everything Neovim does with quickfix (`:cnext`, `:cdo`, `]q`, quickfix plugins) then works on what the agent changed.

**Forking.** Replies keep their ACP `messageId`. `gF` sends `session/fork` (when the agent advertises `sessionCapabilities.fork`) with the fork point in `_meta.jetbrains.air.fork` (`{ version = 1, messageId }`), the extension the Claude adapter reads to fork at a given message; without a point it forks at the latest message. The fork is then loaded like any stored session, so its history replays into a new transcript titled `<title> (fork)`.

What the agent sends that is not text is shown, not dropped: resource links as links, embedded resources as fenced blocks, images and audio as `⟨image: image/png⟩`, and a tool call that arrives already finished with its output (a JSON `rawOutput` is shown as JSON). The client introduces itself (`clientInfo`), warns when the agent speaks another ACP version, explains a sign-in error with what to do (the agent's `authMethods` descriptions, else its `login` hint, as in `run `claude auth login` in a terminal`; signing in and out happens in the agent's own CLI), checks `loadSession` before loading, and falls back to `session/set_model` (then a warning, not a failed start) when the agent has no model option.

## Architecture

The harness follows vgit's shape: a domain that knows nothing of buffers, stores that dispatch lifecycle events, pure calculators and decorators that return data, one writer that applies it, features as objects, views, a CLI router and settings.

**Where a new thing goes**

| You are adding | Put it in | Notes |
| --- | --- | --- |
| A protocol method or field | `servers/acp/connection.lua`, `events.lua` | Standard ACP first; vendor `_meta` only as an optional extra. |
| Per-session state or behaviour | a part under `session/`, composed by `session.lua` | Parts take the session and stay free of UI. |
| Something that reacts to sessions starting, changing or closing | `features/<Name>.lua`, subscribed with `session_store.on` | `register_events()` and `cleanup()`, like `EditCheckTime`. |
| A new look for a kind of block | `transcript/decorators/<kind>.lua` | `(block, ctx) -> MarkSpec[]`; register it in `decorators/init.lua`; test it without a buffer. |
| Layout, fold or line-number maths | `transcript/calculators/` | Pure functions over blocks. |
| A new kind of block | `transcript/Block.lua` (`KIND`) and `BlockBuilder.lua` | Then a decorator. |
| Something drawn in a window | `ui/` as a view or an `Element` | Through `core`/`ui` only; `PlanPanel` is a small example. |
| A command | `cli/commands/<name>.lua`, listed in `cli/router.lua` | `{ name, opts, execute }`. |
| A constant someone may want to change | `settings/<feature>.lua` | Read with `settings:get(key)` where it is used, never copied at load. |
| A Neovim call | `lua/core` (or `lua/ui`) first, then use it | The architecture spec rejects raw calls in harness code. |

**Store events.** `session_store.on(names, fn)` returns a disposer. `start` fires when a session is added (child sessions open their transcript in the background from here), `event` for every session update and notice (the composer takes back interrupted messages from `NOTICE.returned`), and `close` when a session is removed (follow mode stops). Each also fires `User HarnessEvent` with the session key and the event kind.

**The render pipeline.** History goes through `BlockBuilder` into blocks; `Layout` places them and finds the first block that changed; the writer (`ui/document.lua`) rewrites lines only from there and asks each visible block's decorator, and the markdown renderer's `annotate`, for `MarkSpec`s, which it applies through `core.Buffer`. Nothing in `transcript/` touches a buffer, so every look is tested as data.

**Keeping it fast.** `make bench` replays a long session under the real config, opens it and streams a thought and a reply, timing each step and where it goes. What keeps a frame short:

- A view renders at most once a frame (`frame_ms`), however many updates arrive.
- A growing reply or thought redraws from its *settled* line, the last top-level block after a blank line outside a code fence and not a table (`Layout.settled`). A reply's text above that line keeps its marks. A thought is one quote, so the rows above are parsed only as context, and the marks reaching into the redrawn rows are replaced.
- A thought folded away in every window draws only its callout line. The rest waits until the fold opens.
- A diff is laid out without syntax. Its syntax colours are computed with a string parser the first time the diff is drawn (`Edit:syntax()`), because vgit's own syntax pass sets up a scratch buffer per patch.
- The transport splits agent output into lines without copying what is left of the buffer.
- A large rewrite, such as a new turn pushing the oldest live turn out of `live_turns`, is applied as line hunks (`Document.edits`, past `Document.SPLICE_LINES`), so unchanged lines keep their marks and folds instead of being replaced.
- A stored session opens before its history arrives: the transcript shows at once and fills in as the agent replays. Prompts sent meanwhile wait in the queue, and edits are resolved again once the replay is complete.

**Settings.** `setup(opts)` merges per-feature tables into `settings/*` and passes the rest to the hub's policy:

```lua
require('harness').setup({
  max_running = 4,                                      -- hub policy: agent, auto_allow, max_depth, ask
  transcript = {
    live_turns = 50, tick_ms = 100, frame_ms = 16, anchor_prompt = true, margin_screens = 2, preview_lines = 5, output_max = 200, argument_max = 120,
    queue_preview = 120, request_preview = 80, diff_context = 3, diff_preview_lines = 12,
  },
  sessions = { confirm_ms = 3000 },
  composer = { height = 6 },
  follow = { debounce_ms = 300, grace_ms = 1500, poll_ms = 3000 },
  keymaps = { transcript = { yank = 'gy', plan = 'gp', diff = 'gd' }, composer = { steer = '<C-s>', detach = '<C-x>' } },
  theme = { prompt_icon = '>', spinner = { '◐', '◓', '◑', '◒' }, highlights = { UiToolOutput = { bg = '#1e2228' } } },
})
```

## Sessions are buffers, scoped to a directory

A session is a buffer: `harness://h3 <title>`, listed like any other buffer. Sessions belong to the directory of the tab they start in (`getcwd(-1, 0)`), so `:tcd` gives a tab its own set.

- **Like any buffer.** Opening a session shows its buffer full screen in the current window. Split it, move it with `<C-w>L`, cycle with `:bn`, or jump back to your code with `<C-^>`.
- **Closing doesn't end a session.** Leaving the buffer or `:bd`-ing it leaves the session running. Bring it back from the selector, and it re-renders from its history.
- **The selector** (`<leader>.`, or `:HarnessSessions`) is a dropdown like vgit's log, listing the directory's sessions. It starts with `+ New session`, then live sessions (`◆` running, `○` idle, stored ones with how long ago they were used), then the ones Claude Code has stored for the directory.
  - A footer along its bottom border names its keys, as on every picker.
  - `<CR>` opens the selected session, loading and replaying a stored one (its transcript opens at once and fills in), or starts a new one.
  - `<C-x>` deletes the selected session. Press it twice: deleting removes the stored transcript for good, including from `claude --resume`.
  - Agents can drive the selector with `ui_command`, but deleting is left to people.
- **New sessions.** `<leader>an` or `:HarnessNew` starts a new session, which is simply a new buffer.
- **Prompting.** `:Harness <prompt>` asks the session you're in, or the one you were in last, and opens it in the current window. The editor tools keep acting on the buffer you came from, even while the session buffer covers it.

## Sub-agents

The client declares `subagents` (the ACP sub-agent RFD). When an agent reports a child session (`subagent_update`), the parent follows it: the child's updates, and its permission requests, come through the parent session, filed under the tool call that started the child (from its `session_message` id, or the child's `parentToolUseId`). Agents that only tag work with `_meta.<vendor>.parentToolUseId` nest the same way.

In the transcript the child's tools and report sit under its Agent/Task call behind a `│` gutter, folded as one (`zo` opens it, its own folds sit one level deeper), and the call counts the tools the child ran.

## Modes, options and commands

Agents describe their settings as ACP config options (`configOptions`: mode, model, effort, …), or only as session `modes`. Both are kept on the session, not in the history, and follow `config_option_update` and `current_mode_update`.

- The winbar shows the current mode (`[Plan]`) and model.
- `<S-Tab>` cycles the mode; `gm` picks the model. They are set with `session/set_config_option`, or `session/set_mode` for agents that only have modes. A mode is real: in Accept edits Claude edits without asking.
- The agent's slash commands (`available_commands_update`) complete in the composer when `/` starts the message (or `<C-x><C-o>`), with their argument hint and description. They are sent as ordinary prompt text.

## Queue, steer and interrupt

- **Queue.** Sending while the agent works queues the message; queued messages show under the transcript (`· queued …`) and are sent one by one as turns end. Works with any agent.
- **Steer.** `<C-s>` in the composer injects the message into the running turn when the agent advertises steering (`initialize` `_meta.steering.supported`, `_session/steering`); otherwise it queues. It shows in the turn it steered with a muted `steered` after it, and the turn keeps its clock. Claude takes it within a second, moving a running command to the background. If the turn ended first, the message goes as a normal prompt.
- **Interrupt.** `<C-c>` in the transcript or the composer sends `session/cancel`, answers every open permission request with `cancelled` and closes its prompt, and moves queued messages back into the composer.

## The composer

You write to a session in the composer, much like a commit message window.

- **Opening.** Press `i`, `a`, `o`, `I`, `A` or `O` in a session's buffer, which is read-only. The composer opens as a split along the bottom of the editor, like a commit message window, so it never covers the conversation. It's a normal window: move it with `<C-w>K`, `<C-w>L` and the rest, or resize it. Its winbar names the session it writes to and lists its keys.
- **No file behind it.** It's a buffer with `buftype=acwrite`, so it edits like any buffer, and "writing" it means sending it.
  - `<CR>` in normal mode, or `:w`, sends to the session, then clears and closes the composer. In insert mode, `<CR>` is just a newline.
  - `q` in normal mode, `:q`, or closing its window any other way closes it. Leaving it doesn't; it stays open like any window. The draft is kept per session for next time.
- **Only one.** Opening it again focuses the open one, and opening it from another session's buffer moves it there.
- **Context.** Each message says where you were, from the buffer the session was opened from.
- **Reading the reply.** Sending puts your prompt at the top of the transcript's windows, and the reply fills the screen below it without moving it, as in Claude's apps. Past the bottom the view stays put; `G` follows the end again until the next prompt. A session opened from the picker lands at the end. `anchor_prompt = false` keeps the old behaviour of following the last line.
- **Selections.** While the composer is open, select lines in any file and press `<leader>aa` (visual mode) to attach them. Each shows in the winbar as `+ path:from-to`, and they go with the next message, as embedded resources when the agent takes them and fenced code otherwise. The sent prompt lists them under its text (`+ math.lua:3-5`). `<C-x>` in normal mode drops the last one; sending, or closing with the draft discarded, clears them. With no composer open the key does nothing and the selection stays.

It belongs to the session, not to the session's buffer:

| When | The composer |
| --- | --- |
| The session's buffer is closed | Stays open. Sending shows the buffer again, with the reply streaming in: in the window you came from, or in a new window above if that one closed too. |
| You leave it | Stays open, keeping its text. |
| You `q` it, `:q` it or close its window | Closes and keeps the draft, which is saved as you type. Nothing complains about unsaved changes. |
| You `:wq` it | Sends and closes only the composer, never the window under it. |
| The session is deleted | Closes and drops the draft. |
| The session ended | Stays open with your text, and says why it couldn't send. While the agent is still replying, sending queues instead. |


## Tools

Editor tools (`nvim_mcp/tools/`) take a `path` or `bufnr`; omitting both means the focused buffer. Lines are 1-based and inclusive, which matches Claude's own Read and Edit.

| Tier | Tools | Approval |
| --- | --- | --- |
| read | `editor_state`, `buffer_read`, `diagnostics`, `lsp_*`, `treesitter_node`, `fs_find`, `search`, `ui_surfaces`, `ui_read`, `ui_screen`, `git_status`, `git_log`, `git_diff`, `git_blame`, `session_list`, `session_read` | none |
| write | `buffer_edit`, `buffer_write`, `buffer_save`, `open` (always a new tab), `cursor_set`, `ui_show`, `ui_pick`, `ui_command`, `git_view`, `git_stage`, `session_cancel`, `session_close` | none. Edits are one undo step each and stay unsaved. |
| exec | `lua`, `ex`, `ui_keys`, `session_new`, `session_prompt` | allowed when the agent's policy has `auto_allow` (Claude's does). Otherwise you are asked, with "allow always" for the session. |
| always asked | `git_discard`, `git_run` | asked every time, whatever the policy: they throw work away or change the repository |

**Toolsets.** Tools come in toolsets, one module per domain (`editor`, `buffer`, `lsp`, `exec`), plus the harness's `session` toolset. Anything in the editor can add a toolset:

```lua
require('nvim_mcp.tools').register('git', {
  { name = 'git_blame', risk = 'read', summary = '...', params = { ... }, fn = function(args, ctx) ... end },
})
```

The MCP server reads the editor's tool definitions when it connects, so a new toolset needs no server change. A toolset reaches the sessions that start after it is registered. `ctx.caller` names the session that is calling: each session's MCP server carries `HARNESS_SESSION`.

**The raw API** sits underneath the editor tools. Every `nvim_*` RPC function from `api_info()` is listed under its own name and with its real parameter names, at every tier. Unknown argument names are rejected, never defaulted.

**Sessions that start sessions.** `session_new` starts a child session in the caller's directory, optionally with a first prompt.
- The child runs in the background, with its transcript in a tab of its own.
- The tool returns the child's key at once. The caller follows the child with `session_read` (pass `since` to read only what is new) and sends follow-ups with `session_prompt`.
- No tool blocks on a turn, because tools run on the editor's main loop and the child's own tools need that loop.
- Limits: `max_depth` (default 2) caps nesting, and `max_running` (default 4) caps turns running at once.

**The editor's UI, for agents** (`lua/surfaces/`, `lua/sources/`, `nvim_mcp/tools/ui.lua`). People and agents use the same surfaces: a picker, a list of locations, a markdown panel. Each surface has a model with two renderings, a ui/ component for people and a compact `snapshot` for agents.
- *Fast route first.* `search` returns compact results at once from the same sources the pickers use: files, grep, lsp, diagnostics, buffers. Showing is optional: with `show = true` the search also plays out in a picker the user can watch and take over.
- *Surfaces are state machines that commands drive.* A picker goes `loading -> ready -> chosen` through `query`, `move` and `select`; a list takes `cursor`, `open` and `add`; a panel takes `write`. `ui_command` runs one step, the same step a person takes with keys, and returns what the surface shows. `ui_read` reads it, and `ui_pick` lets the user choose while the agent reads the choice later.
- *Any UI.* `ui_screen` returns what the user sees: every window, its visible lines and the cursor. `ui_keys` types into anything, such as vgit's views.
- *Git through vgit.* `git_view` opens vgit's UI and returns once vgit has finished, using `require('vgit').run` when vgit has it, else `:VGit`. The reads come straight from git, as compact text. `git_stage` and `git_discard` apply exactly the hunk at a line with `git apply`.
- *Tokens.* Every result goes through `lua/compact.lua`, which applies rtk's techniques: grouping by file, relative paths, joined duplicates, budgets with `… N more (offset=K)`. `:HarnessStats` shows each session's context use and what compact output saved against plain JSON.
- People get the same pickers from the keymaps (`<C-p>`, `<leader>/`, `<leader>l*`, `<leader>b`) and `vim.ui.select`.

**Scripts.** `lua` is code mode: the agent writes one multi-line script instead of making many small calls.
- Errors come back with a traceback into the script.
- Globals persist between scripts in a scratch environment, not in `_G`.
- A runaway script stops at `timeout_ms` (default 10000).
- Callbacks a script registers are disabled on their first error. You get one notification, and the agent sees the error with its next script.
- `:HarnessClear` removes everything that scripts created.

**Focus.** The tools act on the buffer you ran `:Harness` from (`tools.set_focus`), not on the session buffer. When no window shows that buffer any more, they use its last cursor position.

## Agents come from tin

```yaml
# ~/.config/tin/artifacts/agents/claude.yml
description: Claude Code over ACP, on the Claude subscription
command: claude-agent-acp
recipe: claude-code-acp
include: [nvim/editor, nvim/present]
system: |
  {{ nvim/editor }}
  {{ nvim/present }}
policy:
  auto_allow: true
```

```yaml
# ~/.config/tin/tinrc.yml
exports:
  nvim:
    agents: ~/.local/share/tin/nvim/agents.json
    default: opencode   # the agent :HarnessSessions, :Harness, <leader>. use by default
```

`tin artifact validate` checks an agent's rule and MCP references. `tin artifact export nvim` writes the JSON, composing each system prompt from its rules.
- An agent's `mcp:` lists `artifacts/mcp/` servers to give every session, alongside the editor.
- Secrets are written as `$NAME` and read by Neovim when the agent starts.
- `default` names the agent the harness uses when a session starts without one. It may name a built-in (`claude`, `opencode`) even when that agent is not in the exported list; without it, the harness falls back to `claude`.

Add another ACP agent (Gemini, Codex, ...) as another YAML file, then open a session with `:HarnessNew <agent>`.

## Usage

```vim
:Harness what is wrong with this function?
:'<,'>Harness explain these lines
:Harness now fix it          " asks the session in the session window again
:HarnessNew [agent]          " a new session (a new buffer); also <leader>an
:HarnessSessions             " the session selector: new, open, delete; also <leader>. and <leader>aa
:HarnessCancel
:HarnessClear                " remove what agents' scripts left behind
:HarnessStats                " tokens per session, and what compact output saved
:HarnessChanges              " every file the session changed, in vgit; also gC
:HarnessFork                 " fork the session from the reply under the cursor; also gF
:HarnessRevert [scope]       " revert an edit, a turn or the session after a vgit preview; also gR
:HarnessQuickfix [scope]     " an edit's, a turn's or the session's edits in quickfix; also gl / gL
```

```lua
local harness = require('harness')
harness.setup({ max_running = 4, max_depth = 2 })   -- also: agent, auto_allow, ask, and the settings tables above

local session = harness.start():wait()                -- in the current tab's directory
session:subscribe(function(event) print(event.kind) end)
local result = harness.hub.prompt(session, 'what is in this buffer?'):wait()   -- { stop_reason, text, permissions }
```

## Transcripts

A transcript is plain markdown with the `harness` filetype, drawn entirely by our own renderer: render-markdown.nvim keeps drawing normal `.md` files, and no treesitter highlighter is attached to the buffer. The text is the permanent record: yank it, search it, `:w` it. Anything that changes over time is an extmark.

It works for any ACP agent. It reads only standard ACP fields (`kind`, `title`, `rawInput`, `locations`, `content`, `rawOutput`, diffs, plans, thoughts, usage, stop reasons). A tool name under any agent's `_meta` (`_meta.<vendor>.toolName`) is used when present, and otherwise the label comes from the title.

- **Blocks.** `transcript/BlockBuilder.lua` turns history into typed blocks: title, collapsed, prompt, message, thought, tool, diff, plan, note, stop. Turns before the last can't change, so their blocks are built once and cached.
- **Earlier turns wait.** Turns older than `transcript.live_turns` (50) show as one line, `⋯ 120 earlier turns · <CR> to show`, and are not built until you ask, so opening a session costs about the same at 40 turns as at 1000 (around 20 ms).
- **Incremental writes.** `ui/document.lua` lays out and writes only from the first block that changed, comparing cached blocks by identity. A streamed chunk costs well under a millisecond whatever the length of the session.
- **Lazy drawing.** Extmarks are drawn only for blocks in or near a window (two screens either side), starting where the window lands. A decoration provider draws the rest as they scroll into view.
- **Markdown.** `lua/ui/markdown/Renderer.lua` annotates text into `MarkSpec`s with a treesitter string parser (markdown, inline markdown and code-fence languages), applying the same highlight and conceal captures the built-in highlighter would, then applies them. Only blocks being drawn are parsed, and a block still streaming redraws only from its settled line (see Keeping it fast). The renderer compiles its own copy of each highlights query, because the cached query is shared and plugins change it (render-markdown disables the fence `conceal_lines` patterns for its own drawing). On top (`ui/markdown/nodes.lua`) it draws heading icons and bars, shaded code blocks with a language label, bullets by depth, checkboxes, quote bars, callouts (`> [!NOTE]`, `> [!thought]`), rules, links, and pipe tables as a box aligned by display width. The cursor line shows the raw text.
- **A ledger, not a chat.** There are no speaker headers: your prompt is the bold text after `❯`, and everything under it is the agent. Tools line up as a status icon, a lowercase verb and their argument, with the result aligned right when the window has room (else at the end of the line). Runs of tools and their diffs sit on consecutive lines; a sub-agent's work hangs off a `├ │ └` tree whose prose keeps the rail on wrapped lines (a very long tool line still wraps to the left edge; arguments are capped at `argument_max`); each turn ends on a rule carrying its time and tool count.
- **Surfaces.** Code blocks, tool output and diff lines get backgrounds blended from the colour scheme's own `Normal`, `Comment` and `Added`/`Removed` colours, recomputed on `ColorScheme`, so any scheme gets a coherent palette. `theme.highlights` overrides any group.

In a transcript:

| You see | Where it comes from |
| --- | --- |
| `❯ fix the parser` in bold, wrapped lines indented under the text | each prompt |
| `✓ bash    seq 1 20` with a spinner while it runs, then `✓` or `✗` | the tool call: a lowercase verb and its main argument (command, path, pattern, url) |
| `1 line`, `12 results` at the right edge | the result of reads and searches |
| Output under a `│` rail, the first 5 lines shown and the rest folded | commands, searches and fetches; failures show their error. Output is shown verbatim: its fence is longer than any backtick run in it |
| `✓ edit    a.lua   +2 −2`, then the change under a `│` rail as vgit lays it out: three lines of context, file line numbers, add and delete backgrounds, changed words marked on top of the file's own syntax colours | edits. ACP sends a snippet; `EditResolver` finds it in the file to rebuild the whole file before and after (from the old text while the edit waits for permission), and `vgit.api.patch` lays that out. An edit it can't find, or one that failed, shows just its snippet with no numbers. A finished edit is frozen, so later changes to the file don't move it. A session opened later finds its edits newest first, each in the file as the edits after it left it, and an edit the agent replays without a diff is rebuilt from its input (`oldString`/`newString` or `old_string`/`new_string`). Past 12 rows the rest of a diff is folded. Agents reading the session get the same change as a classic `+`/`-` diff. A diff shown away from its edit keeps a path line |
| `[!thought]` callout with how long it took, folded | thoughts |
| `⠋ agent   List files   2 tools` while it runs, then `✓ agent   List files   6s · 2 tools`, with the sub-agent's tools (`├`) and report (`│`) on a tree closed by `└`, folded as one | sub-agents (Agent/Task calls), from the block's own status and times. Folded, the tree shows what it holds on its rail (`│ ⋯ 2 tools · 1 reply`). Their prose is indented two spaces so wrapped lines keep the rail |
| `✓ read 3 files, searched 1 pattern` over `└ ⋯ 3 tools` | a run of two or more finished reads and searches in a turn; live and failed tools never group, and agents reading the session still see each tool |
| `⋯ 120 earlier turns · <CR> to show` | turns older than `live_turns` |
| `plan` over `✓ read`, `◆ edit`, `○ test` | the turn's latest ACP plan |
| `✗ edit    a.lua   refused` (or `cancelled` when you interrupted) | a permission you refused, on its tool |
| `✗ bash    sleep 20   interrupted` | a tool the turn ended without finishing |
| `✗ error: not logged in` | errors, and failures or refusals with no tool to put them on |
| A box-drawn table | pipe tables in a reply |
| The current turn's prompt in the winbar (`❯ fix the parser`) | once that prompt scrolls out of view |
| A floating `Plan  2/5` checklist at the top right | the latest ACP plan while any entry is unfinished |
| `──────── 12s · 3 tools ──` | the end of each turn; `interrupted` or the limit hit is named in the warning colour, and `failed` (a turn the agent could not run) in the error colour |
| `⠋ working · 12s · <C-c> interrupt` under the last line | a running turn |
| `◆ waiting for you: Edit a.lua` on the tool and the working line, and a notification when the transcript is out of sight | a permission request waiting for an answer |
| `◆ running  [Plan]  ctx 3%  $0.07` in the winbar | the session's state and its latest usage |

Keys in a transcript:

| Key | Does |
| --- | --- |
| `<CR>` | on a link or a file named in inline code (`lua/a.lua:42`): open it in a new tab. On a diff line: open the file at that line. On a tool: open what it touched. On a fold: open or close it. On a tool group: show or hide its tools. On the earlier-turns line: show them |
| `gd` | open the edit under the cursor (its diff or its tool line) in vgit's diff view, as the whole file before and after |
| `gD` | open the git diff of the file under the cursor (a diff, a tool's file, a link): `:VGit diff -- <path>` |
| `gF` | fork the session from the reply under the cursor (on a prompt, from the reply before it, so you can ask differently). The fork opens with the conversation up to that reply; the original is untouched. Needs an agent with `session/fork` |
| `gC` | open every file this session changed in vgit, each from before the session's first edit to it to now (also `:HarnessChanges`) |
| `gp` | show or hide the plan panel |
| `gf` | open what is under the cursor in a new tab |
| `]b`, `[b` | the next or previous code block of a reply (with a count, and in visual mode) |
| `ib`, `ab` | text objects: inside a code block, or the block with its fences (`yib`, `vab`, `"+yib`) |
| `gi` | insert the code block under the cursor below the cursor in the code buffer you came from, as one undo step |
| `ga` | ask the agent to apply the code block under the cursor to the code buffer you came from, merging it with what is there; the block goes along as content, and the result is an edit like any other (`gd`, `gR`) |
| `gR` | revert the edit under the cursor, or anywhere else this turn's edits, after a preview in vgit (`<C-y>` there applies it) |
| `gl`, `gL` | this turn's, or the whole session's, edits in the quickfix list, one entry per changed hunk |
| `gy` | yank the code block under the cursor without its fences, or else the whole block (a prompt without its `>`); on an edit, its change as a patch |
| `za`, `zR`, `zM` | folds, as anywhere |
| `]]`, `[[` | next and previous turn |
| `<C-c>` | interrupt the running turn |
| `1` `2` `3` | while the agent asks permission: allow once, allow always (this session), reject. Otherwise they are counts |
| `<S-Tab>` | next session mode (also in the composer) |
| `gm` | pick the session model |
| `i`, `a`, `o`, `I`, `A`, `O` | write to the session |

**Links.** Replies are told to reference code as `[label](nvim://file/<path>#L<line>)`, relative to the session's directory. `nvim://buf/<n>` names a buffer. Links show an icon and open on `<CR>`. A link to a file that no longer exists is greyed out. Inline code that names an existing file is a link too.

`session_read` gives agents the same transcript without tool output, to keep it small.

## Sessions driven elsewhere

A session can be open in Neovim while another program drives it, for example `claude --resume <id>` in another pane. `harness/follow.lua` keeps the transcript in step without a keypress.

- **Signal.** For agents that keep transcripts on disk, the transcript file is watched (re-armed after atomic saves, checked again right after arming). Where it lives comes from the agent's `transcripts` glob (`{id}` is the session id), which defaults to `~/.claude/projects/*/{id}.jsonl` for `claude-agent-acp`. Agents without one are polled through standard `session/list` (`updatedAt`) every few seconds while the transcript is visible; a transcript that appears later is picked up.
- **Content.** On a change the session is reloaded through standard `session/load`, which the agent replays into a separate history. Only what is new is taken: turns after the last one this editor has, and the latest turn when it came from elsewhere and is still being written. Turns this editor ran keep everything only it knows (endings, timings, refusals). A replay that lags behind changes nothing; one that disagrees replaces the history.
- **Own turns.** Writes made while this editor's turn runs, and shortly after, are its own and cause no reload.
- **Shown.** After a change from elsewhere the winbar reads `⇄ external`, and the composer warns that sending forks the session. Messages sent during a reload are queued.
- **Granularity.** Another program writes whole messages and tool results, not tokens, so a turn from elsewhere fills in step by step rather than streaming character by character.

## Files changed by other programs

`lua/features/LiveReload.lua` (on `core/FileWatch`) keeps buffers in sync with edits made outside Neovim, such as Claude Code or any agent in another pane, without a keypress or focus change.

- **Live.** Each loaded file is watched (`vim.uv.new_fs_event`). A change reloads the buffer within about 100 ms, and the changed lines are highlighted for a few seconds. Atomic saves (write a temp file, rename it over) are followed: the watch is re-armed on the path after every event, and the file is checked once right after arming, so a write in the moment the watch starts isn't missed.
- **Only real files.** Buffers with a `buftype` (chat transcripts, the composer, terminals, help, scratch) and unsaved new files are never watched, so a hundred open sessions cost nothing.
- **Nothing left behind.** A watch stops when its buffer is unloaded, deleted, wiped or renamed, and all stop on exit.
- **Bounded.** At most `LiveReload.MAX` (128) files are watched; past that the least recently entered buffer gives up its watch and falls back to the `checktime` on `BufEnter` and `CursorHold`, and gets it back when entered.
- **Unsaved changes win.** A file that changes under a modified buffer is never reloaded. Instead of Neovim's blocking prompt you get one notification, and `:DiffDisk` opens your version against the disk in a new tab. A file deleted on disk keeps its text in the buffer.

## Permissions

`harness/permissions.lua` sets these rules:
- Read and write tools are allowed without asking.
- Exec tools follow the agent's `policy.auto_allow`, which `setup({ auto_allow = ... })` overrides.
- Claude's built-ins that reach the gate are asked in the transcript, and so are exec tools when `auto_allow` is off. The question sits under the transcript (`◆ Allow Edit a.lua?` with the agent's own options, numbered: `1 Yes  2 Yes, allow all edits during this session  3 No`); the numbers answer it there, and the chosen option goes back to the agent as is, so its "always" is remembered by the agent. An agent that sends no options gets `1 Allow once  2 Allow always (this session)  3 Reject`, with "always" remembered by the harness. A session without a transcript gets one in the background, and you are notified when it is out of sight. `setup({ ask = require('harness.permissions').ui_ask })` brings back the popup.
- Anything that would need asking is refused when there is no UI.
- "Allow always" is remembered per session. The adapter is sent `allow_once`, so no lasting rule lands in the user's Claude Code settings.

## Tests

```sh
make test          # all specs
make test-file FILE=lua/harness/session_spec.lua
```

`harness/servers/acp/fake_agent.lua` is a scripted ACP agent for specs. It handles sessions, list and load, and permission requests. Specs sit next to their module (`Layout.lua`, `Layout_spec.lua`) and go bottom up: calculators and decorators are tested as data, views against real buffers, and `architecture_spec.lua` guards the layers.
