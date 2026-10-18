local schema = require('nvim_mcp.schema')
local util = require('nvim_mcp.tools.util')

local tools = {}

tools.BUILTIN = { 'editor', 'buffer', 'lsp', 'ui', 'exec' }

tools.set_focus = util.set_focus
tools.locations = util.locations

local RISKS = { read = true, write = true, exec = true }

local sets, order, by_name

local function check(set, entry)
  local where = string.format('toolset %s, tool %s', set, tostring(entry.name))

  assert(type(entry.name) == 'string' and entry.name ~= '', where .. ': name must be a string')
  assert(RISKS[entry.risk], where .. ': risk must be read, write or exec')
  assert(type(entry.summary) == 'string', where .. ': summary must be a string')
  assert(type(entry.params) == 'table', where .. ': params must be a list of fields')
  assert(type(entry.fn) == 'function', where .. ': fn must be a function')
  assert(entry.name:sub(1, 5) ~= 'nvim_', where .. ': the nvim_ prefix belongs to the raw API')
end

local function load()
  if sets then return end

  sets, order = {}, {}

  for _, name in ipairs(tools.BUILTIN) do
    tools.register(name, require('nvim_mcp.tools.' .. name))
  end
end

function tools.register(set, entries)
  load()

  local names = {}

  for _, entry in ipairs(entries) do
    check(set, entry)

    for other, other_entries in pairs(sets) do
      for _, existing in ipairs(other ~= set and other_entries or {}) do
        assert(existing.name ~= entry.name, string.format('tool %s is already in toolset %s', entry.name, other))
      end
    end

    assert(not names[entry.name], string.format('toolset %s lists %s twice', set, entry.name))
    names[entry.name] = true
    entry.kind = 'editor'
  end

  if not sets[set] then order[#order + 1] = set end

  sets[set] = entries
  by_name = nil
end

function tools.unregister(set)
  load()

  if not sets[set] then return end

  sets[set] = nil
  order = vim.tbl_filter(function(name)
    return name ~= set
  end, order)
  by_name = nil
end

function tools.entries()
  load()

  local out = {}

  for _, set in ipairs(order) do
    vim.list_extend(out, sets[set])
  end

  return out
end

function tools.definitions()
  return vim.tbl_map(function(entry)
    return {
      name = entry.name,
      kind = entry.kind,
      risk = entry.risk,
      always_ask = entry.always_ask,
      summary = entry.summary,
      params = entry.params,
    }
  end, tools.entries())
end

local function index()
  if not by_name then
    local entries = tools.entries()

    by_name = {}

    for _, entry in ipairs(entries) do
      by_name[entry.name] = entry
    end
  end

  return by_name
end

function tools.always_ask(name)
  local entry = index()[name]

  return entry ~= nil and entry.always_ask == true
end

function tools.risk(name)
  local entry = index()[name]

  return entry and entry.risk
end

function tools.run(name, args, caller)
  local entry = index()[name]

  if not entry then util.fail('unknown editor tool: ' .. tostring(name)) end

  local ok, coerced = schema.validate(schema.model(entry.params), args or {})

  if not ok then util.fail('invalid arguments for ' .. name .. ': ' .. schema.format_errors(coerced)) end

  return entry.fn(coerced, { caller = caller ~= '' and caller or nil })
end

return tools
