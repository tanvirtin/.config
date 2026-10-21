local lazy = require('core.lazy')

local Buffer = require('core.Buffer')
local BlockBuilder = require('harness.transcript.BlockBuilder')
local Layout = require('harness.transcript.calculators.Layout')
local Document = require('harness.ui.document')
local EVENT, NOTICE = require('harness.events').KIND, require('harness.events').NOTICE
local Object = require('core.Object')
local PlanPanel = require('harness.ui.PlanPanel')
local Timer = require('core.Timer')
local Window = require('core.Window')
local console = require('core.console')
local event = require('core.event')
local keymap = require('core.keymap')
local links = require('harness.ui.links')
local permission_prompt = require('harness.ui.permission_prompt')
local settings = require('harness.settings')
local winbar = require('harness.ui.winbar')

local composer = lazy('harness.ui.composer')
local follow = lazy('harness.follow')

local TranscriptView = Object:extend()

TranscriptView.FILETYPE = 'harness'

TranscriptView.WINDOW_OPTIONS = {
  wrap = true,
  linebreak = true,
  number = false,
  relativenumber = false,
  conceallevel = 2,
  concealcursor = '',
  foldmethod = 'expr',
  foldexpr = 'v:lua.require\'harness.ui.transcript\'.foldexpr()',
  foldtext = 'v:lua.require\'harness.ui.transcript\'.foldtext()',
  foldlevel = 0,
  foldenable = true,
  fillchars = 'fold: ,eob: ',
}

TranscriptView.FOLD_OPTIONS = { 'foldexpr', 'foldtext', 'foldlevel', 'foldenable', 'foldmethod' }

function TranscriptView.buffer_name(session)
  return string.format('harness://%s %s', session.key, session.title or 'untitled')
end

function TranscriptView.agent_label(session)
  local name = session.agent and session.agent.name or 'agent'

  return name:sub(1, 1):upper() .. name:sub(2)
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
    plan = PlanPanel(),
    frame = 1,
    cache = {},
    dirty = true,
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
  local text = winbar.transcript(self.session, self:sticky(window))

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

function TranscriptView.to_bottom(window)
  if window:is_valid() then window:set_cursor({ window:get_buffer():get_line_count(), 0 }) end
end

function TranscriptView:state()
  local session = self.session

  return {
    running = session:running(),
    frame = self.frame,
    started = TranscriptView.turn_started(session),
    agent = TranscriptView.agent_label(session),
    queue = session:queued(),
    waiting = session:waiting(),
    asks = permission_prompt.asks_of(session),
    choices = permission_prompt.CHOICES,
  }
end

function TranscriptView:render()
  self.scheduled = false
  self.dirty = false

  if not self.buffer:is_valid() then return end

  local session = self.session
  local last = self.buffer:get_line_count()
  local windows = self:windows()
  local following = vim.tbl_filter(function(window)
    return window:get_cursor()[1] >= last
  end, windows)
  local state = self:state()

  self.document:write(
    BlockBuilder.build(session.history, session.title, {
      times = session.times,
      dir = session.dir,
      running = state.running,
      cache = self.cache,
      groups = true,
      live_turns = not self.expanded and settings.transcript:get('live_turns') or nil,
    }),
    state
  )

  for _, window in ipairs(windows) do
    self:set_winbar(window)
  end

  for _, window in ipairs(following) do
    TranscriptView.to_bottom(window)
  end

  self:update_plan()

  if state.running and not self.timer:is_active() then
    self.timer:every(settings.transcript:get('tick_ms'), function()
      self:tick()
    end)
  end
end

function TranscriptView:_step()
  if not self.buffer:is_valid() then return self.timer:stop() end

  if not self.session:running() then
    self.timer:stop()
    return self:render()
  end

  self.frame = self.frame + 1
  self.document:tick({ frame = self.frame })
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

  console.notify(string.format('Harness %s is waiting for your permission: %s', self.session.key, what), 'warn')
end

function TranscriptView:on_event(update)
  local kind = update.kind

  if kind == EVENT.title then pcall(self.buffer.set_name, self.buffer, TranscriptView.buffer_name(self.session)) end
  if kind == NOTICE.reset then self.cache = {} end
  if kind == NOTICE.waiting then self:announce_waiting() end

  self.dirty = true

  if self.scheduled then return end

  self.scheduled = true
  Timer.schedule(function()
    self:render()
  end)
end

function TranscriptView:on_show()
  self.buffer:set_option('buflisted', true)
  self:style(Window.get_current())

  if self.document:stale() then
    self.document:reset()
    self.dirty = true
  end

  if self.opening then return end

  if self.dirty then
    self:render()
  else
    self.document:decorate_visible()
  end
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
  TranscriptView.to_bottom(window)

  if self.dirty then
    self:render()
  else
    self.document:decorate_visible()
  end
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
    self:map(binding[1], binding[2], binding[3])
  end

  for _, choice in ipairs(permission_prompt.CHOICES) do
    self:map(choice.key, function()
      if #permission_prompt.asks_of(session) == 0 then return choice.key end

      Timer.schedule(function()
        permission_prompt.answer(session, choice.kind)
      end)

      return ''
    end, choice.label .. ' (when the agent asks)', { expr = true })
  end
end

function TranscriptView:resolve(kind, text)
  local target = links.resolve(kind, text, self.session.dir)

  return target and { icon = links.icon(target) } or nil
end

function TranscriptView:mount(callbacks)
  callbacks = callbacks or {}

  self.document.renderer.resolve = function(kind, text)
    return self:resolve(kind, text)
  end

  self.unsubscribe = self.session:subscribe(function(update)
    self:on_event(update)
  end)

  self.group = event.augroup('harness.transcript.' .. self.bufnr)
  self.group.on('BufWinEnter', function()
    self:on_show()
  end, { buffer = self.buffer })
  self.group.on('WinScrolled', function()
    for _, window in ipairs(self:windows()) do
      self:set_winbar(window)
    end
  end)
  self.group.on({ 'WinResized', 'TabEnter' }, function()
    self:update_plan()
  end)
  self.group.on('BufWinLeave', function()
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

  self:render()

  return self
end

function TranscriptView:dispose()
  if self.disposed then return end

  self.disposed = true

  if self.unsubscribe then self.unsubscribe() end

  follow.stop(self.session)
  self.plan:hide()
  self.timer:close()
  self.document:dispose()

  if self.group then self.group.dispose() end

  local buffer = self.buffer

  Timer.schedule(function()
    if Buffer.exists(buffer.bufnr) then pcall(buffer.delete, buffer, { force = true }) end
  end)
end

return TranscriptView
