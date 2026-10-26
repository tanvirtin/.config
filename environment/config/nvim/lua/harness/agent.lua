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
  'The nvim MCP tools act on that live editor; prefer them to reading files from disk.',
  'Each prompt starts with where the user is (their file, cursor and selection) in an <editor-context> tag.',
  'The session_* tools start and follow other agent sessions in this directory; they run in the background,',
  'so check on them with session_read.',
  'Answer fast, and show your work in the editor when it helps: search returns compact results (show = true',
  'also plays the search out in a picker); ui_show (list or panel) points the user at places or explains;',
  'ui_command drives a surface step by step and ui_read reads it; ui_screen and ui_keys read and drive any UI,',
  'such as vgit views opened with git_view. Write a lua script only for what these tools cannot do.',
  'Your replies render as markdown in a Neovim buffer, where code references open the file on <CR>.',
  'Reference code as [label](nvim://file/<path>#L<line>), with the path relative to the working directory,',
  'for example [composer.lua:42](nvim://file/lua/harness/ui/composer.lua#L42); inline code like `path:line`',
  'also links. Keep replies scannable: short paragraphs, lists, and fenced code with a language.',
}, ' ')

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

local function resolve(value)
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
    env[key] = resolve(value)
  end

  return env
end

function Agent:mcp_servers()
  local servers = {}

  for _, server in ipairs(self.mcp) do
    local copy = vim.deepcopy(server)

    for _, var in ipairs(copy.env or {}) do
      var.value = resolve(var.value)
    end

    servers[#servers + 1] = copy
  end

  return servers
end

agent.Agent = Agent

local loaded

local function read_exported(path)
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
  local specs, default = read_exported(path or agent.PATH)

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
