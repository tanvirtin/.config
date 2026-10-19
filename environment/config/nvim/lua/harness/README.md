# harness

Neovim hosts ACP agents and gives each one the running editor as an MCP server. Neovim controls everything: every agent process, every session, every tool. Sessions belong to a directory.

tin defines the agents, and Neovim runs them. The default agent is Claude, through `claude-agent-acp` (installed by the `claude-code-acp` recipe). It runs on the Claude subscription, so no API key is involved, and the user's Claude Code settings, skills and CLAUDE.md all apply.

```
tin                                       Neovim
artifacts/agents/*.yml ── export ──► agents.json ──► harness.agent
artifacts/rules/nvim/*.yml (system prompts)              │
                                                         ▼
:Harness ──► ui.commands ──► hub ──► Workspace(dir) ──► Connection(agent process) ══ ACP ══► agent
                              │            └─ Session* (history of events) ──► ui.transcript
                              ▼
               nvim_mcp/run.lua (child nvim) ◄══ MCP stdio ══ agent
                     │ RPC socket
                     ▼
               this editor: nvim_mcp.tools (toolsets) runs the tools
```

## Layers

Bottom up. A layer only requires layers below it.

| Layer | Module | What it is |
| --- | --- | --- |
| protocol | `acp/jsonrpc.lua`, `acp/transport.lua`, `acp/connection.lua` | A **Connection** is one agent process serving many sessions. It routes updates and requests by `sessionId`. It covers new, load, list, prompt, cancel and close, and nothing else: no UI and no policy. |
| events | `events.lua` | Typed events (`message`, `tool_call`, `plan`, `permission`, `stop`, ...) normalized from `session/update`. Views never parse ACP. |
| agent | `agent.lua` | **Agent** definitions, loaded from tin's `~/.local/share/tin/nvim/agents.json`, with a built-in `claude` as fallback. It spawns the process and reads `$NAME` env values at spawn time. |
| session | `session.lua` | **Session**: one conversation. Its `history` of events is the source of truth. It provides `subscribe`, `prompt`, `cancel` and `close`, and answers permission requests through `approve`. |
| workspace | `workspace.lua` | **Workspace**: the sessions of one directory. It runs one process per agent, shared by that agent's sessions. `list()` merges live sessions with the agent's stored ones (`session/list`), and `load_session` replays a stored one. |
| hub | `hub.lua` | Every session in the editor. It decides what a session gets (agent, policy, the editor as the `nvim` MCP server) and enforces `max_running` and `max_depth`. It fires `User HarnessEvent`. |
| tools | `tools.lua` | The `session` toolset, which lets an agent run sessions (see below). |
| ui | `ui/blocks.lua`, `ui/document.lua`, `ui/transcript.lua`, `ui/commands.lua` | Transcripts built from history as blocks, written incrementally and reopenable at any time, and the user's commands. |

`context.lua` captures where the user is (file, cursor, selection). It is sent ahead of each prompt inside an `<editor-context>` tag, so the agent always sees fresh context. Transcripts strip the tag when a session replays.

## Sessions are buffers, scoped to a directory

A session is a buffer: `harness://h3 <title>`, listed like any other buffer. Sessions belong to the directory of the tab they start in (`getcwd(-1, 0)`), so `:tcd` gives a tab its own set.

- **Like any buffer.** Opening a session shows its buffer full screen in the current window. Split it, move it with `<C-w>L`, cycle with `:bn`, or jump back to your code with `<C-^>`.
- **Closing doesn't end a session.** Leaving the buffer or `:bd`-ing it leaves the session running. Bring it back from the selector, and it re-renders from its history.
- **The selector** (`<leader>.`, or `:HarnessSessions`) is a dropdown like vgit's log, listing the directory's sessions. It starts with `+ New session`, then live sessions (`●` running, `○` open), then the ones Claude Code has stored for the directory.
  - A footer along its bottom border names its keys, as on every picker.
  - `<CR>` opens the selected session, loading and replaying a stored one, or starts a new one.
  - `<C-x>` deletes the selected session. Press it twice: deleting removes the stored transcript for good, including from `claude --resume`.
  - Agents can drive the selector with `ui_command`, but deleting is left to people.
- **New sessions.** `<leader>an` or `:HarnessNew` starts a new session, which is simply a new buffer.
- **Prompting.** `:Harness <prompt>` asks the session you're in, or the one you were in last, and opens it in the current window. The editor tools keep acting on the buffer you came from, even while the session buffer covers it.

## Modes, options and commands

Agents describe their settings as ACP config options (`configOptions`: mode, model, effort, …), or only as session `modes`. Both are kept on the session, not in the history, and follow `config_option_update` and `current_mode_update`.

- The winbar shows the current mode (`󰒓 Plan`) and model.
- `<S-Tab>` cycles the mode; `go` picks any option and value. They are set with `session/set_config_option`, or `session/set_mode` for agents that only have modes. A mode is real: in Accept edits Claude edits without asking.
- The agent's slash commands (`available_commands_update`) complete in the composer when `/` starts the message (or `<C-x><C-o>`), with their argument hint and description. They are sent as ordinary prompt text.

