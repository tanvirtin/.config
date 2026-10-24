local lazy = require('core.lazy')

local hub = lazy('harness.hub')
local vgit = lazy('harness.vgit')
local fences = lazy('core.fences')
local Timer = require('core.Timer')
local async = lazy('harness.async')
local core_text = lazy('core.text')
local event = require('core.event')
local Buffer = require('core.Buffer')
local Object = require('core.Object')
local Window = require('core.Window')
local follow = lazy('harness.follow')
local keymap = require('core.keymap')
local edits = lazy('harness.ui.edits')
local register = lazy('core.register')
local console = require('core.console')
local links = require('harness.ui.links')
local display = lazy('harness.ui.display')
local winbar = require('harness.ui.winbar')
local composer = lazy('harness.ui.composer')
local settings = require('harness.settings')
local Renderer = lazy('ui.markdown.Renderer')
local Block = lazy('harness.transcript.Block')
local theme = lazy('harness.transcript.theme')
local Document = require('harness.ui.Document')
local hit_test = require('harness.ui.hit_test')
local PlanPanel = require('harness.ui.PlanPanel')
local Following = require('harness.ui.Following')
local code_blocks = lazy('harness.ui.code_blocks')
local actions = require('harness.transcript.actions')
local sticky_bottom = require('harness.ui.sticky_bottom')
local BlockBuilder = require('harness.transcript.BlockBuilder')
local Layout = require('harness.transcript.calculators.Layout')
local permission_prompt = require('harness.ui.permission_prompt')
local EVENT, NOTICE = require('harness.types.events').KIND, require('harness.types.events').NOTICE

actions.bind('diff', function(view)
  return edits.show_edit(view)
end)

local TranscriptView = Object:extend()

TranscriptView.FILETYPE = 'harness'

TranscriptView.FILE_CATEGORY = {
  [Block.CATEGORY.read] = true,
  [Block.CATEGORY.edit] = true,
  [Block.CATEGORY.delete] = true,
  [Block.CATEGORY.move] = true,
}

TranscriptView.WINDOW_OPTIONS = {
  wrap = true,
  linebreak = true,
  breakindent = true,
  breakindentopt = 'list:-1',
  number = false,
  relativenumber = false,
  list = false,
  conceallevel = 2,
  concealcursor = '',
  foldmethod = 'expr',
  foldexpr = 'v:lua.require\'harness.ui.transcript\'.foldexpr()',
  foldtext = 'v:lua.require\'harness.ui.transcript\'.foldtext()',
  foldlevel = 0,
  foldenable = true,
  fillchars = 'fold: ,eob: ',
}

TranscriptView.LIST_PATTERN = [[^>\s\+\|^\s*[-*+]\s\+\|^\s*\d\+[.)]\s\+]]

TranscriptView.FOLD_OPTIONS = { 'foldexpr', 'foldtext', 'foldlevel', 'foldenable', 'foldmethod' }

function TranscriptView.buffer_name(session)
  return string.format('harness://%s %s', session.key, session.title or 'untitled')
end

function TranscriptView.turn_started(session)
  for i = #session.history, 1, -1 do
    local kind = session.history[i].kind

    if kind == EVENT.prompt or kind == EVENT.user then return session.times[i] end
  end
end

function TranscriptView:constructor(session, opts)
  opts = opts or {}

  local buffer = Buffer():create(true, true)

  buffer:set_option('bufhidden', 'hide')
  buffer:set_option('modifiable', false)
  buffer:set_option('filetype', TranscriptView.FILETYPE)
  buffer:set_option('formatlistpat', TranscriptView.LIST_PATTERN)
  pcall(buffer.set_name, buffer, TranscriptView.buffer_name(session))

  local document = Document(buffer.bufnr):attach()

  return {
    session = session,
    buffer = buffer,
    bufnr = buffer.bufnr,
    document = document,
    source_win = opts.source_win,
    source_buf = opts.source_buf,
    timer = Timer(),
    pacer = Timer(),
    plan = PlanPanel(),
    frame = 1,
    cache = {},
    layout = nil,
    edits = session.edits,
    dirty = true,
    landing = nil,
    following = Following(TranscriptView.reserve),
    scheduled = false,
    disposed = false,
  }
