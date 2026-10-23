local lazy = require('core.lazy')

local fs = lazy('core.fs')
local hub = lazy('harness.hub')
local Buffer = lazy('core.Buffer')
local Window = lazy('core.Window')
local keymap = lazy('core.keymap')
local context = lazy('harness.context')
local CodeBlocks = lazy('harness.transcript.CodeBlocks')

local code_blocks = {}

code_blocks.APPLY = 'Apply the attached code block to %s, merging it with the code already there.'

local function spans(view)
  return CodeBlocks.list(view.document.blocks)
end

local function cursor_row()
  return Window.get_current():get_cursor()[1] - 1
end

function code_blocks.at(view)
  return CodeBlocks.at(spans(view), cursor_row())
end

function code_blocks.jump(view, direction)
  local list, row, count = spans(view), cursor_row(), keymap.count()
  local span = direction > 0 and CodeBlocks.next(list, row, count) or CodeBlocks.previous(list, row, count)

  if not span then return false, direction > 0 and 'no code block below' or 'no code block above' end

  Window.get_current():set_cursor({ span.body_start + 1, 0 })

  return true
end

function code_blocks.select(view, around)
  local span = code_blocks.at(view)

  if not span then return false end

  local top = around and span.start or span.body_start
  local bottom = around and span.finish or span.body_finish

  if bottom < top then return false end

  Window.get_current():select_lines(top + 1, bottom + 1)

  return true
end

local function window_showing(view)
  local preferred = view.source_win and Window(view.source_win)

  if preferred and preferred:is_valid() and preferred:get_buffer().bufnr == view.source_buf then return preferred end

  for _, window in ipairs(Window.list_tab()) do
    if window:get_buffer().bufnr == view.source_buf then return window end
  end
end

local function target(view)
  if not (view.source_buf and Buffer.exists(view.source_buf)) then return nil end

  local buffer = Buffer(view.source_buf)
  local window = window_showing(view)

  if window then return buffer, window:get_cursor()[1], window end

  return buffer, math.max(buffer:get_mark('"')[1], 1)
end

function code_blocks.insert(view)
  local span = code_blocks.at(view)

  if not span then return false, 'no code block here' end

  local buffer, line, window = target(view)

  if not buffer then return false, 'no code buffer to insert into' end

  buffer:break_undo()
  buffer:set_lines(span.lines, line, line)

  if window then window:set_cursor({ line + 1, 0 }) end

  return true
end

function code_blocks.apply(view)
  local span = code_blocks.at(view)

  if not span then return false, 'no code block here' end

  local buffer = target(view)

  if not buffer then return false, 'no code buffer to apply it to' end

  local name = buffer:get_name()
  local captured = context.capture_buffer(buffer.bufnr)

  context.attach(captured, {
    title = 'The code block',
    lines = span.lines,
    language = span.language,
  })

  local prompt = code_blocks.APPLY:format(name ~= '' and fs.display(name) or 'the current buffer')
  local _, err = hub.send(view.session, prompt, captured)

  if err then return false, tostring(err) end

  return true
end

return code_blocks
