local Timer = require('core.Timer')
local console = require('core.console')
local fs = require('core.fs')
local text = require('core.text')
local api = require('nvim_mcp.api')
local async = require('harness.async')
local tools = require('nvim_mcp.tools')
local DECISION = require('harness.acp.connection').DECISION

local permissions = {}

permissions.MCP_NAME = 'nvim'

local PREFIX = 'mcp__' .. permissions.MCP_NAME .. '__'

function permissions.tier(tool_name)
  if type(tool_name) ~= 'string' or tool_name:sub(1, #PREFIX) ~= PREFIX then return nil end

  local name = tool_name:sub(#PREFIX + 1)

  return tools.risk(name) or (name:sub(1, 5) == 'nvim_' and api.risk(name)) or 'exec'
end

permissions.CHOICES = {
  { key = '1', kind = DECISION.allow_once, label = 'Allow once' },
  { key = '2', kind = DECISION.allow_always, label = 'Allow always (this session)' },
  { key = '3', kind = DECISION.reject_once, label = 'Reject' },
}

permissions.MAX_CHOICES = 9

local KINDS = {
  [DECISION.allow_once] = true,
  [DECISION.allow_always] = true,
  [DECISION.reject_once] = true,
  [DECISION.reject_always] = true,
}

function permissions.choices(request)
  local options = ((request and request.params) or {}).options
  local choices = {}

  for _, option in ipairs(type(options) == 'table' and options or {}) do
    if type(option) == 'table' and KINDS[option.kind] and #choices < permissions.MAX_CHOICES then
      choices[#choices + 1] = {
        key = tostring(#choices + 1),
        kind = option.kind,
        label = type(option.name) == 'string' and option.name ~= '' and option.name or option.kind,
      }
    end
  end

  return #choices > 0 and choices or permissions.CHOICES
end

function permissions.offers(request, kind)
  for _, option in ipairs(((request and request.params) or {}).options or {}) do
    if type(option) == 'table' and option.kind == kind then return true end
  end

  return false
end

local WIDTH = 160

local function count_lines(text)
  local _, newlines = text:gsub('\n', '')

  return newlines + 1
end

function permissions.describe(request)
  local call = (request.params or {}).toolCall or {}
  local input = call.rawInput
  local detail

  if type(input) == 'table' then
    local code = input.code or input.command

    if type(code) == 'string' then
      local lines = count_lines(vim.trim(code))
      detail = vim.split(vim.trim(code), '\n', { plain = true })[1]
        .. (lines > 1 and ' (+' .. text.plural(lines - 1, 'line') .. ')' or '')
    elseif type(input.file_path) == 'string' then
      local content = input.content or input.new_string

      local path = fs.display(input.file_path)
      local size = type(content) == 'string' and text.plural(count_lines(content), 'line') or nil

      if request.tool:find(path, 1, true) then
        return require('compact').line(request.tool .. (size and (' (' .. size .. ')') or ''), WIDTH)
      end

      detail = path .. (size and (' (' .. size .. ')') or '')
    else
      detail = vim.inspect(input, { newline = ' ', indent = '' })
    end
  elseif input ~= nil and input ~= vim.NIL then
    detail = tostring(input)
  end

  return require('compact').line(request.tool .. (detail and (': ' .. detail) or ''), WIDTH)
end

function permissions.ui_ask(request)
  local future = async.Future.new()

  Timer.schedule(function()
    if future.done then return end

    local picker = console.select(permissions.choices(request), {
      prompt = 'Harness wants to run ' .. permissions.describe(request),
      format_item = function(choice)
        return choice.label
      end,
    }, function(choice)
      future:set_result(choice and choice.kind or DECISION.reject_once)
      async.drain()
    end)

    if future.done and type(picker) == 'table' and picker.close then pcall(picker.close, picker) end
    future.picker = picker
  end)

  function future.dismiss()
    if future.done then return end

    future:set_result(DECISION.cancelled)

    local picker = future.picker

    if type(picker) == 'table' and picker.close then pcall(picker.close, picker) end
  end

  return future
end

function permissions.new(opts)
  opts = opts or {}

  local always = {}

  return function(request)
    local tier = permissions.tier(request.tool)
    local destructive = tier ~= nil and tools.always_ask(request.tool:sub(#PREFIX + 1))

    if not destructive then
      if tier == 'read' or tier == 'write' or (tier and opts.auto_allow) then return DECISION.allow_once end
      if always[request.tool] then return DECISION.allow_once end
    end

    if not opts.ask then return DECISION.reject_once end

    local function decide(kind)
      if kind == DECISION.allow_always and destructive then return DECISION.allow_once end

      if kind == DECISION.allow_always then
        always[request.tool] = true
        return permissions.offers(request, DECISION.allow_always) and DECISION.allow_always or DECISION.allow_once
      end

      return kind
    end

    local answer = opts.ask(request)

    if type(answer) ~= 'table' or not answer.on_complete then return decide(answer) end

    local decided = async.Future.new()

    decided.dismiss = answer.dismiss
    answer:on_complete(function(err, kind)
      decided:set_result(decide(not err and kind or DECISION.reject_once))
    end)

    return decided
  end
end

return permissions
