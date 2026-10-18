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
| ui | `ui/transcript.lua`, `ui/commands.lua` | Transcripts rendered from history, which can be reopened at any time, and the user's commands. |

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

## The composer

You write to a session in the composer, much like a commit message window.

- **Opening.** Press `i`, `a`, `o`, `I`, `A` or `O` in a session's buffer, which is read-only. The composer opens as a float along the bottom of the editor, detached from your windows. Its border names the session it writes to and lists its keys.
- **No file behind it.** It's a buffer with `buftype=acwrite`, so it edits like any buffer, and "writing" it means sending it.
  - `<CR>` in normal mode, or `:w`, sends to the session, then clears and closes the composer. In insert mode, `<CR>` is just a newline.
  - `q` or `<Esc>` in normal mode closes it. So does leaving it. The draft is kept per session for next time.
- **Only one.** Opening it again focuses the open one, and opening it from another session's buffer moves it there.
- **Context.** Each message says where you were, from the buffer the session was opened from.

It belongs to the session, not to the session's buffer:

| When | The composer |
| --- | --- |
| The session's buffer is closed | Stays open. Sending shows the buffer again in the window you came from, with the reply streaming in. |
| You leave it, `q` it or `:q` it | Closes and keeps the draft, which is saved as you type. `:q` never complains about unsaved changes. |
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

In a transcript:
- tool calls appear as `-> name` lines
- edits made by Claude's built-in Edit appear as fenced diffs, and open buffers reload (`checktime`) after them
- plans appear as checklists

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
