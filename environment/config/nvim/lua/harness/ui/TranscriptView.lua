local lazy = require('core.lazy')

local vgit = lazy('harness.vgit')
local Timer = require('core.Timer')
local core_text = lazy('core.text')
local event = require('core.event')
local Buffer = require('core.Buffer')
local Object = require('core.Object')
local Window = require('core.Window')
local follow = lazy('harness.follow')
local keymap = require('core.keymap')
local console = require('core.console')
local asks = require('harness.ui.asks')
local links = require('harness.ui.links')
local winbar = require('harness.ui.winbar')
local settings = require('harness.settings')
local theme = lazy('harness.transcript.theme')
local Document = require('harness.ui.Document')
local ASK = require('harness.types.events').ASK
local PlanPanel = require('harness.ui.PlanPanel')
local Following = require('harness.ui.Following')
local commands = lazy('harness.ui.transcript_commands')
local bindings = lazy('harness.ui.transcript_bindings')
local sticky_bottom = require('harness.ui.sticky_bottom')
local BlockBuilder = require('harness.transcript.BlockBuilder')
local Layout = require('harness.transcript.calculators.Layout')
local elicitation_actions = lazy('harness.ui.elicitation_actions')
local EVENT, NOTICE = require('harness.types.events').KIND, require('harness.types.events').NOTICE

local TranscriptView = Object:extend()

TranscriptView.FILETYPE = 'harness'

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

  local view = {
    session = session,
    buffer = buffer,
    bufnr = buffer.bufnr,
    document = document,
    composer = opts.composer,
    display = opts.display,
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
    following = nil,
    scheduled = false,
    disposed = false,
  }

  view.following = Following(function(window)
    return TranscriptView.reserve(view, window)
  end)

  return view
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
    asks = asks.asks_of(session),
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

function TranscriptView.reserve(view, window)
  if view.composer and view.composer.is_open() then return 0 end

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

  local why = waiting[1].kind == ASK.elicitation and 'waiting for your answer' or 'waiting for permission'

  console.notify(string.format('Harness %s: %s: %s', self.session.key, why, what), 'warn')
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
      if self.composer then self.composer.open(session, { insert = true, display = self.display }) end
    end, 'Write to this session')
  end

  for _, binding in ipairs(actions) do
    self:map(binding[1], binding[2], binding[3], binding[4])
  end

  local keys = vim.list_extend({ settings.keymaps:get('transcript').decline }, asks.KEYS)

  for _, key in ipairs(keys) do
    self:map(key, function()
      if not asks.choice(session, key) then return key end

      Timer.schedule(function()
        local action, prompt = asks.answer(session, key)

        if prompt and prompt.kind == ASK.elicitation then elicitation_actions.follow(self, prompt, action) end
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
  return commands.target_at(self, window)
end

function TranscriptView:jump(direction)
  return commands.jump(self, direction)
end

function TranscriptView:_toggle_at(window, fold_row, row)
  return commands.toggle_at(self, window, fold_row, row)
end

function TranscriptView:activate()
  return commands.activate(self)
end

function TranscriptView:open_target()
  return commands.open_target(self)
end

function TranscriptView:run_block_action(key)
  return commands.run_block_action(self, key)
end

function TranscriptView:path_at()
  return commands.path_at(self)
end

function TranscriptView:git_diff()
  return commands.git_diff(self)
end

function TranscriptView:fork_point(row)
  return commands.fork_point(self, row)
end

function TranscriptView:fork()
  return commands.fork(self)
end

function TranscriptView:yank_token(block)
  return commands.yank_token(self, block)
end

function TranscriptView:yank_block(block, name)
  return commands.yank_block(self, block, name)
end

function TranscriptView:yank(name)
  return commands.yank(self, name)
end

function TranscriptView:_describe_choice(choice, current)
  return commands.describe_choice(self, choice, current)
end

function TranscriptView:pick_model()
  return commands.pick_model(self)
end

function TranscriptView:show_permissions()
  return commands.show_permissions(self)
end

function TranscriptView.report(ok, why)
  if not ok and why then console.notify_now('Harness: ' .. why, 'info') end

  return ok
end

function TranscriptView:bindings()
  return bindings.bindings(self)
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
