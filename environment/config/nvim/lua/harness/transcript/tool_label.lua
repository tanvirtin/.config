local text = require('core.text')
local compact = require('compact')
local settings = require('harness.settings.transcript')

local tool_label = {}

function tool_label.relative(path, dir)
  if type(path) ~= 'string' then return path end

  if dir and path == dir then return '.' end
  if dir and path:sub(1, #dir + 1) == dir .. '/' then return path:sub(#dir + 2) end

  return text.display_path(path)
end

local ARGUMENT_KEYS = {
  'command',
  'cmd',
  'file_path',
  'filePath',
  'absolute_path',
  'path',
  'pattern',
  'query',
  'url',
  'description',
  'code',
  'bufnr',
}

local function argument_text(key, value, dir)
  if type(value) == 'table' then
    local parts = {}

    for _, part in ipairs(value) do
      parts[#parts + 1] = tostring(part)
    end

    value = table.concat(parts, ' ')
  end

  value = tostring(value)

  return key:lower():find('path') and tool_label.relative(value, dir) or value
end

function tool_label.label(state, id, dir)
  local raw = state.name or (state.title and state.title:match('^(%S+)')) or 'tool'
  local name = raw
  local server, tool = name:match('^mcp__(.-)__(.+)$')

  if server then name = server .. ':' .. tool end

  local argument

  for _, key in ipairs(ARGUMENT_KEYS) do
    local value = state.input[key]

    if value ~= nil and value ~= vim.NIL and value ~= '' then
      argument = argument_text(key, value, dir)
      break
    end
  end

  if not argument and state.locations and state.locations[1] then
    argument = tool_label.relative(state.locations[1].path, dir)
  end

  if not argument and state.title and state.title:find('%s') then
    argument = state.title:gsub('^' .. vim.pesc(raw) .. '%s*', '')
  end

  if not argument and not state.name and not state.title then argument = id end

  return compact.line(name, 80), argument and compact.line(argument, settings:get('argument_max')) or nil
end

return tool_label
