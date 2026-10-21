local Buffer = require('core.Buffer')
local Window = require('core.Window')
local fs = require('core.fs')

local context = {}

context.TAG = 'editor-context'

local function display_path(buffer)
  local name = buffer:get_name()

  return name ~= '' and fs.display(name) or '[No Name]'
end

function context.capture(win, range)
  local window = Window(win)
  local buffer = window:get_buffer()
  local cursor = window:get_cursor()
  local parts = {
    string.format(
      'The user is in %s (bufnr %d), line %d, col %d.',
      display_path(buffer),
      buffer.bufnr,
      cursor[1],
      cursor[2] + 1
    ),
  }

  if range then parts[#parts + 1] = string.format('They selected lines %d-%d.', range[1], range[2]) end

  parts[#parts + 1] = 'Editor tools default to this buffer when path and bufnr are omitted.'

  return string.format('<%s>%s</%s>', context.TAG, table.concat(parts, ' '), context.TAG)
end

function context.capture_buffer(buf, range)
  local buffer = Buffer(buf)

  for _, window in ipairs(Window.list()) do
    if window:get_buffer().bufnr == buf then return context.capture(window.win_id, range) end
  end

  local mark = buffer:get_mark('"')
  local line, col = mark[1] > 0 and mark[1] or 1, mark[2]
  local parts = {
    string.format('The user is in %s (bufnr %d), line %d, col %d.', display_path(buffer), buf, line, col + 1),
  }

  if range then parts[#parts + 1] = string.format('They selected lines %d-%d.', range[1], range[2]) end

  parts[#parts + 1] = 'Editor tools default to this buffer when path and bufnr are omitted.'

  return string.format('<%s>%s</%s>', context.TAG, table.concat(parts, ' '), context.TAG)
end

function context.strip(text)
  local tag = vim.pesc(context.TAG)
  local pattern = '<' .. tag .. '>.-</' .. tag .. '>%s*'

  return (text:gsub(pattern, ''))
end

return context
