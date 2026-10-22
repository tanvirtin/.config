local Buffer = require('core.Buffer')
local Window = require('core.Window')
local fences = require('core.fences')
local fs = require('core.fs')

local context = {}

context.TAG = 'editor-context'

local function display_path(buffer)
  local name = buffer:get_name()

  return name ~= '' and fs.display(name) or '[No Name]'
end

local function selection(buffer, range)
  if not range then return nil end

  local name = buffer:get_name()

  return {
    path = name ~= '' and name or nil,
    from = range[1],
    to = range[2],
    lines = buffer:get_lines(range[1] - 1, range[2]),
    filetype = buffer:get_option('filetype'),
  }
end

local function describe(buffer, line, col, range)
  local parts = {
    string.format('The user is in %s (bufnr %d), line %d, col %d.', display_path(buffer), buffer.bufnr, line, col + 1),
  }

  if range then parts[#parts + 1] = string.format('They selected lines %d-%d.', range[1], range[2]) end

  parts[#parts + 1] = 'Editor tools default to this buffer when path and bufnr are omitted.'

  return {
    text = string.format('<%s>%s</%s>', context.TAG, table.concat(parts, ' '), context.TAG),
    selection = selection(buffer, range),
  }
end

function context.capture(win, range)
  local window = Window(win)
  local cursor = window:get_cursor()

  return describe(window:get_buffer(), cursor[1], cursor[2], range)
end

function context.capture_buffer(buf, range)
  for _, window in ipairs(Window.list()) do
    if window:get_buffer().bufnr == buf then return context.capture(window.win_id, range) end
  end

  local buffer = Buffer(buf)
  local mark = buffer:get_mark('"')

  return describe(buffer, mark[1] > 0 and mark[1] or 1, mark[2], range)
end

function context.text_of(captured)
  if type(captured) == 'table' then return captured.text end

  return captured
end

local function uri_of(path, from, to)
  return 'file://' .. path .. string.format('#L%d-%d', from, to)
end

function context.blocks(captured, capabilities)
  local text = context.text_of(captured)
  local blocks = text and { { type = 'text', text = text } } or {}
  local selected = type(captured) == 'table' and captured.selection

  if not selected then return blocks end

  local body = table.concat(selected.lines, '\n')

  if selected.path and capabilities and capabilities.embeddedContext then
    blocks[#blocks + 1] = {
      type = 'resource',
      resource = { uri = uri_of(selected.path, selected.from, selected.to), text = body, mimeType = 'text/plain' },
    }
  else
    local where = selected.path and fs.display(selected.path) or '[No Name]'
    local heading = string.format('Selected lines %d-%d of %s:', selected.from, selected.to, where)

    blocks[#blocks + 1] = {
      type = 'text',
      text = heading .. '\n' .. table.concat(fences.wrap(selected.lines, selected.filetype), '\n'),
    }
  end

  return blocks
end

function context.strip(text)
  local tag = vim.pesc(context.TAG)
  local pattern = '<' .. tag .. '>.-</' .. tag .. '>%s*'

  return (text:gsub(pattern, ''))
end

return context
