local Buffer = require('core.Buffer')
local Window = require('core.Window')
local fences = require('core.fences')
local fs = require('core.fs')

local context = {}

context.TAG = 'editor-context'
context.INSTRUCTIONS = 'harness-instructions'

local function display_path(buffer)
  local name = buffer:get_name()

  return name ~= '' and fs.display(name) or '[No Name]'
end

local function uri_of(path, from, to)
  return 'file://' .. path .. string.format('#L%d-%d', from, to)
end

function context.selection(buffer, range)
  local name = buffer:get_name()
  local where = name ~= '' and fs.display(name) or '[No Name]'

  return {
    label = string.format('%s:%s', where, range[1] == range[2] and range[1] or (range[1] .. '-' .. range[2])),
    uri = name ~= '' and uri_of(name, range[1], range[2]) or nil,
    heading = string.format('Selected lines %d-%d of %s:', range[1], range[2], where),
    lines = buffer:get_lines(range[1] - 1, range[2]),
    language = buffer:get_option('filetype'),
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
    attachments = range and { context.selection(buffer, range) } or {},
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

function context.attach(captured, attachment)
  captured.attachments = captured.attachments or {}
  captured.attachments[#captured.attachments + 1] = attachment

  return captured
end

local function block_of(attachment, capabilities)
  if attachment.uri and capabilities and capabilities.embeddedContext then
    return {
      type = 'resource',
      resource = { uri = attachment.uri, text = table.concat(attachment.lines, '\n'), mimeType = 'text/plain' },
    }
  end

  return {
    type = 'text',
    text = attachment.heading .. '\n' .. table.concat(fences.wrap(attachment.lines, attachment.language), '\n'),
  }
end

function context.labels(captured)
  local out = {}

  for _, attachment in ipairs(type(captured) == 'table' and captured.attachments or {}) do
    if attachment.label then out[#out + 1] = attachment.label end
  end

  return #out > 0 and out or nil
end

function context.blocks(captured, capabilities)
  local text = context.text_of(captured)
  local blocks = text and { { type = 'text', text = text } } or {}

  for _, attachment in ipairs(type(captured) == 'table' and captured.attachments or {}) do
    blocks[#blocks + 1] = block_of(attachment, capabilities)
  end

  return blocks
end

function context.instructions(text)
  return string.format('<%s>%s</%s>', context.INSTRUCTIONS, text, context.INSTRUCTIONS)
end

function context.strip(text)
  for _, name in ipairs({ context.INSTRUCTIONS, context.TAG }) do
    local tag = vim.pesc(name)

    text = text:gsub('<' .. tag .. '>.-</' .. tag .. '>%s*', '')
  end

  return text
end

function context.selections_in(text)
  local labels = {}

  local rest = text:gsub('Selected lines (%d+)%-(%d+) of (.-):\n(`+)[^\n]*\n.-\n%4%s*', function(from, to, where)
    labels[#labels + 1] = string.format('%s:%s', where, from == to and from or (from .. '-' .. to))
    return ''
  end)

  return rest, labels
end

return context
