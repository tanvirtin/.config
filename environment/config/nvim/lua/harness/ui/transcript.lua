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
local code_blocks = require('harness.ui.code_blocks')
local buffers = require('core.buffers')
local console = require('core.console')
local display = require('harness.ui.display')
local fences = require('core.fences')
local links = require('harness.ui.links')
local permission_prompt = require('harness.ui.permission_prompt')
local register = require('core.register')
local settings = require('harness.settings')
local core_text = require('core.text')
local theme = require('harness.transcript.theme')
local vgit = require('harness.vgit')
local winbar = require('harness.ui.winbar')

local composer = lazy('harness.ui.composer')
local async = lazy('harness.async')
local hub = lazy('harness.hub')

local transcript = {}

transcript.FILETYPE = TranscriptView.FILETYPE

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

local MANY = { tool = 'tools', reply = 'replies' }

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

    if n then parts[#parts + 1] = core_text.plural(n, noun, MANY[noun]) end
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
  local text = '⋯ ' .. (children or core_text.plural(hidden, 'more line'))

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

function transcript.report(ok, why)
  if not ok and why then console.notify_now('Harness: ' .. why, 'info') end

  return ok
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

local function reply_with_id(block)
  return block and block.kind == Block.KIND.message and not block.depth and block.message_id ~= nil
end

function transcript.fork_point(view, row)
  local blocks = view.document.blocks
  local block = view.document:block_at(row)

  if not block then return nil end

  local from = block.kind == Block.KIND.prompt and block.index - 1 or block.index

  for i = from, 1, -1 do
    if reply_with_id(blocks[i]) then return blocks[i].message_id end
  end
end

function transcript.fork(buf)
  local view = view_for(buf)

  if not view then return false, 'no session here' end

  local session = view.session

  if not session.connection:can_fork() then return false, 'this agent cannot fork sessions' end

  local message_id = transcript.fork_point(view, Window.get_current():get_cursor()[1] - 1)

  if not message_id then console.notify_now('Harness: no reply before this point; forking from the latest message') end

  hub.fork(session, message_id):on_complete(function(err, forked)
    Timer.schedule(function()
      if err then return console.notify_now('Harness: could not fork: ' .. tostring(err), 'warn') end

      transcript.open(forked)
    end)
  end)
  async.drain()

  return true
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
  local mark = choice.value == current and theme.CURRENT_ICON or '  '

  return mark .. (choice.name or choice.value) .. (choice.description and ('  ' .. choice.description) or '')
end

function transcript.pick_model(session)
  local option = session:option('model')

  if not option or (option.type and option.type ~= 'select') then
    return console.notify_now('Harness: this agent offers no model option', 'info')
  end

  console.select(session.choices(option), {
    prompt = option.name or 'Model',
    format_item = function(choice)
      return describe(choice, option.currentValue)
    end,
  }, function(choice)
    if choice then session:set_option(option.id, choice.value) end
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
        transcript.report(transcript.show_edit(buf))
      end,
      'Open the edit under the cursor in vgit',
    },
    {
      keys.git_diff,
      function()
        transcript.report(transcript.git_diff(buf))
      end,
      'Open the git diff of the file under the cursor in vgit',
    },
    {
      keys.changes,
      function()
        transcript.report(transcript.show_changes(view))
      end,
      'Open every file this session changed in vgit',
    },
    {
      keys.block_next,
      function()
        transcript.report(code_blocks.jump(view, 1))
      end,
      'Next code block',
      { mode = { 'n', 'x' } },
    },
    {
      keys.block_previous,
      function()
        transcript.report(code_blocks.jump(view, -1))
      end,
      'Previous code block',
      { mode = { 'n', 'x' } },
    },
    {
      keys.block_inner,
      function()
        code_blocks.select(view, false)
      end,
      'Inside the code block',
      { mode = { 'o', 'x' } },
    },
    {
      keys.block_around,
      function()
        code_blocks.select(view, true)
      end,
      'The code block with its fences',
      { mode = { 'o', 'x' } },
    },
    {
      keys.insert,
      function()
        transcript.report(code_blocks.insert(view))
      end,
      'Insert the code block below the cursor in your code',
    },
    {
      keys.apply,
      function()
        transcript.report(code_blocks.apply(view))
      end,
      'Ask the agent to apply the code block to your code',
    },
    {
      keys.fork,
      function()
        transcript.report(transcript.fork(buf))
      end,
      'Fork the session from the reply under the cursor (or the one before this prompt)',
    },
    {
      keys.model,
      function()
        transcript.pick_model(session)
      end,
      'Session model',
    },
  }
end

return transcript
