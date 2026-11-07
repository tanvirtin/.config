local fs = require('core.fs')
local lsp = require('core.lsp')
local text = require('core.text')
local symbols = require('harness.symbols')

local walkthrough_diagram = {}

walkthrough_diagram.MAX_ITEMS = 12
walkthrough_diagram.PREPARE = 'textDocument/prepareCallHierarchy'

local function width(value)
  return text.width(value)
end

local function pad(value, size)
  return value .. string.rep(' ', math.max(size - width(value), 0))
end

local function capped(items)
  local shown = vim.list_slice(items, 1, walkthrough_diagram.MAX_ITEMS)

  return shown, #items - #shown
end

function walkthrough_diagram.render(center, callers, callees, opts)
  opts = opts or {}

  local lines, targets = {}, {}

  local function add(line, target)
    lines[#lines + 1] = line

    if target then targets[#lines] = target end
  end

  local shown_callers, more_callers = capped(callers)
  local shown_callees, more_callees = capped(callees)
  local name_width, where_width = 0, 0

  for _, item in ipairs(shown_callers) do
    name_width, where_width = math.max(name_width, width(item.name)), math.max(where_width, width(item.where))
  end

  local left = #shown_callers > 0 and (name_width + 2 + where_width + 1) or 0
  local inner = width(center.name)
  local box = inner + 4
  local axis = math.max(#shown_callers > 0 and left + 1 or 0, math.floor(box / 2))
  local column = string.rep(' ', axis)

  for index, item in ipairs(shown_callers) do
    local body = pad(item.name, name_width) .. '  ' .. pad(item.where, where_width) .. ' '

    add(body .. string.rep('─', axis - width(body)) .. (index == 1 and '┐' or '┤'), item.target)
  end

  if more_callers > 0 then add(pad(string.format('… %d more', more_callers), axis) .. '│') end
  if #shown_callers > 0 then add(column .. '▼') end

  local indent = string.rep(' ', axis - math.floor(box / 2))

  add(indent .. '╭' .. string.rep('─', inner + 2) .. '╮')
  add(indent .. '│ ' .. center.name .. ' │  ' .. center.where, center.target)
  add(indent .. '╰' .. string.rep('─', inner + 2) .. '╯')

  if #shown_callees > 0 then
    local callee_width = 0

    for _, item in ipairs(shown_callees) do
      callee_width = math.max(callee_width, width(item.name))
    end

    add(column .. '│')

    for index, item in ipairs(shown_callees) do
      local last = index == #shown_callees and more_callees == 0

      add(
        column .. (last and '└─▶ ' or '├─▶ ') .. pad(item.name, callee_width) .. '  ' .. item.where,
        item.target
      )
    end

    if more_callees > 0 then add(column .. string.format('└─ … %d more', more_callees)) end
  end

  if #callers == 0 and #callees == 0 then
    add('')
    add('Nothing calls it and it calls nothing, as far as can be seen.')
  end

  if opts.note then
    add('')
    add(opts.note)
  end

  return { lines = lines, targets = targets }
end

local function last_part(name)
  return name:match('[%w_]+$') or name
end

local function where(path, line)
  return string.format('%s:%d', fs.basename(path), line)
end

function walkthrough_diagram.from_tree(source, list, center)
  local calls = symbols.calls(source.lines, source.path)
  local callers, callees, seen = {}, {}, {}
  local wanted = last_part(center.name)

  for _, call in ipairs(calls) do
    if call.line >= center.first and call.line <= center.last then
      if not seen[call.name] then
        seen[call.name] = true

        local _, separators = call.name:gsub('[.:]', '')
        local found = symbols.find(list, call.name)
          or (separators <= 1 and symbols.find(list, last_part(call.name)) or nil)

        callees[#callees + 1] = {
          name = call.name,
          where = found and where(source.path, found.first) or 'elsewhere',
          target = found and { path = source.path, line = found.first, last = found.last } or nil,
        }
      end
    elseif last_part(call.name) == wanted then
      local caller = symbols.enclosing(list, call.line, call.line)
      local key = caller and caller.name or ('line ' .. call.line)

      if not seen['caller:' .. key] then
        seen['caller:' .. key] = true
        callers[#callers + 1] = {
          name = caller and caller.name or '(top level)',
          where = where(source.path, call.line),
          target = { path = source.path, line = call.line, last = call.line },
        }
      end
    end
  end

  return {
    center = center,
    callers = callers,
    callees = callees,
    note = 'From this file only: no language server answered for it.',
  }
end

local function item_of(entry)
  local start = entry.selectionRange and entry.selectionRange.start or entry.range.start
  local path = lsp.path(entry.uri)

  return {
    name = entry.name,
    where = where(path, start.line + 1),
    target = { path = path, line = entry.range.start.line + 1, last = entry.range['end'].line + 1 },
  }
end

local function from_lsp(source, list, center, done)
  local params = {
    textDocument = { uri = lsp.uri(source.bufnr) },
    position = { line = center.name_line - 1, character = center.name_col - 1 },
  }

  lsp.request(source.bufnr, walkthrough_diagram.PREPARE, params, function(items)
    local item = items[1]

    if not item then return done(walkthrough_diagram.from_tree(source, list, center)) end

    local result = { center = center, callers = {}, callees = {} }
    local pending = 2

    local function settle()
      pending = pending - 1

      if pending == 0 then done(result) end
    end

    lsp.request(source.bufnr, 'callHierarchy/incomingCalls', { item = item }, function(calls)
      for _, call in ipairs(calls) do
        result.callers[#result.callers + 1] = item_of(call.from)
      end

      settle()
    end)

    lsp.request(source.bufnr, 'callHierarchy/outgoingCalls', { item = item }, function(calls)
      for _, call in ipairs(calls) do
        result.callees[#result.callees + 1] = item_of(call.to)
      end

      settle()
    end)
  end)
end

function walkthrough_diagram.collect(source, done)
  local list = symbols.parse(source.lines, source.path)
  local center = symbols.enclosing(list, source.first, source.last)
    or symbols.enclosing(list, source.first, source.first)

  if not center then return done(nil, 'no function around this step to draw') end

  if source.bufnr and lsp.supports(source.bufnr, walkthrough_diagram.PREPARE) then
    return from_lsp(source, list, center, done)
  end

  done(walkthrough_diagram.from_tree(source, list, center))
end

function walkthrough_diagram.center_of(result, path)
  local center = result.center

  return {
    name = center.name,
    where = where(path, center.first),
    target = { path = path, line = center.first, last = center.last },
  }
end

return walkthrough_diagram
