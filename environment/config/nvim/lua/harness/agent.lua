local Object = require('core.Object')
local transport = require('harness.acp.transport')

local agent = {}

agent.PATH = vim.fn.expand('~/.local/share/tin/nvim/agents.json')
agent.DEFAULT = 'claude'

local CLAUDE_SYSTEM = table.concat({
  'You are running inside the user\'s Neovim, driven by its harness.',
  'The nvim MCP tools act on that live editor; prefer them to reading files from disk.',
  'Each prompt starts with where the user is (their file, cursor and selection) in an <editor-context> tag.',
  'The session_* tools start and follow other agent sessions in this directory; they run in the background,',
  'so check on them with session_read.',
  'Answer fast, and show your work in the editor when it helps: search returns compact results (show = true',
  'also plays the search out in a picker); ui_show (list or panel) points the user at places or explains;',
  'ui_command drives a surface step by step and ui_read reads it; ui_screen and ui_keys read and drive any UI,',
  'such as vgit views opened with git_view. Write a lua script only for what these tools cannot do.',
}, ' ')

agent.BUILTIN = {
  claude = {
    description = 'Claude Code over ACP, on the Claude subscription',
    command = 'claude-agent-acp',
    model = 'claude-sonnet-5-5',
    system = CLAUDE_SYSTEM,
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
    model = spec.model,
    system = spec.system,
    mcp = spec.mcp or {},
    policy = spec.policy or {},
  }
end

local function resolve(value)
  if type(value) == 'string' and value:sub(1, 1) == '$' then return vim.env[value:sub(2)] or '' end

  return value
end

function Agent:executable()
  local found = vim.fn.exepath(self.command)

  if found ~= '' then return found end

  return vim.fn.expand('~/.local/bin/' .. self.command)
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

function Agent:spawn(cwd)
  return transport.process(vim.list_extend({ self:executable() }, self.args), { cwd = cwd, env = self:environment() })
end

agent.Agent = Agent

local loaded

local function read_exported(path)
  local file = io.open(path, 'r')

  if not file then return {} end

  local text = file:read('*a')
  file:close()

  local ok, decoded = pcall(vim.json.decode, text)

  if not ok or type(decoded) ~= 'table' or type(decoded.agents) ~= 'table' then
    vim.notify('Harness: ignoring unreadable agents file ' .. path, vim.log.levels.WARN)
    return {}
  end

  return decoded.agents
end

function agent.load(path)
  local specs = vim.tbl_extend('force', agent.BUILTIN, read_exported(path or agent.PATH))

  loaded = {}

  for name, spec in pairs(specs) do
    loaded[name] = Agent(name, spec)
  end

  return loaded
end

function agent.get(name)
  return (loaded or agent.load())[name or agent.DEFAULT]
end

function agent.names()
  local names = vim.tbl_keys(loaded or agent.load())

  table.sort(names)

  return names
end

return agent