end

function TranscriptView:windows()
  if not self.buffer:is_valid() then return {} end

  return self.buffer:get_windows()
end

function TranscriptView:is_visible()
  return #self:windows() > 0
end

function TranscriptView:sticky(window)
  local top = window:get_visible_range()

  return Layout.prompt_above(self.document.blocks, top)
end

function TranscriptView:plan_window()
  local current = Window.get_current()

  if current:get_buffer().bufnr == self.bufnr then return current end

  for _, window in ipairs(Window.list_tab()) do
    if window:get_buffer().bufnr == self.bufnr then return window end
  end
end

function TranscriptView:update_plan()
  self.plan:update(self.session.history, self:plan_window())
end

function TranscriptView:toggle_plan()
  self.plan:toggle(self.session.history, self:plan_window())
end

function TranscriptView:set_winbar(window)
  local text = winbar.transcript(self.session, self:sticky(window), window:get_width())

  if window:get_option('winbar') ~= text then window:set_option('winbar', text) end
end

function TranscriptView:style(window)
  self:set_winbar(window)

  for option, value in pairs(TranscriptView.WINDOW_OPTIONS) do
    if not option:find('^fold') then window:set_option(option, value) end
  end

  for _, option in ipairs(TranscriptView.FOLD_OPTIONS) do
    local value = TranscriptView.WINDOW_OPTIONS[option]

    if window:get_option(option) ~= value then window:set_option(option, value) end
  end
end

TranscriptView.ACTIVE = require('harness.session.Subagents').ACTIVE

function TranscriptView.active_subagents(session)
  local active = {}

  for _, child in pairs(session.children or {}) do
    if child.tool and TranscriptView.ACTIVE[child.state] then active[child.tool] = true end
  end

  return active
end

function TranscriptView:state()
  local session = self.session

  return {
    running = session:running(),
    loading = session:loading(),
    frame = self.frame,
    started = TranscriptView.turn_started(session),
    queue = session:queued(),
    waiting = session:waiting(),
    asks = permission_prompt.asks_of(session),
    active = TranscriptView.active_subagents(session),
  }
end

