local lazy = require('core.lazy')

local harness = lazy('harness')
local agent = lazy('harness.agent')
local edits = lazy('harness.ui.edits')
local notice = lazy('harness.ui.notice')

local command = {}

local function scopes()
  local names = vim.tbl_keys(edits.SCOPE)

  table.sort(names)

  return names
end

command.SUBCOMMANDS = {
  {
    name = 'ask',
    desc = 'Ask the agent, from the lines of a range',
    arguments = {},
    run = function(rest, args)
      if rest == '' then return notice.warn('ask what? :Harness ask <prompt>') end

      return harness.ask(rest, { range = args.range > 0 and { args.line1, args.line2 } or nil })
    end,
  },
  {
    name = 'new',
    desc = 'Open a new session, with an agent if you name one',
    arguments = function()
      return agent.names()
    end,
    run = function(rest)
      return harness.new({ agent = rest ~= '' and rest or nil })
    end,
  },
  {
    name = 'switch',
    desc = 'The session selector: new, open, delete',
    arguments = {},
    run = function()
      return harness.switch()
    end,
  },
  {
    name = 'cancel',
    desc = 'Stop the running turn',
    arguments = {},
    run = function()
      return harness.cancel()
    end,
  },
  {
    name = 'fork',
    desc = 'Fork the session from the reply under the cursor',
    arguments = {},
    run = function()
      return harness.fork()
    end,
  },
  {
    name = 'changes',
    desc = 'Every file the session changed, in vgit',
    arguments = {},
    run = function()
      return harness.changes()
    end,
  },
  {
    name = 'revert',
    desc = 'Revert an edit, a turn or the session after a vgit preview',
    arguments = scopes,
    run = function(rest)
      return harness.revert(rest)
    end,
  },
  {
    name = 'quickfix',
    desc = 'Send an edit, a turn or the session to the quickfix list',
    arguments = scopes,
    run = function(rest)
      return harness.quickfix(rest)
    end,
  },
  {
    name = 'waiting',
    desc = 'Go to the request waiting for you',
    arguments = {},
    run = function()
      return harness.waiting()
    end,
  },
  {
    name = 'permissions',
    desc = 'The session\'s grants, saved rules and decisions',
    arguments = {},
    run = function()
      return harness.permissions()
    end,
  },
}

function command.find(name)
  for _, sub in ipairs(command.SUBCOMMANDS) do
    if sub.name == name then return sub end
  end
end

function command.names()
  return vim.tbl_map(function(sub)
    return sub.name
  end, command.SUBCOMMANDS)
end

function command.complete(lead, line)
  local words = vim.split(vim.trim(line:gsub('^%S+', '')), '%s+', { trimempty = true })
  local typing_first = #words == 0 or (#words == 1 and not line:match('%s$'))

  if typing_first then
    return vim.tbl_filter(function(name)
      return vim.startswith(name, lead)
    end, command.names())
  end

  local sub = command.find(words[1])
  local options = sub and (type(sub.arguments) == 'function' and sub.arguments() or sub.arguments) or {}

  return vim.tbl_filter(function(name)
    return vim.startswith(name, lead)
  end, options)
end

function command.execute(args)
  local text = vim.trim(args.args or '')
  local name, rest = text:match('^(%S+)%s*(.*)$')

  if not name then return harness.switch() end

  local sub = command.find(name)

  if not sub then
    return notice.warn(string.format('no Harness command "%s"; try %s', name, table.concat(command.names(), ', ')))
  end

  return sub.run(rest, args)
end

return {
  name = 'Harness',
  opts = {
    nargs = '*',
    range = true,
    complete = command.complete,
    desc = 'Drive Harness: ask, new, switch, cancel, fork, changes, revert, quickfix, waiting, permissions',
  },
  execute = command.execute,
  command = command,
}
