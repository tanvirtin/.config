local lazy = require('core.lazy')

local Block = require('harness.transcript.Block')
local Buffer = require('core.Buffer')
local EditPatches = require('harness.transcript.EditPatches')
local SessionChanges = require('harness.transcript.SessionChanges')
local Fold = require('core.Fold')
local INLINE = require('ui.markdown.Renderer').INLINE
local Timer = require('core.Timer')
local TranscriptView = require('harness.ui.TranscriptView')
local Window = require('core.Window')
local buffers = require('core.buffers')
local console = require('core.console')
local display = require('harness.ui.display')
local fences = require('harness.transcript.fences')
local links = require('harness.ui.links')
local permission_prompt = require('harness.ui.permission_prompt')
local register = require('core.register')
local settings = require('harness.settings')
local theme = require('harness.transcript.theme')
local vgit = require('harness.vgit')
local winbar = require('harness.ui.winbar')

local composer = lazy('harness.ui.composer')

local transcript = {}

transcript.FILETYPE = TranscriptView.FILETYPE
transcript.WINBAR = winbar.HINTS
transcript.CHOICES = permission_prompt.CHOICES

transcript.view = display.view
transcript.view_of = display.view_of
transcript.buffer_of = display.buffer_of
transcript.last = display.last
transcript.window = display.window
transcript.to_bottom = display.to_bottom
transcript.open = display.open
transcript.forget = display.forget
transcript.winbar = winbar.transcript
transcript.asks_of = permission_prompt.asks_of
transcript.ask = permission_prompt.ask
transcript.answer = permission_prompt.answer

function transcript.render(history, title)
  return require('harness.transcript.TextRenderer').render(history, title)
end

function transcript.announce_waiting(session)
  local view = display.view_of(session)

  if view then view:announce_waiting() end
end

function transcript.foldexpr()
  local view = display.view()

  return view and view.document:fold_level(Fold.lnum() - 1) or '0'
end

local SUMMED = { [Block.KIND.tool] = 'tool', [Block.KIND.message] = 'reply' }

