local lazy = require('core.lazy')

local fs = lazy('core.fs')
local env = lazy('core.env')
local Object = lazy('core.Object')
local console = lazy('core.console')

local agent = {}

agent.PATH = fs.expand('~/.local/share/tin/nvim/agents.json')
agent.DEFAULT = 'claude'

local SYSTEM = table.concat({
  'You are running inside the user\'s Neovim, driven by its harness.',
  'Each prompt starts with where the user is (their file, cursor and selection) in an <editor-context> tag.',
  'Editor tools default to that buffer when path and bufnr are omitted, so call editor_state only for the open buffers and tabs.',
  'The nvim MCP tools act on the live editor: read and edit files through buffer_read and buffer_edit in place of your own file tools,',
  'because buffers hold unsaved changes and the user watches each edit land. buffer_edit takes several edits in one call.',
  'The session_* tools start and follow other agent sessions in this directory; they run in the background, so check on them with session_read.',
  '',
  'The editor\'s UI is yours to drive, but showing is optional: answer fast, show when it helps the user.',
  '- search returns compact results at once (files, grep, lsp definition and references, diagnostics, buffers);',
  '  show = true also plays the search out in a picker the user watches.',
  '- ui_show points the user at several places (kind = list) or explains with markdown and tables (kind = panel).',
  '- ui_command drives a surface step by step (picker: query, move, select; list: cursor, open, add; panel: write)',
  '  and ui_read reads it. ui_pick asks the user to choose; read their choice later with ui_read.',
  '- ui_screen shows what the user sees; ui_keys types keys into any UI. Use them with vgit\'s views,',
  '  opened with git_view; git_status, git_diff, git_log and git_blame read git compactly.',
  '- lua runs one script with full vim.* access: use it for what these tools cannot do, in place of many small calls.',
  'When the editor shows the answer, keep the chat reply brief.',
  'Your replies render as markdown in a Neovim buffer, where code references open the file on <CR>.',
  'Reference code as [label](nvim://file/<path>#L<line>), with the path relative to the working directory,',
  'for example [composer.lua:42](nvim://file/lua/harness/ui/composer.lua#L42); inline code like `path:line`',
  'also links. Keep replies scannable: short paragraphs, lists, and fenced code with a language.',
}, '\n')

agent.BUILTIN = {
  claude = {
    description = 'Claude Code over ACP, on the Claude subscription',
    command = 'claude-agent-acp',
    model = 'claude-sonnet-5-5',
    login = 'run `claude auth login` in a terminal',
    fork_at_message = true,
    system = SYSTEM,
    policy = { auto_allow = true },
  },
  opencode = {
    description = 'opencode over ACP, with the models opencode is set up for',
    command = 'opencode',
    args = { 'acp' },
    login = 'run `opencode auth login` in a terminal',
    system = SYSTEM,
    policy = { auto_allow = true },
  },
}

local Agent = Object:extend()

function Agent:constructor(name, spec)
  return {
    name = name,
    description = spec.description or '',
    command = spec.command,
    args = spec.args or {},
    env = spec.env or {},
    server = spec.server,
    model = spec.model,
    login = spec.login,
    fork_at_message = spec.fork_at_message,
    system = spec.system,
    mcp = spec.mcp or {},
    policy = spec.policy or {},
    transcripts = spec.transcripts,
    permission_rules = spec.permission_rules,
  }
end

agent.TRANSCRIPTS = {
  ['claude-agent-acp'] = '~/.claude/projects/*/{id}.jsonl',
}

function Agent:transcript(id)
  local pattern = self.transcripts or agent.TRANSCRIPTS[fs.basename(self.command or '')]

  if not pattern or not id then return nil end

  local matches = fs.glob(fs.expand((pattern:gsub('{id}', id))))

  return matches[1]
end

function Agent:_resolve(value)
  if type(value) == 'string' and value:sub(1, 1) == '$' then return env.var(value:sub(2)) or '' end

  return value
end

function Agent:executable()
  local found = fs.exepath(self.command)

  if found ~= '' then return found end

  return fs.expand('~/.local/bin/' .. self.command)
end

function Agent:environment()
  if next(self.env) == nil then return nil end

  local env = {}

  for key, value in pairs(self.env) do
    env[key] = self:_resolve(value)
  end

  return env
end

function Agent:mcp_servers()
  local servers = {}

  for _, server in ipairs(self.mcp) do
    local copy = vim.deepcopy(server)

    for _, var in ipairs(copy.env or {}) do
      var.value = self:_resolve(var.value)
    end

    servers[#servers + 1] = copy
  end

  return servers
end

agent.Agent = Agent

local loaded

function Agent._read_exported(path)
  local file = io.open(path, 'r')

  if not file then return {}, nil end

  local text = file:read('*a')
  file:close()

  local ok, decoded = pcall(vim.json.decode, text)

  if not ok or type(decoded) ~= 'table' or type(decoded.agents) ~= 'table' then
    console.notify_now('Harness: ignoring unreadable agents file ' .. path, 'warn')
    return {}, nil
  end

  return decoded.agents, decoded.default
end

function agent.load(path)
  local specs, default = Agent._read_exported(path or agent.PATH)

  loaded = {}

  for name, spec in pairs(vim.tbl_extend('force', agent.BUILTIN, specs)) do
    loaded[name] = Agent(name, vim.tbl_extend('force', agent.BUILTIN[name] or {}, spec))
  end

  agent.default_name = type(default) == 'string' and default or nil

  return loaded
end

function agent.get(name)
  local all = loaded or agent.load()

  return all[name or agent.default_name or agent.DEFAULT]
end

function agent.names()
  local names = vim.tbl_keys(loaded or agent.load())

  table.sort(names)

  return names
end

return agent