## Queue, steer and interrupt

- **Queue.** Sending while the agent works queues the message; queued messages show under the transcript (`󰔟 queued …`) and are sent one by one as turns end. Works with any agent.
- **Steer.** `<C-s>` in the composer injects the message into the running turn when the agent advertises steering (`initialize` `_meta.steering.supported`, `_session/steering`); otherwise it queues.
- **Interrupt.** `<C-c>` in the transcript or the composer sends `session/cancel`, answers every open permission request with `cancelled` and closes its prompt, and moves queued messages back into the composer.

## The composer

You write to a session in the composer, much like a commit message window.

- **Opening.** Press `i`, `a`, `o`, `I`, `A` or `O` in a session's buffer, which is read-only. The composer opens as a split along the bottom of the editor, like a commit message window, so it never covers the conversation. It's a normal window: move it with `<C-w>K`, `<C-w>L` and the rest, or resize it. Its winbar names the session it writes to and lists its keys.
- **No file behind it.** It's a buffer with `buftype=acwrite`, so it edits like any buffer, and "writing" it means sending it.
  - `<CR>` in normal mode, or `:w`, sends to the session, then clears and closes the composer. In insert mode, `<CR>` is just a newline.
  - `q` in normal mode, `:q`, or closing its window any other way closes it. Leaving it doesn't; it stays open like any window. The draft is kept per session for next time.
- **Only one.** Opening it again focuses the open one, and opening it from another session's buffer moves it there.
- **Context.** Each message says where you were, from the buffer the session was opened from.

It belongs to the session, not to the session's buffer:

| When | The composer |
| --- | --- |
| The session's buffer is closed | Stays open. Sending shows the buffer again, with the reply streaming in: in the window you came from, or in a new window above if that one closed too. |
| You leave it | Stays open, keeping its text. |
| You `q` it, `:q` it or close its window | Closes and keeps the draft, which is saved as you type. Nothing complains about unsaved changes. |
| You `:wq` it | Sends and closes only the composer, never the window under it. |
| The session is deleted | Closes and drops the draft. |
| The session ended, or is still replying | Stays open with your text, and says why it couldn't send. |


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
- *Git through vgit.* `git_view` opens vgit's UI and returns once vgit has finished, using `require('vgit').run`, which returns the command's task. The reads come straight from git, as compact text. `git_stage` and `git_discard` apply exactly the hunk at a line with `git apply`.
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
```

`tin artifact validate` checks an agent's rule and MCP references. `tin artifact export nvim` writes the JSON, composing each system prompt from its rules.
- An agent's `mcp:` lists `artifacts/mcp/` servers to give every session, alongside the editor.
- Secrets are written as `$NAME` and read by Neovim when the agent starts.

Add another ACP agent (Gemini, Codex, ...) as another YAML file, then open a session with `:HarnessNew <agent>`.

## Usage

```vim
:Harness what is wrong with this function?
:'<,'>Harness explain these lines
:Harness now fix it          " asks the session in the session window again
:HarnessNew [agent]          " a new session (a new buffer); also <leader>an
:HarnessSessions             " the session selector: new, open, delete; also <leader>.
:HarnessCancel
:HarnessClear                " remove what agents' scripts left behind
:HarnessStats                " tokens per session, and what compact output saved
```

```lua
local harness = require('harness')
harness.setup({ max_running = 4, max_depth = 2 })   -- also: agent, auto_allow, ask