local function children_in(view, first, last)
  local counts = {}

  for _, block in ipairs(view.document.blocks) do
    if block.start >= first and block.start < last then
      if not block.depth then return nil end

      local noun = SUMMED[block.kind]

      if noun then counts[noun] = (counts[noun] or 0) + 1 end
    end
  end

  local parts = {}

  for _, noun in ipairs({ 'tool', 'reply' }) do
    local n = counts[noun]

    if n then
      parts[#parts + 1] = string.format('%d %s', n, n == 1 and noun or (noun == 'reply' and 'replies' or noun .. 's'))
    end
  end

  return #parts > 0 and table.concat(parts, ' · ') or nil
end

local function rails(view, row, last)
  local block = view and view.document:block_at(row)
  local depth = block and (block.depth or 0) + (row > block.start and 1 or 0) or 0

  if depth == 0 then return '  ' end

  local tail = view.document:block_at(last)
  local closes = tail and tail.last_child and last >= tail.start + #tail.lines and row == block.start

  return string.rep(theme.GUTTER, depth - 1) .. (closes and theme.BRANCH_END or theme.GUTTER)
end

function transcript.foldtext()
  local first, last = Fold.range()
  local hidden = last - first + 1
  local view = display.view()
  local children = view and children_in(view, first - 1, last)
  local text = children and '⋯ ' .. children or string.format('⋯ %d more line%s', hidden, hidden == 1 and '' or 's')

  return { { rails(view, first - 1, last - 1), 'UiMuted' }, { text, 'UiMuted' } }
end

local function target_at(view, window)
  local cursor = window:get_cursor()
  local row, col = cursor[1] - 1, cursor[2]
  local document, dir = view.document, view.session.dir
  local kind, text = document.renderer:inline_at(row, col)

  if kind then
    local target = links.resolve(kind, text, dir)
    if target then return target end
  end

  local block = document:block_at(row)

  if not block then return nil end

  if block.kind == Block.KIND.diff then
    local line = EditPatches.line_at(block, row)
    return links.resolve(INLINE.link, block.path, dir) and { path = block.path, line = line } or nil
  end

  if block.kind == Block.KIND.tool and block.locations and block.locations[1] then
    local location = block.locations[1]
    return { path = location.path, line = location.line }
  end
end

local function view_for(buf)
  return display.view(buf or Buffer.current_number())
end

function transcript.jump(direction, buf)
  local view = view_for(buf)

  if not view then return end

  local window = Window.get_current()
  local row = window:get_cursor()[1] - 1
  local rows = {}

  for _, block in ipairs(view.document.blocks) do
    if block.kind == Block.KIND.prompt then rows[#rows + 1] = block.start end
  end

  if direction < 0 then
    for i = #rows, 1, -1 do
      if rows[i] < row then return window:set_cursor({ rows[i] + 1, 0 }) end
    end
  else
    for _, candidate in ipairs(rows) do
      if candidate > row then return window:set_cursor({ candidate + 1, 0 }) end
    end
  end
end

local function toggle_at(window, fold_row, row)
  window:set_cursor({ fold_row, 0 })
  window:normal(window:fold_closed(fold_row) and 'zo' or 'zc')
  window:set_cursor({ row, 0 })
end

function transcript.activate(buf)
  local view = view_for(buf)

  if not view then return false end

  local window = Window.get_current()
  local row = window:get_cursor()[1]

  if window:fold_closed(row) then
    window:normal('zo')
    return true
  end

  if links.open(target_at(view, window)) then return true end

  if window:fold_level(row) > 0 then
    window:normal('zc')
    return true
  end

  local block = view.document:block_at(row - 1)

  if block and block.grouped then
    toggle_at(window, block.finish + 1, row)
    return true
  end

  if block and block.kind == Block.KIND.collapsed then
    view:expand()
    window:set_cursor({ 1, 0 })
    return true
  end

  if block and block.folds and block.folds[1] then
    toggle_at(window, block.start + block.folds[1][1] + 1, row)
    return true
  end

  return false
end

function transcript.open_target(buf)
  local view = view_for(buf)

  return view and links.open(target_at(view, Window.get_current())) or false
end

function transcript.path_at(buf)
  local view = view_for(buf)
  local target = view and target_at(view, Window.get_current())

  return target and target.path or nil
end

function transcript.git_diff(buf)
  local path = transcript.path_at(buf)

  if not path then return false, 'no file here' end

  return vgit.git_diff(path)
end

function transcript.edit_at(buf)
  local view = view_for(buf)

  if not view then return nil end

  local blocks = view.document.blocks
  local block = view.document:block_at(Window.get_current():get_cursor()[1] - 1)

  if not block or not block.id then return nil end

  local files = {}

  for _, candidate in ipairs(blocks) do
    if candidate.kind == Block.KIND.diff and candidate.id == block.id and candidate.edit then
      files[#files + 1] = candidate.edit
    end
  end

  return #files > 0 and files or nil
end

function transcript.show_edit(buf)
  local files = transcript.edit_at(buf)

  if not files then return false, 'no edit here' end

  return vgit.show(files)
end

function transcript.show_changes(view)
  if not view then return false, 'no session here' end

  local files = SessionChanges.files(view.session.history, view.edits, buffers.lines_of)

  if #files == 0 then return false, 'this session has not changed any file' end

  return vgit.show(files)
end

function transcript.yank(buf, name)
  local view = view_for(buf)

  if not view then return nil end

  local row = Window.get_current():get_cursor()[1] - 1
  local block = view.document:block_at(row)

  if not block then return nil end

  if block.kind == Block.KIND.diff and block.edit then
    local patch = vgit.patch_text(block.edit)

    register.set(patch, name)

    return patch, true
  end

  local lines = block.lines
  local first, last = fences.fenced_at(lines, row - block.start + 1)
  local text = vim.list_slice(lines, first or 1, last or #lines)

  if not first and lines[1] and lines[1]:match('^>') then
    text = vim.tbl_map(function(line)
      return (line:gsub('^> ?', ''))
    end, text)
  end

  register.set(text, name)

  return text, first ~= nil
end

local function describe(choice, current)
  local mark = choice.value == current and '● ' or '  '

  return mark .. (choice.name or choice.value) .. (choice.description and ('  ' .. choice.description) or '')
end

function transcript.pick_option(session)
  local options = vim.tbl_filter(function(option)
    return option.type == nil or option.type == 'select'
  end, session.options)

  local function pick_value(option)
    console.select(session.choices(option), {
      prompt = option.name or option.id,
      format_item = function(choice)
        return describe(choice, option.currentValue)
      end,
    }, function(choice)
      if choice then session:set_option(option.id, choice.value) end
    end)
  end

  if #options == 0 then
    local modes = session:mode_choices()

    if #modes == 0 then return console.notify_now('Harness: this agent offers no options', 'info') end

    return console.select(modes, {
      prompt = 'Mode',
      format_item = function(mode)
        return (mode.name or mode.id) .. (mode.description and ('  ' .. mode.description) or '')
      end,
    }, function(mode)
      if mode then session:set_mode(mode.id) end
    end)
  end

  console.select(options, {
    prompt = 'Session option',
    format_item = function(option)
      local current = session:choice(option.id)
      return (option.name or option.id)
        .. ': '
        .. (current and (current.name or current.value) or tostring(option.currentValue))
    end,
  }, function(option)
    if option then Timer.schedule(function()
      pick_value(option)
    end) end
  end)
end

function transcript.bindings(view)
  local session, buf = view.session, view.bufnr
  local keys = settings.keymaps:get('transcript')

  return {
    {
      keys.interrupt,
      function()
        composer.interrupt(session)
      end,
      'Interrupt this session',
    },
    {
      keys.activate,
      function()
        if not transcript.activate(buf) then Window.get_current():normal('j') end
      end,
      'Open or fold what is under the cursor',
    },
    {
      keys.open,
      function()
        if not transcript.open_target(buf) then console.notify_now('Harness: nothing to open here', 'info') end
      end,
      'Open the file under the cursor in a new tab',
    },
    {
      keys.yank,
      function()
        local text, code = transcript.yank(buf)

        if text then
          local what = code and 'code block' or 'block'
          console.notify_now(string.format('Harness: yanked the %s (%d line%s)', what, #text, #text == 1 and '' or 's'))
        end
      end,
      'Yank the code block under the cursor, or the whole block',
    },
    {
      keys.next_turn,
      function()
        transcript.jump(1, buf)
      end,
      'Next turn',
    },
    {
      keys.previous_turn,
      function()
        transcript.jump(-1, buf)
      end,
      'Previous turn',
    },
    {
      keys.cycle_mode,
      function()
        session:cycle_mode()
      end,
      'Next session mode',
    },
    {
      keys.plan,
      function()
        view:toggle_plan()
      end,
      'Show or hide the plan',
    },
    {
      keys.diff,
      function()
        local ok, why = transcript.show_edit(buf)

        if not ok then console.notify_now('Harness: no edit to show: ' .. why, 'info') end
      end,
      'Open the edit under the cursor in vgit',
    },
    {
      keys.git_diff,
      function()
        local ok, why = transcript.git_diff(buf)

        if not ok then console.notify_now('Harness: no git diff to show: ' .. why, 'info') end
      end,
      'Open the git diff of the file under the cursor in vgit',
    },
    {
      keys.changes,
      function()
        local ok, why = transcript.show_changes(view)

        if not ok then console.notify_now('Harness: no changes to show: ' .. why, 'info') end
      end,
      'Open every file this session changed in vgit',
    },
    {
      keys.options,
      function()
        transcript.pick_option(session)
      end,
      'Session options: mode, model, …',
    },
  }
end

return transcript