function TranscriptView:render()
  self.scheduled = false
  self.dirty = false
  self.rendered = Timer.now()

  if not self.buffer:is_valid() then return end

  local session = self.session
  local before = self.buffer:get_line_count()
  local windows = self:windows()
  local loading = session:loading()
  local tails = {}

  self:adopt(windows)

  -- see a scroll made since the last frame before writing can pull the window back
  self.following:track(windows)

  for _, window in ipairs(windows) do
    if not loading then tails[#tails + 1] = { window = window, on_last = window:get_cursor()[1] >= before } end
  end

  local state = self:state()

  if not loading or #self.document.blocks == 0 then
    self:write(loading and {} or session.history, state)
  else
    self.document:tick(state)
  end

  for _, window in ipairs(windows) do
    self:set_winbar(window)
  end

  local landing = self.landing

  -- only text arriving moves a window, and only while the reader is at the edge
  local grew = self.buffer:get_line_count() > before

  if landing ~= nil and not loading then
    self.landing = nil

    for _, window in ipairs(windows) do
      if landing == true or landing == window.win_id then self:land(window) end
    end
  elseif grew then
    for _, tail in ipairs(tails) do
      if self.following:follows(tail.window) then self.following:glide(tail.window, tail.on_last) end
    end
  end

  self.following:track(windows)
  self:settle()
  self:update_plan()

  if (state.running or state.loading or next(state.active)) and not self.timer:is_active() then
    self.timer:every(settings.transcript:get('tick_ms'), function()
      self:tick()
    end)
  end
end

function TranscriptView:diff_layout()
  local layout = vgit.layout(settings.transcript:get('diff_layout'))

  if layout ~= 'split' then return layout end

  return layout .. ':' .. tostring(self.document:text_width())
end

function TranscriptView:write(history, state)
  local session = self.session
  local layout = self:diff_layout()

  if layout ~= self.layout then
    self.cache = {}
    self.layout = layout
  end

  self.document:write(
    BlockBuilder.build(history, session.title, {
      times = session.times,
      dir = session.dir,
      running = state.running,
      cache = self.cache,
      index = session.log and session.log.turns,
      edits = self.edits,
      groups = true,
      live_turns = not self.expanded and settings.transcript:get('live_turns') or nil,
      width = self.document:text_width(),
    }),
    state
  )
end

function TranscriptView.reserve(window)
  if composer.is_open() then return 0 end

  return sticky_bottom.margin(window)
end

function TranscriptView:keep_end()
  if not self.session:loading() then self.following:keep_end(self:windows()) end
end

function TranscriptView:hold_end()
  if not self.session:loading() then self.following:hold_end(self:windows()) end
end

function TranscriptView:settle()
  if self.settling then return end

  self.settling = true

  Timer.schedule(function()
    self.settling = false

    if not self.disposed and self.buffer:is_valid() then self:keep_end() end
  end)
end

function TranscriptView:_step()
  if not self.buffer:is_valid() then return self.timer:stop() end

  local active = TranscriptView.active_subagents(self.session)

  if not self.session:running() and not self.session:loading() and not next(active) then
    self.timer:stop()
    return self:render()
  end

  self.frame = self.frame + 1

  for _, window in ipairs(self:windows()) do
    self:set_winbar(window)
  end

  self.document:tick({ frame = self.frame, active = active, loading = self.session:loading() })
end

function TranscriptView:tick()
  local ok, err = pcall(self._step, self)

  if not ok then
    self.timer:stop()
    console.notify_now('Harness: the transcript stopped animating: ' .. tostring(err), 'warn')
  end
end

function TranscriptView:announce_waiting()
  local waiting = self.session:waiting()

  if #waiting == 0 then return end

  for _, window in ipairs(Window.list_tab()) do
    if window:get_buffer().bufnr == self.bufnr then return end
  end

  local what = waiting[1].title or waiting[1].tool or 'a tool'

  console.notify(string.format('Harness %s: waiting for permission: %s', self.session.key, what), 'warn')
end

-- a window that came to show the transcript without BufWinEnter (a split of it,
-- another tab) has never been landed, so nothing would follow the stream in it
function TranscriptView:adopt(windows)
  for _, window in ipairs(windows) do
    if not self.following:settled(window) then self:land(window) end
  end
end

function TranscriptView:watch()
  local windows = self:windows()

  self:adopt(windows)

  for _, window in ipairs(windows) do
    self:set_winbar(window)
  end

  -- note where the reader is, and put back only a top line a resize moved
  self.following:hold_end(windows)
end

function TranscriptView:on_event(update)
  local kind = update.kind

  if kind == EVENT.title then pcall(self.buffer.set_name, self.buffer, TranscriptView.buffer_name(self.session)) end
  if kind == NOTICE.reset then self.cache = {} end

  if kind == NOTICE.loaded then
    self.landing = true
    self.cache = {}
    self.edits:reset()
  end
  if kind == NOTICE.waiting then self:announce_waiting() end

  self:schedule()
end

function TranscriptView:schedule()
  self.dirty = true

  if self.scheduled then return end

  self.scheduled = true

  local function render()
    if self.scheduled and not self.disposed then self:render() end
  end

  local wait = self.rendered and settings.transcript:get('frame_ms') - (Timer.now() - self.rendered) or 0

  if wait > 0 then
    self.pacer:after(wait, render)
  else
    Timer.schedule(render)
  end
end

function TranscriptView:on_show()
  self.buffer:set_option('buflisted', true)
  self:style(Window.get_current())

  if self.document:stale() then
    self.document:reset()
    self.dirty = true
  end

  if self:diff_layout() ~= self.layout then self.dirty = true end

  if self.opening then return end

  local window = Window.get_current()

  if self.following:arrive(window) then
    self:enter(window)
  elseif self.dirty then
    self:render()
  else
    self.document:decorate_visible()
  end
end

function TranscriptView:enter(window)
  self.landing = window.win_id

  if self.dirty then
    self:render()
  else
    self.landing = nil
    self:land(window)
  end
end

function TranscriptView:land(window)
  self.following:land(window, function()
    self.document:decorate_visible()
  end)
  self:settle()
end

function TranscriptView:expand()
  if self.expanded then return false end

  self.expanded = true
  self.dirty = true
  self:render()

  return true
end

function TranscriptView:show_in(window)
  self.opening = true
  window:set_buffer(self.buffer)
  self.opening = false
  self:enter(window)
end

function TranscriptView:map(lhs, callback, desc, opts)
  keymap.buffer_set(
    self.buffer,
    { mode = opts and opts.mode or 'n', key = lhs, desc = desc, expr = opts and opts.expr },
    callback
  )
end

function TranscriptView:bind(actions)
  local session = self.session

  for _, lhs in ipairs(settings.keymaps:get('transcript').write) do
    self:map(lhs, function()
      composer.open(session, { insert = true })
    end, 'Write to this session')
  end

  for _, binding in ipairs(actions) do
    self:map(binding[1], binding[2], binding[3], binding[4])
  end

  for _, key in ipairs(permission_prompt.KEYS) do
    self:map(key, function()
      if not permission_prompt.choice(session, key) then return key end

      Timer.schedule(function()
        permission_prompt.answer(session, key)
      end)

      return ''
    end, 'Answer the agent\'s question with choice ' .. key, { expr = true })
  end
end

function TranscriptView:resolve(kind, text)
  local target = links.resolve(kind, text, self.session.dir)

  return target and { icon = links.icon(target) } or nil
end

TranscriptView.SUMMED = { tool = 'tool', message = 'reply' }

TranscriptView.MANY = { tool = 'tools', reply = 'replies' }

function TranscriptView:_children_in(first, last)
  local counts = {}

  for _, block in ipairs(self.document.blocks) do
    if block.start >= first and block.start < last then
      if not block.depth then return nil end

      local noun = TranscriptView.SUMMED[block.kind]

      if noun then counts[noun] = (counts[noun] or 0) + 1 end
    end
  end

  local parts = {}

  for _, noun in ipairs({ 'tool', 'reply' }) do
    local n = counts[noun]

    if n then parts[#parts + 1] = core_text.plural(n, noun, TranscriptView.MANY[noun]) end
  end

  return #parts > 0 and table.concat(parts, ' · ') or nil
end

function TranscriptView:_rails(row, last)
  local document = self.document
  local block = document:block_at(row)
  local depth = block and (block.depth or 0) + (row > block.start and 1 or 0) or 0

  if depth == 0 then return '  ' end

  local tail = document:block_at(last)
  local closes = tail and tail.last_child and last >= tail.start + #tail.lines and row == block.start

  return string.rep(theme.GUTTER, depth - 1) .. (closes and theme.BRANCH_END or theme.GUTTER)
end

function TranscriptView:fold_text(first, last)
  local children = self:_children_in(first - 1, last)
  local text = '⋯ ' .. (children or core_text.plural(last - first + 1, 'more line'))

  return { { self:_rails(first - 1, last - 1), 'UiMuted' }, { text, 'UiMuted' } }
end

function TranscriptView:_target_at(window)
  local cursor = window:get_cursor()
  local row, col = cursor[1] - 1, cursor[2]
  local document, dir = self.document, self.session.dir
  local kind, text = document.renderer:inline_at(row, col)

  if kind then
    local target = links.resolve(kind, text, dir)

    if target then return target end
  end

  local block = document:block_at(row)

  if not block then return nil end

  if block.kind == Block.KIND.diff then
    local line = Block.file_line(block, row)
    local target = links.resolve(Renderer.INLINE.link, block.path, dir)

    if target then return { path = target.path, line = line } end
  end

  if block.kind == Block.KIND.tool then
    local location = block.locations and block.locations[1]

    if location then
      local target = links.resolve(Renderer.INLINE.link, location.path, dir)

      if target then return { path = target.path, line = location.line or target.line } end
    end

    if TranscriptView.FILE_CATEGORY[block.category] and block.argument then
      return links.resolve(Renderer.INLINE.link, block.argument, dir)
    end
  end
end

function TranscriptView:jump(direction)
  local window = Window.get_current()
  local row = window:get_cursor()[1] - 1
  local rows = {}

  for _, block in ipairs(self.document.blocks) do
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

function TranscriptView:_toggle_at(window, fold_row, row)
  window:set_cursor({ fold_row, 0 })
  window:normal(window:fold_closed(fold_row) and 'zo' or 'zc')
  window:set_cursor({ row, 0 })

  return self
end

function TranscriptView:activate()
  local window = Window.get_current()
  local row = window:get_cursor()[1]

  if window:fold_closed(row) then
    window:normal('zo')
    return true
  end

  if links.open(self:_target_at(window)) then return true end

  if window:fold_level(row) > 0 then
    window:normal('zc')
    return true
  end

  local block = self.document:block_at(row - 1)

  if block and block.grouped then
    self:_toggle_at(window, block.finish + 1, row)
    return true
  end

  if block and block.kind == Block.KIND.collapsed then
    self:expand()
    window:set_cursor({ 1, 0 })
    return true
  end

  if block and block.folds and block.folds[1] then
    self:_toggle_at(window, block.start + block.folds[1][1] + 1, row)
    return true
  end

  return false
end

function TranscriptView:open_target()
  return links.open(self:_target_at(Window.get_current())) or false
end

function TranscriptView:run_block_action(key)
  local window = Window.get_current()
  local block = self.document:block_at(window:get_cursor()[1] - 1)

  return actions.run(self, block, key)
end

function TranscriptView:path_at()
  local target = self:_target_at(Window.get_current())

  return target and target.path or nil
end

function TranscriptView:git_diff()
  local path = self:path_at()

  if not path then return false, 'no file here' end

  return vgit.git_diff(path)
end

function TranscriptView:fork_point(row)
  local blocks = self.document.blocks
  local block = self.document:block_at(row)

  if not block then return nil end

  local from = block.kind == Block.KIND.prompt and block.index - 1 or block.index

  for i = from, 1, -1 do
    local candidate = blocks[i]

    if candidate and candidate.kind == Block.KIND.message and not candidate.depth and candidate.message_id ~= nil then
      return candidate.message_id
    end
  end
end

function TranscriptView:fork()
  local session = self.session

  if not session:can('fork') then return false, 'this agent cannot fork sessions' end

  local at_message = session:can('fork_at_message')
  local message_id = at_message and self:fork_point(Window.get_current():get_cursor()[1] - 1)

  if not at_message then
    console.notify_now('Harness: this agent forks a whole session; forking from the latest message')
  elseif not message_id then
    console.notify_now('Harness: no reply before this point; forking from the latest message')
  end

  hub.fork(session, message_id):on_complete(function(err, forked)
    Timer.schedule(function()
      if err then return console.notify_now('Harness: could not fork: ' .. tostring(err), 'warn') end

      display.open(forked)
    end)
  end)
  async.drain()

  return true
end

function TranscriptView:yank_token(block)
  local window = Window.get_current()
  local row = window:get_cursor()[1] - 1
  local col = window:get_cursor()[2]
  local hit = hit_test.at(block, row, col)

  if hit and hit.text then
    register.set(hit.text)

    return hit.text, hit.kind or 'token'
  end
end

function TranscriptView:yank_block(block, name)
  if not block then return nil end

  local row = Window.get_current():get_cursor()[1] - 1

  if block.kind == Block.KIND.diff and block.edit then
    local patch = vgit.patch_text(block.edit)

    register.set(patch, name)

    return patch, 'patch'
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

  return text, first and 'code block' or 'block'
end

function TranscriptView:yank(name)
  local row = Window.get_current():get_cursor()[1] - 1
  local block = self.document:block_at(row)
  local handled, text, code = self:run_block_action('yank')

  if handled then return text, code end

  return self:yank_block(block, name)
end

function TranscriptView:_describe_choice(choice, current)
  local mark = choice.value == current and theme.CURRENT_ICON or '  '

  return mark .. (choice.name or choice.value) .. (choice.description and ('  ' .. choice.description) or '')
end

function TranscriptView:pick_model()
  local session = self.session
  local option = session:option('model')

  if not option or (option.kind and option.kind ~= 'select') then
    return console.notify_now('Harness: this agent offers no model option', 'info')
  end

  console.select(option.choices, {
    prompt = option.name or 'Model',
    format_item = function(choice)
      return self:_describe_choice(choice, option.current)
    end,
  }, function(choice)
    if choice then session:set_option(option.id, choice.value) end
  end)
end

function TranscriptView.report(ok, why)
  if not ok and why then console.notify_now('Harness: ' .. why, 'info') end

  return ok
end

function TranscriptView:bindings()
  local session, report = self.session, TranscriptView.report
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
        if not self:activate() then Window.get_current():normal('j') end
      end,
      'Open or fold what is under the cursor',
    },
    {
      keys.bottom,
      function()
        local count = keymap.count()
        local window = Window.get_current()

        if count > 1 then return window:normal(count .. 'G') end

        self:land(window)
      end,
      'Go to the end, leaving room under the newest line',
    },
    {
      keys.open,
      function()
        local handled, ok = self:run_block_action('open')
        if not handled then ok = self:open_target() end
        if not ok then console.notify_now('Harness: nothing to open here', 'info') end
      end,
      'Open the file under the cursor in a new tab',
    },
    {
      keys.yank,
      function()
        local text, what = self:yank()

        if text then
          what = what or 'block'

          console.notify_now(string.format('Harness: yanked the %s (%d line%s)', what, #text, #text == 1 and '' or 's'))
        end
      end,
      'Yank the code block under the cursor, or the whole block',
    },
    {
      keys.next_turn,
      function()
        self:jump(1)
      end,
      'Next turn',
    },
    {
      keys.previous_turn,
      function()
        self:jump(-1)
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
        self:toggle_plan()
      end,
      'Show or hide the plan',
    },
    {
      keys.diff,
      function()
        local handled, ok, why = self:run_block_action('diff')
        if not handled then
          ok, why = edits.show_edit(self)
        end
        report(ok, why)
      end,
      'Open the edit under the cursor in vgit',
    },
    {
      keys.git_diff,
      function()
        report(self:git_diff())
      end,
      'Open the git diff of the file under the cursor in vgit',
    },
    {
      keys.changes,
      function()
        report(edits.show_changes(self))
      end,
      'Open every file this session changed in vgit',
    },
    {
      keys.block_next,
      function()
        report(code_blocks.jump(self, 1))
      end,
      'Next code block',
      { mode = { 'n', 'x' } },
    },
    {
      keys.block_previous,
      function()
        report(code_blocks.jump(self, -1))
      end,
      'Previous code block',
      { mode = { 'n', 'x' } },
    },
    {
      keys.block_inner,
      function()
        code_blocks.select(self, false)
      end,
      'Inside the code block',
      { mode = { 'o', 'x' } },
    },
    {
      keys.block_around,
      function()
        code_blocks.select(self, true)
      end,
      'The code block with its fences',
      { mode = { 'o', 'x' } },
    },
    {
      keys.insert,
      function()
        report(code_blocks.insert(self))
      end,
      'Insert the code block below the cursor in your code',
    },
    {
      keys.apply,
      function()
        report(code_blocks.apply(self))
      end,
      'Ask the agent to apply the code block to your code',
    },
    {
      keys.revert,
      function()
        report(edits.revert(self))
      end,
      'Revert the edit under the cursor, or this turn\'s edits, after a preview in vgit',
    },
    {
      keys.quickfix,
      function()
        report(edits.quickfix(self, edits.SCOPE.turn))
      end,
      'Send this turn\'s edits to the quickfix list',
    },
    {
      keys.quickfix_session,
      function()
        report(edits.quickfix(self, edits.SCOPE.session))
      end,
      'Send every edit of this session to the quickfix list',
    },
    {
      keys.fork,
      function()
        report(self:fork())
      end,
      'Fork the session from the reply under the cursor (or the one before this prompt)',
    },
    {
      keys.model,
      function()
        self:pick_model()
      end,
      'Session model',
    },
  }
end

function TranscriptView:mount(callbacks)
  callbacks = callbacks or {}

  self.document.renderer.resolve = function(kind, text)
    return self:resolve(kind, text)
  end

  self.unsubscribe = self.session:subscribe(function(update)
    self:on_event(update)
  end)
  self.unwatch = settings.composer:on_change(function()
    if not self.disposed then self:keep_end() end
  end)

  local function relayout()
    if not self.disposed and self:diff_layout() ~= self.layout then self:schedule() end
  end

  self.group = event.augroup('harness.transcript.' .. self.bufnr)
  self.group.on('BufWinEnter', function()
    self:on_show()
  end, { buffer = self.buffer })
  self.group.on('WinClosed', function(args)
    local win_id = tonumber(args.match)

    if win_id then self.following:forget(win_id) end
  end)
  self.group.on({ 'WinResized', 'TabEnter' }, function()
    self.document:resize()
    self:hold_end()
    self:update_plan()
    relayout()
  end)
  self.group.on('BufWinLeave', function()
    self.following:track(self:windows())

    Timer.schedule(function()
      if not self.disposed then self:update_plan() end
    end)
  end, { buffer = self.buffer })
  self.group.on('BufEnter', function()
    if callbacks.on_enter then callbacks.on_enter(self) end
  end, { buffer = self.buffer })
  self.group.on({ 'BufUnload', 'BufDelete', 'BufWipeout' }, function()
    self:dispose()
    if callbacks.on_dispose then callbacks.on_dispose(self) end
  end, { buffer = self.buffer, once = true })

  follow.start(self.session, {
    visible = function()
      return self.buffer:is_valid() and self:is_visible()
    end,
  })

  -- WinScrolled is not delivered everywhere, so the window is watched for the
  -- user's own scrolling instead of waiting for an event
  self.watcher = Timer():every(settings.transcript:get('watch_ms'), function()
    if not self.disposed and self:is_visible() then self:watch() end
  end)

  self:render()

  return self
end

function TranscriptView:dispose()
  if self.disposed then return end

  self.disposed = true

  if self.unsubscribe then self.unsubscribe() end
  if self.unwatch then self.unwatch() end

  follow.stop(self.session)
  self.plan:hide()
  self.timer:close()
  self.pacer:close()
  if self.watcher then self.watcher:close() end

  if self.group then self.group.dispose() end

  local buffer = self.buffer

  Timer.schedule(function()
    if Buffer.exists(buffer.bufnr) then pcall(buffer.delete, buffer, { force = true }) end
  end)
end

return TranscriptView