local session = harness.start():wait()                -- in the current tab's directory
session:subscribe(function(event) print(event.kind) end)
local result = harness.hub.prompt(session, 'what is in this buffer?'):wait()   -- { stop_reason, text, permissions }
```

## Transcripts

A transcript is plain markdown with the `harness` filetype, drawn entirely by our own renderer: render-markdown.nvim keeps drawing normal `.md` files, and no treesitter highlighter is attached to the buffer. The text is the permanent record: yank it, search it, `:w` it. Anything that changes over time is an extmark.

It works for any ACP agent. It reads only standard ACP fields (`kind`, `title`, `rawInput`, `locations`, `content`, `rawOutput`, diffs, plans, thoughts, usage, stop reasons). A tool name under any agent's `_meta` (`_meta.<vendor>.toolName`) is used when present, and otherwise the label comes from the title.

- **Blocks.** `ui/blocks.lua` turns history into typed blocks: title, prompt, message, thought, tool, diff, plan, note, stop. Turns before the last can't change, so their blocks are built once and cached.
- **Incremental writes.** `ui/document.lua` lays out and writes only from the first block that changed, comparing cached blocks by identity. A streamed chunk costs well under a millisecond whatever the length of the session.
- **Lazy drawing.** Extmarks are drawn only for blocks in or near a window (two screens either side). A decoration provider draws the rest as they scroll into view.
- **Per-block parsing.** `lua/ui/markdown/Renderer.lua` parses each block's text on its own with a treesitter string parser, markdown, inline markdown and code-fence languages, and applies the same highlight and conceal captures the built-in highlighter would. A block is parsed once; streaming reparses only the tail. The renderer compiles its own copy of each highlights query, because the cached query is shared and plugins change it (render-markdown disables the fence `conceal_lines` patterns for its own drawing). On top it draws heading icons and bars, shaded code blocks with a language label, bullets by depth, checkboxes, quote bars, callouts (`> [!NOTE]`, `> [!thought]`), rules and links. The cursor line shows the raw text.
- **Who said what.** Your prompts sit on a tinted card (a blend of the accent and `Normal`'s background, recomputed on `ColorScheme`) under a **You** header; each reply opens under the agent's name; a rule separates turns.

In a transcript:

| You see | Where it comes from |
| --- | --- |
| **You** header, tinted card with a `▌` bar, a rule between turns | each prompt |
| **󰚩 Claude** header (the session's agent) | the start of each reply |
| `󰄬 Bash seq 1 20` with a spinner while it runs, then done or failed | the tool call: its name and main argument (command, path, pattern, url) |
| `⎿ Read 5 lines`, `⎿ 12 results` | the result of reads and searches, as a virtual line |
| Output under `⎿`, the first 5 lines shown and the rest folded | commands, searches and fetches; failures show their error. Output is shown verbatim: its fence is longer than any backtick run in it |
| `Edit a.lua +2 -2`, then the diff with file line numbers, diff colours and the file's own syntax colours | edits. Numbers come from finding the edit in the file, and are left off when it can't be found |
| `[!thought]` callout with how long it took, folded | thoughts |
| `󰄬 Done in 12s · 3 tools` | the end of each turn: done, interrupted, or a limit hit |
| `⠋ Working · 12s · <C-c> interrupt` under the last line | a running turn |
| `󰀦 Waiting for you: Edit a.lua` on the tool and the working line, and a notification when the transcript is out of sight | a permission request waiting for an answer |
| `● running  ctx 3%  $0.07` in the winbar | the session's state and its latest usage |

Keys in a transcript:

| Key | Does |
| --- | --- |
| `<CR>` | on a link or a file named in inline code (`lua/a.lua:42`): open it in a new tab. On a diff line: open the file at that line. On a tool: open what it touched. On a fold: open or close it |
| `gf` | open what is under the cursor in a new tab |
| `gy` | yank the code block under the cursor without its fences, or else the whole block (a prompt without its `>`) |
| `za`, `zR`, `zM` | folds, as anywhere |
| `]]`, `[[` | next and previous turn |
| `<C-c>` | interrupt the running turn |
| `<S-Tab>` | next session mode (also in the composer) |
| `go` | pick a session option (mode, model, effort, …) and its value |
| `i`, `a`, `o` | write to the session |

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

`lua/core/watcher.lua` keeps buffers in sync with edits made outside Neovim, such as Claude Code or any agent in another pane, without a keypress or focus change.

- **Live.** Each loaded file is watched (`vim.uv.new_fs_event`). A change reloads the buffer within about 100 ms, and the changed lines are highlighted for a few seconds. Atomic saves (write a temp file, rename it over) are followed: the watch is re-armed on the path after every event, and the file is checked once right after arming, so a write in the moment the watch starts isn't missed.
- **Only real files.** Buffers with a `buftype` (chat transcripts, the composer, terminals, help, scratch) and unsaved new files are never watched, so a hundred open sessions cost nothing.
- **Nothing left behind.** A watch stops when its buffer is unloaded, deleted, wiped or renamed, and all stop on exit.
- **Bounded.** At most `watcher.MAX` (128) files are watched; past that the least recently entered buffer gives up its watch and falls back to the `checktime` on `BufEnter` and `CursorHold`, and gets it back when entered.
- **Unsaved changes win.** A file that changes under a modified buffer is never reloaded. Instead of Neovim's blocking prompt you get one notification, and `:DiffDisk` opens your version against the disk in a new tab. A file deleted on disk keeps its text in the buffer.

## Permissions

`harness/permissions.lua` sets these rules:
- Read and write tools are allowed without asking.
- Exec tools follow the agent's `policy.auto_allow`, which `setup({ auto_allow = ... })` overrides.
- Claude's built-ins that reach the gate are asked through `vim.ui.select`, and so are exec tools when `auto_allow` is off.
- Anything that would need asking is refused when there is no UI.
- "Allow always" is remembered per session. The adapter is sent `allow_once`, so no lasting rule lands in the user's Claude Code settings.

## Tests

```sh
make test          # all specs
make test-file FILE=lua/harness/session_spec.lua
```

`harness/fake_agent.lua` is a scripted ACP agent for specs. It handles sessions, list and load, and permission requests.
