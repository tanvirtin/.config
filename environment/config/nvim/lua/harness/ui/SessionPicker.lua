local lazy = require('core.lazy')

local View = lazy('ui.View')
local text = lazy('core.text')
local hub = lazy('harness.hub')
local glitch = lazy('ui.glitch')
local Timer = lazy('core.Timer')
local event = lazy('core.event')
local motion = lazy('ui.motion')
local Buffer = lazy('core.Buffer')
local Window = lazy('core.Window')
local agent = lazy('harness.agent')
local async = lazy('harness.async')
local schema = lazy('nvim_mcp.schema')
local Component = lazy('ui.Component')
local notice = lazy('harness.ui.notice')
local Surface = lazy('surfaces.Surface')
local catalog = lazy('ui.pixel.catalog')
local winbar = lazy('harness.ui.winbar')
local display = lazy('harness.ui.display')
local Element = lazy('ui.elements.Element')
local theme = lazy('harness.transcript.theme')
local indicators = lazy('ui.pixel.indicators')
local LayoutSpec = lazy('ui.layout.LayoutSpec')
local transcript = lazy('harness.ui.transcript')
local keymaps = lazy('harness.settings.keymaps')
local confirm = lazy('harness.settings.sessions')
local session_types = lazy('harness.types.session')
local session_search = lazy('harness.ui.session_search')

local PROMPT = '> '
local MODES = { 'sessions', 'agents' }
local EVENT = require('harness.types.events').KIND
local STATE_ROLE = { waiting = 'warn', running = 'accent', idle = 'muted' }
local STATE_INDICATOR = { waiting = 'waiting', running = 'busy', idle = 'idle' }
local SECTION = { live = 'Live', recent = 'Recent' }
local TUNE_MS, TUNE_FRAME_MS, TUNE_DENSITY = 240, 33, 0.55
local LISTING_MS, LISTING_MAX_MS = 240, 5000
local CORPUS_KINDS = { [EVENT.prompt] = true, [EVENT.message] = true }
local GLITCH = Buffer.namespace('harness.session_picker.glitch')
local STATIC_DENSITY, STATIC_BAND, STATIC_PRIORITY = 0.3, 0.6, 150

local function one_line(text)
  return text and (tostring(text):gsub('[\r\n]+', ' ')) or ''
end

local function shorten(value, width)
  return text.truncate(one_line(value), width)
end

local function home(dir)
  if not dir or dir == '' then return '?' end

  return text.display_path(dir)
end

local function state_of(session)
  if #session:waiting() > 0 then return 'waiting', 'UiWarn' end
  if session:running() then return 'running', 'UiAccent' end

  return 'idle', 'UiMuted'
end

local function active_agent(dir)
  local view = display.last()

  if view and view.session and view.session.state ~= 'closed' and view.session.dir == dir and view.session.agent then
    return view.session.agent.name
  end

  local latest, at

  for _, session in ipairs(hub.sessions(dir)) do
    local seen = session.times[#session.times] or 0

    if not at or seen > at then
      latest, at = session, seen
    end
  end

  return latest and latest.agent and latest.agent.name or nil
end

local function open_here(session)
  local view = display.view()
  local window = Window.get_current()
  local source_win, source_buf

  if view and Buffer.exists(view.source_buf) then
    source_win, source_buf = view.source_win, view.source_buf
  else
    source_win, source_buf = window.win_id, window:get_buffer().bufnr
  end

  transcript.open(session, { source_win = source_win, source_buf = source_buf })
end

local function ago(ms)
  local seconds = math.floor(ms / 1000)

  if seconds < 5 then return 'just now' end
  if seconds < 60 then return seconds .. 's ago' end
  if seconds < 3600 then return math.floor(seconds / 60) .. 'm ago' end
  if seconds < 86400 then return math.floor(seconds / 3600) .. 'h ago' end

  return math.floor(seconds / 86400) .. 'd ago'
end

local function turns_of(session)
  local total = 0

  for _, event in ipairs(session.history) do
    if event.kind == EVENT.prompt and not event.steered then total = total + 1 end
  end

  return total
end

local function usage_of(session)
  for i = #session.history, 1, -1 do
    if session.history[i].kind == EVENT.usage then return session.history[i] end
  end
end

local SessionPickerBody = Component:extend()

function SessionPickerBody:constructor(props)
  local instance = Component.constructor(self, props)

  instance.picker = props.picker
  instance.elements = {}
  instance._drawing = false

  return instance
end

function SessionPickerBody:mount()
  if self._mounted then return end

  self.elements.title = Element({
    buf_options = { modifiable = false, buflisted = false, bufhidden = 'wipe' },
    win_options = {
      cursorline = false,
      number = false,
      relativenumber = false,
      wrap = false,
      winhl = 'Normal:UiNormal',
    },
    win_plot = { focusable = false },
  })

  self.elements.input = Element({
    buf_options = { modifiable = true, buflisted = false, bufhidden = 'wipe' },
    win_options = {
      cursorline = false,
      number = false,
      relativenumber = false,
      wrap = false,
      winhl = 'Normal:UiNormal',
    },
    win_plot = { focusable = true },
  })

  self.elements.list = Element({
    buf_options = { modifiable = false, buflisted = false, bufhidden = 'wipe' },
    win_options = {
      cursorline = true,
      number = false,
      relativenumber = false,
      wrap = false,
      winhl = 'Normal:UiNormal,FloatBorder:UiBorder,CursorLine:UiSelected',
    },
    win_plot = { focusable = true, border = 'rounded' },
    surface = { elevation = 'raised' },
  })

  self.elements.detail = Element({
    buf_options = { modifiable = false, buflisted = false, bufhidden = 'wipe' },
    win_options = {
      cursorline = false,
      number = false,
      relativenumber = false,
      wrap = true,
      linebreak = true,
      winhl = 'Normal:UiNormal,FloatBorder:UiBorder',
    },
    win_plot = { focusable = false, border = 'rounded', title = ' Details ', title_pos = 'left' },
    surface = { elevation = 'raised' },
  })

  self.elements.footer = Element({
    buf_options = { modifiable = false, buflisted = false, bufhidden = 'wipe' },
    win_options = {
      cursorline = false,
      number = false,
      relativenumber = false,
      wrap = false,
      winhl = 'Normal:UiNormal',
    },
    win_plot = { focusable = false },
  })

  self._mounted = true
end

function SessionPickerBody:get_layout_spec()
  return LayoutSpec.absolute(
    LayoutSpec.vertical({
      LayoutSpec.view(self.elements.title, { height = 1 }),
      LayoutSpec.view(self.elements.input, { height = 1 }),
      LayoutSpec.horizontal({
        LayoutSpec.view(self.elements.list, { flex = 3 }),
        LayoutSpec.view(self.elements.detail, { flex = 2 }),
      }, { flex = 1 }),
      LayoutSpec.view(self.elements.footer, { height = 1 }),
    }),
    {
      anchor = LayoutSpec.Anchor.CENTER,
      width = self.picker:width(),
      height = self.picker:height(),
    }
  )
end

function SessionPickerBody:on_mount()
  self.elements.input:set_buf_var('completion', false)
  self.picker:_bind(self)
  self.picker:_draw_input()
  self.picker:refresh()
  self.elements.input:focus()
  self.elements.input:start_insert()
end

function SessionPickerBody:unmount()
  if not self._mounted then return end

  if self.elements.input then self.elements.input:stop_insert() end

  for _, element in pairs(self.elements) do
    element:unmount()
  end

  self.elements = {}
  self._mounted = false
end

local SessionPicker = Surface:extend()

function SessionPicker:constructor(opts)
  local instance = Surface.constructor(self, {
    kind = 'session-picker',
    title = opts.title or 'Harness sessions',
    owner = opts.owner,
  })

  instance._mode = opts.mode or 'sessions'
  instance._query = ''
  instance._selected = 1
  instance._rows = {}
  instance._filtered = {}
  instance._live = {}
  instance._stored = {}
  instance._body = nil
  instance._timer = nil
  instance._badge = nil
  instance._pending_delete = nil
  instance._select_pending = true
  instance._dir = opts.dir or hub.dir()
  instance._corpus = {}
  instance._lines = {}
  instance._rows_at = {}
  instance._drawn = nil
  instance._detail_drawn = nil
  instance._tune = nil
  instance._tuner = nil
  instance._loading = nil
  instance._loader = nil
  instance._listing = nil
  instance._lister = nil

  return instance
end

function SessionPicker:width()
  return math.max(64, math.min(118, math.floor(Window.screen_width() * 0.84)))
end

function SessionPicker:height()
  return math.max(14, math.min(26, Window.screen_height() - 8))
end

function SessionPicker:open()
  self._body = SessionPickerBody({ picker = self })
  self._view = View()
  self._view:_render({ component = self._body, mode = 'popup' })
  self:set_state('ready')

  self._timer = Timer()
  self._timer:every(400, function()
    if not self:is_open() then
      self._timer:close()
      if self.state ~= 'closed' then self:set_state('closed') end
      return
    end

    self:refresh()
  end)

  self:_begin_listing()
  self:refresh()
  self:_load_stored()

  return self
end

function SessionPicker:_load_stored()
  for _, name in ipairs(agent.names()) do
    hub.list(self._dir, name):on_complete(function(err, listed)
      if err then
        return Timer.schedule(function()
          self:_listed()
        end)
      end

      Timer.schedule(function()
        local kept = {}

        for _, entry in ipairs(self._stored) do
          if entry.agent ~= name then kept[#kept + 1] = entry end
        end

        for _, entry in ipairs(listed or {}) do
          if not entry.session then
            kept[#kept + 1] = { id = entry.id, title = entry.title, updated_at = entry.updated_at, agent = name }
          end
        end

        self._stored = kept
        self:_listed()
      end)
    end)
  end

  async.drain()
end

function SessionPicker:_listed()
  if self._listing then
    self._listing.pending = math.max(0, self._listing.pending - 1)

    if self._listing.pending == 0 and Timer.now() >= self._listing.ends_at then return self:_end_listing() end
  end

  self:refresh()
end

function SessionPicker:_begin_listing()
  if self._mode ~= 'sessions' or theme.reduced() then return end

  local names = agent.names()

  if #names == 0 then return end

  self._listing = { pending = #names, ends_at = Timer.now() + LISTING_MS, gives_up = Timer.now() + LISTING_MAX_MS }
  self._lister = Timer()
  self._lister:every(motion.STEP_MS, function()
    if not self:is_open() or not self._listing then return self:_stop_lister() end
    if self._listing.pending == 0 and Timer.now() >= self._listing.ends_at then return self:_end_listing() end
    if Timer.now() >= self._listing.gives_up then return self:_end_listing() end

    self:_draw_static_state()
  end)
end

function SessionPicker:_stop_lister()
  if self._lister then self._lister:close() end

  self._lister = nil
end

function SessionPicker:_cancel_listing()
  self._listing = nil
  self:_stop_lister()
  self:_clear_static()
  self._drawn, self._detail_drawn = nil, nil
end

function SessionPicker:_end_listing()
  self:_cancel_listing()

  if self:is_open() then self:refresh() end
end

function SessionPicker:_begin_loading(entry)
  if self._loading then return false end

  self._loading = { id = entry.id, title = entry.title or 'untitled', started = Timer.now() }
  self._drawn, self._detail_drawn = nil, nil
  self:_stop_tuner()
  self._loader = Timer()
  self._loader:every(motion.STEP_MS, function()
    if not self:is_open() or not self._loading then return self:_stop_loader() end

    self:_draw_static_state()
  end)

  self:_draw_static_state()

  return true
end

function SessionPicker:_stop_loader()
  if self._loader then self._loader:close() end

  self._loader = nil
end

function SessionPicker:_end_loading()
  self._loading = nil
  self:_stop_loader()
  self:_clear_static()
  self._drawn, self._detail_drawn = nil, nil

  if self:is_open() then self:refresh() end
end

function SessionPicker:_draw_static_state()
  local body = self._body

  if not body or not self:is_open() or not (self._loading or self._listing) then return end

  local seed = motion.step(Timer.now())
  local top = body.elements.title:get_window():get_position()[1]
  local band = seed * 2 % math.max(1, self:height())

  if self._loading then self:_draw_static_title(seed, 'loading', self._loading.title or 'untitled') end

  for _, pane in ipairs({ 'list', 'detail' }) do
    self:_draw_static(body.elements[pane], seed, band, top)
  end
end

function SessionPicker:_clear_static()
  local body = self._body

  if not body then return end

  for _, pane in ipairs({ 'list', 'detail' }) do
    local element = body.elements[pane]

    if element and element:is_valid() then element:get_buffer():clear_namespace(GLITCH, 0, -1) end
  end
end

function SessionPicker:_draw_static_title(seed, label, name)
  local title = self._body.elements.title

  if not title:is_valid() then return end

  local prefix = ' ' .. label .. string.rep('.', seed % 4) .. ' '
  local line = prefix .. shorten(name, self:width() - #prefix - 2)

  title:set_lines({ line })
  title:clear_extmark_highlights()
  title:clear_extmark_texts()
  title:place_extmark_highlight({ hl = 'UiAccent', row = 0, col_range = { from = 1, to = #prefix - 1 } })
  title:place_extmark_highlight({ hl = 'UiTitle', row = 0, col_range = { from = #prefix, to = #line } })
end

function SessionPicker:_draw_static(element, seed, band, top)
  if not element or not element:is_valid() then return end

  local buffer = element:get_buffer()

  buffer:clear_namespace(GLITCH, 0, -1)

  if theme.reduced() then return end

  local window = element:get_window()
  local offset = window:get_position()[1] - top
  local first, last = window:get_visible_range()
  local lines = buffer:get_lines(first, math.min(last, element:get_line_count()))

  for offset_row, line in ipairs(lines) do
    local index = first + offset_row
    local from = #(line:match('^[%s>]*') or '')
    local dense = math.abs(offset + index - 1 - band) <= 1
    local density = dense and STATIC_BAND or STATIC_DENSITY

    for _, cell in ipairs(glitch.cols(line, density, seed + index, from)) do
      buffer:set_extmark(GLITCH, index - 1, cell[1], {
        virt_text = { { cell[2], dense and 'UiThought' or 'UiThoughtFade2' } },
        virt_text_pos = 'overlay',
        priority = STATIC_PRIORITY,
      })
    end
  end
end

function SessionPicker:_resume(entry)
  if not self:_begin_loading(entry) then return self end

  hub
    .load({ dir = self._dir, agent = entry.agent, id = entry.id, title = entry.title })
    :on_complete(function(err, session)
      Timer.schedule(function()
        local was_open = self:is_open()

        self:_end_loading()

        if err then return notice.warn('could not resume: ' .. tostring(err)) end
        if not was_open then return end

        self:close()

        Timer.schedule(function()
          open_here(session)
        end)
      end)
    end)
  async.drain()

  return self
end

function SessionPicker:close()
  if self._timer then self._timer:close() end
  self:_stop_tuner()
  self:_stop_loader()
  self:_stop_lister()
  self:_release_badge()
  if self.state == 'closed' then return self end

  Surface.close(self)

  return self
end

function SessionPicker:_fork_key()
  return keymaps:get('sessions').fork
end

function SessionPicker:_delete_key()
  return keymaps:get('sessions').delete
end

function SessionPicker:_release_badge()
  if self._badge then self._badge.release() end

  self._badge = nil
end

function SessionPicker:set_mode(name)
  if name ~= 'sessions' and name ~= 'agents' then return self end

  if self._listing then self:_cancel_listing() end

  self._mode = name
  self._query = ''
  self._selected = 1
  self._select_pending = true

  self:_draw_input()
  self:refresh()
  self:_focus_input()

  return self
end

function SessionPicker:set_query(query)
  self._query = one_line(query)
  self._selected = 1
  self:refresh()

  return self
end

function SessionPicker:query(query)
  self._query = one_line(query)
  self._selected = 1
  self:_draw_input()
  self:refresh()

  return self
end

function SessionPicker:move(direction)
  if self._loading then return self end

  if self._listing then self:_end_listing() end

  local count = #self._filtered

  if count == 0 then return self end

  local index = self._selected + (direction == 'up' and -1 or 1)

  if index > count then
    index = 1
  elseif index < 1 then
    index = count
  end

  self._selected = index
  self:_start_tune()
  self:_draw_list()
  self:_draw_detail()

  return self
end

function SessionPicker:select()
  if self._loading then return self end

  if self._listing then self:_end_listing() end

  return self:choose(self._filtered[self._selected])
end

function SessionPicker:choose(row)
  if self._listing then self:_end_listing() end
  if not row then return self end

  if row.action == 'new' then return self:set_mode('agents') end
  if row.action == 'back' then return self:set_mode('sessions') end
  if row.action == 'agent' then return self:_start(row.agent) end
  if row.session then return self:_open(row.session) end
  if row.stored then return self:_resume(row.stored) end

  return self
end

function SessionPicker:_open(session)
  self:close()

  Timer.schedule(function()
    open_here(session)
  end)

  return self
end

function SessionPicker:_start(name)
  self:close()

  Timer.schedule(function()
    hub.start({ agent = name, dir = self._dir }):on_complete(function(err, session)
      if err then return notice.warn('could not start ' .. name .. ': ' .. tostring(err)) end

      Timer.schedule(function()
        open_here(session)
      end)
    end)
    async.drain()
  end)

  return self
end

function SessionPicker:_selected_row()
  if self._mode ~= 'sessions' then return nil end

  return self._filtered[self._selected]
end

function SessionPicker:fork()
  if self._loading then return self end

  if self._listing then self:_end_listing() end

  local row = self:_selected_row()

  if row and row.session then return self:_fork_live(row.session) end
  if row and row.stored then return self:_fork_stored(row.stored) end

  return self
end

function SessionPicker:_fork_live(session)
  if not session:can('fork') then
    notice.info('this agent cannot fork sessions')

    return self
  end

  hub.fork(session):on_complete(function(err, forked)
    Timer.schedule(function()
      if err then return notice.warn('could not fork: ' .. tostring(err)) end

      self:_open(forked)
    end)
  end)
  async.drain()

  return self
end

function SessionPicker:_fork_stored(entry)
  local spec = agent.get(entry.agent)

  if not spec or not spec.fork_at_message then
    notice.info('this agent cannot fork sessions')

    return self
  end

  if not self:_begin_loading(entry) then return self end

  hub
    .load({ dir = self._dir, agent = entry.agent, id = entry.id, title = entry.title })
    :on_complete(function(err, session)
      Timer.schedule(function()
        self:_end_loading()

        if err then return notice.warn('could not load: ' .. tostring(err)) end

        self:_fork_live(session)
      end)
    end)
  async.drain()

  return self
end

function SessionPicker:delete()
  if self._loading then return self end

  if self._listing then self:_end_listing() end

  local row = self:_selected_row()

  if not row or not row.stored then return self end

  local entry = row.stored

  if self._pending_delete ~= entry.id then return self:_confirm_delete(entry) end

  self._pending_delete = nil

  hub.delete({ dir = self._dir, agent = entry.agent, id = entry.id }):on_complete(function(err)
    Timer.schedule(function()
      if err then return notice.warn(tostring(err)) end

      local kept = {}

      for _, stored in ipairs(self._stored) do
        if stored.id ~= entry.id then kept[#kept + 1] = stored end
      end

      self._stored = kept
      self:refresh()
    end)
  end)
  async.drain()

  return self
end

function SessionPicker:_confirm_delete(entry)
  self._pending_delete = entry.id
  self:refresh()

  Timer.defer(confirm:get('confirm_ms'), function()
    if self._pending_delete ~= entry.id then return end

    self._pending_delete = nil
    self:refresh()
  end)

  return self
end

function SessionPicker:_focus_input()
  local body = self._body

  if not body or not body.elements.input then return end

  local input = body.elements.input

  if input:is_valid() then
    input:focus()
    input:start_insert()
  end
end

function SessionPicker:_select_default()
  local rows = self._filtered

  if self._mode == 'agents' then
    for i, row in ipairs(rows) do
      if row.action == 'agent' then
        self._selected = i
        return
      end
    end
  else
    local current = display.view()

    for i, row in ipairs(rows) do
      if row.session and current and row.session == current.session then
        self._selected = i
        return
      end
    end

    local wanted = active_agent(self._dir)

    if wanted then
      for i, row in ipairs(rows) do
        if row.session and row.session.agent and row.session.agent.name == wanted then
          self._selected = i
          return
        end
      end
    end

    for i, row in ipairs(rows) do
      if row.session then
        self._selected = i
        return
      end
    end
  end

  self._selected = 1
end

function SessionPicker:_live_sessions()
  local out = {}

  for _, session in ipairs(hub.sessions()) do
    if session.state ~= 'closed' then out[#out + 1] = session end
  end

  table.sort(out, function(a, b)
    local aw, bw = #a:waiting() > 0, #b:waiting() > 0

    if aw ~= bw then return aw end
    if a:running() ~= b:running() then return a:running() end

    return (a.times[#a.times] or 0) > (b.times[#b.times] or 0)
  end)

  return out
end

function SessionPicker:_live_facts(session, status, agent_name)
  local parts = { agent_name }
  local now = Timer.now()

  if status == 'running' then
    local started = lazy('harness.ui.TranscriptView').turn_started(session)
    local elapsed = started and theme.duration(now - started)

    parts[#parts + 1] = elapsed and ('working ' .. elapsed) or 'working'
  elseif status == 'waiting' then
    parts[#parts + 1] = 'asks you'
  else
    local seen = session.times[#session.times]

    if seen then parts[#parts + 1] = ago(now - seen) end
  end

  if session.dir ~= self._dir then parts[#parts + 1] = home(session.dir) end

  return table.concat(parts, ' · ')
end

function SessionPicker:_live_row(session)
  local status, status_hl = state_of(session)
  local agent_name = session.agent and session.agent.name or '?'
  local dir = home(session.dir)
  local icon, icon_hl

  if status == 'waiting' then
    icon, icon_hl = '!', status_hl
  elseif status == 'running' then
    icon, icon_hl = '»', status_hl
  else
    icon, icon_hl = '·', 'UiMuted'
  end

  return {
    session = session,
    section = 'live',
    icon = icon,
    icon_hl = icon_hl,
    indicator = { STATE_INDICATOR[status], STATE_ROLE[status] },
    label = session_types.label(session),
    description = table.concat({ agent_name, status, dir }, ' '),
    meta = self:_live_facts(session, status, agent_name),
  }
end

function SessionPicker:_session_rows()
  local rows = {}

  if self._query == '' then
    rows[#rows + 1] = {
      action = 'new',
      icon = '+',
      icon_hl = 'UiAccent',
      label = 'New session',
      description = 'start one on any agent',
      meta = '',
      label_hl = 'UiAccent',
    }
  end

  for _, session in ipairs(self._live) do
    rows[#rows + 1] = self:_live_row(session)
  end

  local open = {}

  for _, session in ipairs(hub.sessions()) do
    if session.state ~= 'closed' then open[session.id] = true end
  end

  local stored = {}

  for _, entry in ipairs(self._stored) do
    if not open[entry.id] then stored[#stored + 1] = entry end
  end

  table.sort(stored, function(a, b)
    return (a.updated_at or '') > (b.updated_at or '')
  end)

  for _, entry in ipairs(stored) do
    local title = entry.title or 'untitled'
    local when = entry.updated_at and require('core.utils.date').from_iso(entry.updated_at)
    local age = when and require('core.utils.date').age(when, os.time()).display or ''

    rows[#rows + 1] = {
      stored = entry,
      section = 'recent',
      icon = ' ',
      label = title,
      age = age,
      description = entry.agent .. ' ' .. title,
      meta = table.concat({ entry.agent, age }, ' · '),
    }
  end

  return rows
end

function SessionPicker:_agent_rows()
  local default = agent.get().name
  local names = agent.names()

  table.sort(names, function(a, b)
    if a == default or b == default then return a == default end

    return a < b
  end)

  local rows = {}

  if self._query == '' then
    rows[#rows + 1] = {
      action = 'back',
      icon = '←',
      icon_hl = 'UiMuted',
      label = 'Back to sessions',
      description = 'switch, do not start',
      meta = '',
      label_hl = 'UiMuted',
    }
  end

  for _, name in ipairs(names) do
    local spec = agent.get(name)

    rows[#rows + 1] = {
      action = 'agent',
      agent = name,
      spec = spec,
      icon = '+',
      icon_hl = 'UiAccent',
      label = name .. (name == default and ' (default)' or ''),
      description = table.concat({ spec.description or '', spec.command or '' }, ' '),
      meta = spec.model or spec.command or '',
      label_hl = name == default and 'UiAccent' or nil,
    }
  end

  return rows
end

function SessionPicker:refresh()
  local body = self._body

  if not self:is_open() or not body or not body._mounted then return self end

  self._live = self:_live_sessions()
  self._rows = self._mode == 'agents' and self:_agent_rows() or self:_session_rows()
  self._filtered = self:_filter_rows()

  if self._selected > #self._filtered then self._selected = math.max(1, #self._filtered) end
  if self._selected < 1 then self._selected = 1 end

  if self._select_pending then
    self._select_pending = false
    self:_select_default()
  end

  if self._loading then
    self:_draw_static_state()
  else
    self:_draw_tabs()
    self:_draw_list()
    self:_draw_detail()

    if self._listing then self:_draw_static_state() end
  end

  self:_draw_footer()
  self:_draw_count()

  return self
end

function SessionPicker:_body_of(row)
  local session = row.session

  if not session then return nil end

  local cached = self._corpus[session.key]
  local size = #session.history

  if cached and cached.size == size then return cached.text end

  local parts = {}

  for _, event in ipairs(session.history) do
    if CORPUS_KINDS[event.kind] and event.text and event.text ~= '' then parts[#parts + 1] = one_line(event.text) end
  end

  local joined = table.concat(parts, ' ')

  self._corpus[session.key] = { size = size, text = joined }

  return joined
end

function SessionPicker:_filter_rows()
  local query = self._query:lower()

  return session_search.rank(self._rows, query, function(row)
    return self:_body_of(row)
  end)
end

function SessionPicker:_draw_input()
  local body = self._body

  if not body or not body.elements.input then return end

  local input = body.elements.input

  if not input:is_valid() then return end

  input:set_lines({ PROMPT .. self._query })
  input:set_cursor({ 1, #PROMPT + #self._query })
  input:clear_extmark_highlights()
  input:place_extmark_highlight({ hl = 'UiAccent', row = 0, col_range = { from = 0, to = #PROMPT } })
  self:_draw_count()
end

function SessionPicker:_draw_count()
  local body = self._body

  if not body or not body.elements.input then return end

  local input = body.elements.input
  local text

  if self._loading then
    text = 'loading'
  elseif self._listing then
    text = 'scanning'
  elseif self._mode == 'agents' then
    text = #agent.names() .. ' agents'
  else
    text = string.format('%d live', #self._live)
  end

  input:clear_extmark_texts()
  input:place_extmark_text({ text = text, hl = 'UiMuted', row = 0, col = 0, pos = 'right_align' })
end

function SessionPicker:_draw_tabs()
  local body = self._body

  if not body then return end

  local title = body.elements.title

  if not title:is_valid() then return end

  local sessions_label = 'Sessions ' .. #self._live
  local agents_label = 'New session ' .. #agent.names()
  local line = ' Harness  ' .. sessions_label .. '    ' .. agents_label
  local sessions_from = #' Harness  '
  local agents_from = sessions_from + #sessions_label + 4

  title:set_lines({ line })
  title:clear_extmark_highlights()
  title:clear_extmark_texts()
  title:place_extmark_highlight({ hl = 'UiTitle', row = 0, col_range = { from = 1, to = 8 } })
  title:place_extmark_highlight({
    hl = self._mode == 'sessions' and 'UiAccent' or 'UiMuted',
    row = 0,
    col_range = { from = sessions_from, to = sessions_from + #sessions_label },
  })
  title:place_extmark_highlight({
    hl = self._mode == 'agents' and 'UiAccent' or 'UiMuted',
    row = 0,
    col_range = { from = agents_from, to = agents_from + #agents_label },
  })
  title:place_extmark_text({
    text = self._mode == 'sessions' and 'transcripts are buffers' or 'on any ACP agent',
    hl = 'UiMuted',
    row = 0,
    col = 0,
    pos = 'right_align',
  })
end

function SessionPicker:_tuning()
  local tune = self._tune

  if not tune or theme.reduced() then return nil end

  local progress = (Timer.now() - tune.started) / TUNE_MS

  if progress >= 1 then return nil end

  return tune, progress
end

function SessionPicker:_stop_tuner()
  if self._tuner then self._tuner:close() end

  self._tuner = nil
end

function SessionPicker:_start_tune()
  if theme.reduced() then return end

  self._tune = { started = Timer.now() }
  self:_stop_tuner()
  self._tuner = Timer()
  self._tuner:every(TUNE_FRAME_MS, function()
    if not self:is_open() or not self:_tuning() then
      self:_stop_tuner()
      self._tune = nil
    end

    if self:is_open() then self:_draw_list() end
  end)
end

local function match_ranges(positions, limit)
  local ranges, from, last = {}, nil, nil

  for _, at in ipairs(positions or {}) do
    if at <= limit then
      if from and at == last + 1 then
        last = at
      else
        if from then ranges[#ranges + 1] = { from, last } end

        from, last = at, at
      end
    end
  end

  if from then ranges[#ranges + 1] = { from, last } end

  return ranges
end

function SessionPicker:_snow(width)
  local seed = math.floor(Timer.now() / 120)
  local rows = {}

  for i = 1, 3 do
    rows[i] = glitch.snow(math.max(8, width - 6), seed, i)
  end

  return rows
end

function SessionPicker:_draw_list()
  local body = self._body

  if not body or not body.elements.list or self._loading then return end

  local list = body.elements.list

  if not list:is_valid() then return end

  local window = list:get_window()
  local width = window and window:get_width() or 70
  local inner = math.max(24, width - 2)
  local rows = self._filtered
  local lines, highlights, overlays = {}, {}, {}
  local line_of, row_of = {}, {}
  local tune, progress = self:_tuning()
  local sectioned = self._query == '' and self._mode == 'sessions'
  local section

  local function push(line)
    lines[#lines + 1] = line

    return #lines - 1
  end

  for i, row in ipairs(rows) do
    if sectioned and row.section and row.section ~= section then
      local count = 0

      for _, other in ipairs(rows) do
        if other.section == row.section then count = count + 1 end
      end

      local at = push(' ' .. SECTION[row.section] .. ' ' .. count)

      highlights[#highlights + 1] = { hl = 'UiMuted', row = at, col_range = { from = 1, to = #lines[#lines] } }
    end

    section = row.section or section

    local loading = self._loading and row.stored and row.stored.id == self._loading.id
    local meta = shorten(loading and 'loading' or row.meta or '', math.max(8, math.floor(inner / 2)))
    local label = shorten(row.label or '', math.max(8, inner - text.width(meta) - 4))
    local icon = row.icon or ' '

    if loading then label = glitch.scramble(label, 0.4, math.floor(Timer.now() / TUNE_FRAME_MS)) end
    local head = ' ' .. icon .. ' ' .. label
    local tail = meta ~= '' and (' ' .. meta .. ' ') or ''
    local gap = tail ~= '' and string.rep(' ', math.max(1, width - text.width(head) - text.width(tail))) or ''
    local at = push(head .. gap .. tail)
    local line = lines[#lines]
    local origin = 2 + #icon

    line_of[i], row_of[at + 1] = at + 1, i

    highlights[#highlights + 1] = { hl = row.icon_hl or 'UiMuted', row = at, col_range = { from = 1, to = 1 + #icon } }

    if row.label_hl then
      highlights[#highlights + 1] = { hl = row.label_hl, row = at, col_range = { from = origin, to = #head } }
    end

    for _, range in ipairs(match_ranges(row.match, #label)) do
      highlights[#highlights + 1] =
        { hl = 'UiAccent', row = at, col_range = { from = origin + range[1] - 1, to = origin + range[2] } }
    end

    if tail ~= '' then
      highlights[#highlights + 1] = { hl = 'UiMuted', row = at, col_range = { from = #head + #gap, to = #line } }
    end

    local indicator = row.indicator and indicators.chunk(row.indicator[1], row.indicator[2])

    if loading then indicator = indicators.chunk('loading', 'accent') end

    if indicator then overlays[#overlays + 1] = { texts = { indicator }, row = at, col = 1, pos = 'overlay' } end

    if tune and i == self._selected then
      local seed = math.floor(Timer.now() / TUNE_FRAME_MS)

      for _, cell in ipairs(glitch.cols(label, TUNE_DENSITY * (1 - progress), seed)) do
        overlays[#overlays + 1] =
          { texts = { { cell[2], 'UiMuted' } }, row = at, col = origin + cell[1], pos = 'overlay' }
      end
    end
  end

  if #rows == 0 then
    local at = push('  no matches')

    highlights[#highlights + 1] = { hl = 'UiMuted', row = at, col_range = { from = 2, to = #lines[#lines] } }

    if not theme.reduced() then
      for _, snow in ipairs(self:_snow(width)) do
        local row = push('  ' .. snow)

        highlights[#highlights + 1] = { hl = 'UiMuted', row = row, col_range = { from = 2, to = #lines[#lines] } }
      end
    end
  end

  local signature = {}

  for _, mark in ipairs(highlights) do
    signature[#signature + 1] = mark.hl .. mark.row .. ':' .. mark.col_range.from .. '-' .. mark.col_range.to
  end

  for _, mark in ipairs(overlays) do
    signature[#signature + 1] = 'o' .. mark.row .. ':' .. mark.col .. vim.inspect(mark.texts)
  end

  local key = table.concat(lines, '\n') .. '\0' .. table.concat(signature, ';')

  self._rows_at, self._line_of = row_of, line_of

  if key ~= self._drawn then
    self._drawn = key

    list:set_lines(lines)
    list:clear_extmark_highlights()
    list:clear_extmark_texts()

    for _, mark in ipairs(highlights) do
      list:place_extmark_highlight(mark)
    end

    for _, mark in ipairs(overlays) do
      list:place_extmark_text(mark)
    end
  end

  body._drawing = true
  list:set_cursor({ math.min(line_of[self._selected] or 1, #lines), 0 })
  body._drawing = false
end

function SessionPicker:_detail_of(row)
  local lines, highlights = {}, {}
  local extras = {}

  local function put(value, hl)
    lines[#lines + 1] = value

    if hl then highlights[#highlights + 1] = { hl = hl, row = #lines - 1, col_range = { from = 0, to = #value } } end
  end

  local function field(key, value, hl)
    if value == nil or value == '' then return end

    value = tostring(value)

    local line = ' ' .. key
    local from = #line + 2

    lines[#lines + 1] = line .. '  ' .. value
    highlights[#highlights + 1] = { hl = 'UiMuted', row = #lines - 1, col_range = { from = 1, to = 1 + #key } }

    if hl then
      highlights[#highlights + 1] = { hl = hl, row = #lines - 1, col_range = { from = from, to = #lines[#lines] } }
    end
  end

  if row and row.session then
    local session = row.session
    local buffer = display.buffer_of(session)
    local status = state_of(session)
    local mode = session:mode()
    local model = mode and (mode.name or mode.id) or 'default'
    local usage = usage_of(session)
    local turns = turns_of(session)

    put(' ' .. session_types.label(session), 'UiTitle')
    field('agent', (session.agent and session.agent.name or '?') .. ' · ' .. model)
    field('dir', home(session.dir))

    local facts = {}

    if usage and usage.used and usage.size and usage.size > 0 then
      local share = usage.used / usage.size
      local percent = math.floor(share * 100 + 0.5)

      facts[#facts + 1] = percent .. '%'
      extras.ring = {
        row = #lines,
        group = percent >= winbar.CONTEXT_FULL and 'UiError'
          or percent >= winbar.CONTEXT_WARN and 'UiWarn'
          or 'UiAccent',
        share = share,
      }
    end

    if turns > 0 then facts[#facts + 1] = turns .. (turns == 1 and ' turn' or ' turns') end
    if usage and usage.cost then facts[#facts + 1] = string.format('$%.2f', usage.cost) end

    field('context', table.concat(facts, ' · '))

    if not extras.ring or #facts == 0 then extras.ring = nil end

    if buffer then
      local buf = Buffer(buffer)

      field('buffer', string.format('#%d · %d lines', buffer, buf:is_valid() and buf:get_line_count() or 0), 'UiMuted')
    else
      field('buffer', 'not loaded', 'UiMuted')
    end

    if #session.queue > 0 then field('queue', #session.queue .. ' queued', 'UiWarn') end

    extras.badge = status
  elseif row and row.stored then
    local entry = row.stored
    local spec = agent.get(entry.agent)

    put(' ' .. (entry.title or 'untitled'), 'UiTitle')
    field('agent', entry.agent)
    field('used', row.age, 'UiMuted')
    field('dir', home(self._dir))
    field('fork', spec and spec.fork_at_message and 'from any message' or 'not supported', 'UiMuted')

    if self._pending_delete == entry.id then
      put(' press ' .. self:_delete_key() .. ' again to delete for good', 'UiWarn')
    end
  elseif row and row.action == 'agent' then
    put(' ' .. row.agent, 'UiTitle')
    put(' ' .. (row.spec.description or ''), 'UiMuted')
    field('command', row.spec.command)
    field('model', row.spec.model or 'whatever it is set to')
    field('login', row.spec.login, 'UiMuted')
    field('fork', row.spec.fork_at_message and 'from any message' or 'not supported', 'UiMuted')
  elseif row and row.action == 'new' then
    put(' New session', 'UiTitle')
    put(' Start a conversation on any of the agents you have.', 'UiMuted')
    put(' Press <CR> to see them, then <CR> again to start.', 'UiMuted')
  elseif row and row.action == 'back' then
    put(' Sessions', 'UiTitle')
    put(' Switch between the sessions you have open.', 'UiMuted')
    put(' Each one is a transcript buffer; pick it to switch to it.', 'UiMuted')
  else
    put(' Nothing selected', 'UiMuted')
  end

  return lines, highlights, extras
end

function SessionPicker:_draw_detail()
  local body = self._body

  if not body or not body.elements.detail or self._loading then return end

  local detail = body.elements.detail

  if not detail:is_valid() then return end

  local row = self._filtered[self._selected]
  local lines, highlights, extras = self:_detail_of(row)
  local marks = {}

  for _, mark in ipairs(highlights) do
    marks[#marks + 1] = mark.hl .. mark.row .. ':' .. mark.col_range.from .. '-' .. mark.col_range.to
  end

  local ring = extras.ring and (extras.ring.group .. math.floor(extras.ring.share * 100 + 0.5)) or ''
  local key = table.concat(lines, '\n') .. '\0' .. table.concat(marks, ';') .. '\0' .. (extras.badge or '') .. ring

  if key == self._detail_drawn and (not extras.badge or self._badge) then return end

  self._detail_drawn = key
  self:_release_badge()

  detail:set_lines(lines)
  detail:clear_extmark_highlights()
  detail:clear_extmark_texts()

  for _, mark in ipairs(highlights) do
    detail:place_extmark_highlight(mark)
  end

  if extras.badge then
    self._badge = catalog.render('badge', { text = extras.badge, color = STATE_ROLE[extras.badge] })
    detail:place_extmark_text({ texts = self._badge.lines[1], row = 0, col = 0, pos = 'eol' })
  end

  if extras.ring then
    local chunk = theme.context_ring(extras.ring.share, extras.ring.group)

    if chunk then
      detail:place_extmark_text({ texts = { { ' ', 'Normal' }, chunk }, row = extras.ring.row, col = 0, pos = 'eol' })
    end
  end
end

function SessionPicker:_draw_footer()
  local body = self._body

  if not body or not body.elements.footer then return end

  local footer = body.elements.footer

  if not footer:is_valid() then return end

  local hints = self._mode == 'sessions'
      and {
        { '<CR>', 'open' },
        { self:_fork_key(), 'fork' },
        { self:_delete_key(), 'delete (press twice)' },
        { '<Tab>', 'new' },
        { '<C-n>/<C-p>', 'move' },
        { '<Esc>', 'close' },
      }
    or {
      { '<CR>', 'start' },
      { '<Tab>', 'back' },
      { '<C-n>/<C-p>', 'move' },
      { '<Esc>', 'close' },
    }

  local line = ' '
  local highlights = {}

  for i, hint in ipairs(hints) do
    if i > 1 then line = line .. '   ' end

    local from = #line
    line = line .. hint[1]
    highlights[#highlights + 1] = { hl = 'UiAccent', row = 0, col_range = { from = from, to = #line } }

    from = #line + 1
    line = line .. ' ' .. hint[2]
    highlights[#highlights + 1] = { hl = 'UiMuted', row = 0, col_range = { from = from, to = #line } }
  end

  footer:set_lines({ line })
  footer:clear_extmark_highlights()

  for _, mark in ipairs(highlights) do
    footer:place_extmark_highlight(mark)
  end
end

function SessionPicker:_bind(body)
  local input, list = body.elements.input, body.elements.list

  local function choose()
    self:select()
  end

  local function mode_up()
    self:set_mode(self._mode == 'sessions' and 'agents' or 'sessions')
  end

  local function close()
    self:close()
  end

  local function fork_row()
    self:fork()
  end

  local function delete_row()
    self:delete()
  end

  input:set_keymap('i', self:_fork_key(), fork_row, 'Fork the session')
  input:set_keymap('i', self:_delete_key(), delete_row, 'Delete the session (press twice)')
  input:set_keymap('i', '<C-n>', function()
    self:move('down')
  end, 'Move down')
  input:set_keymap('i', '<Down>', function()
    self:move('down')
  end, 'Move down')
  input:set_keymap('i', '<C-p>', function()
    self:move('up')
  end, 'Move up')
  input:set_keymap('i', '<Up>', function()
    self:move('up')
  end, 'Move up')
  input:set_keymap('i', '<CR>', choose, 'Choose')
  input:set_keymap('i', '<Tab>', mode_up, 'Switch between sessions and agents')
  input:set_keymap('i', '<S-Tab>', mode_up, 'Switch between sessions and agents')
  input:set_keymap('i', '<Esc>', close, 'Close')
  input:set_keymap('i', '<C-c>', close, 'Close')

  for _, element in ipairs({ input, list }) do
    element:set_keymap('n', '<CR>', choose, 'Choose')
    element:set_keymap('n', '<Tab>', mode_up, 'Switch between sessions and agents')
    element:set_keymap('n', '<S-Tab>', mode_up, 'Switch between sessions and agents')
    element:set_keymap('n', '<Esc>', close, 'Close')
    element:set_keymap('n', '<C-c>', close, 'Close')
    element:set_keymap('n', 'q', close, 'Close')
    element:set_keymap('n', self:_fork_key(), fork_row, 'Fork the session')
    element:set_keymap('n', self:_delete_key(), delete_row, 'Delete the session (press twice)')
    element:set_keymap('n', 'j', function()
      self:move('down')
    end, 'Move down')
    element:set_keymap('n', 'k', function()
      self:move('up')
    end, 'Move up')
  end

  list:set_keymap('n', '<C-n>', function()
    self:move('down')
  end, 'Move down')
  list:set_keymap('n', '<C-p>', function()
    self:move('up')
  end, 'Move up')

  input:attach_to_changes({
    on_lines = event.async(function()
      event.await()

      if not input:is_valid() then return end

      local line = (input:get_lines()[1] or '')

      if not vim.startswith(line, PROMPT) then
        input:set_lines({ PROMPT })
        input:set_cursor({ 1, #PROMPT })

        return
      end

      local query = line:sub(#PROMPT + 1)

      if query ~= self._query then self:set_query(query) end
    end),
  })

  list:on('CursorMoved', function()
    if body._drawing or not list:is_valid() then return end

    local cursor = list:get_cursor()

    if not cursor then return end

    local row = self._rows_at[cursor[1]]

    if row and row ~= self._selected and self._filtered[row] then
      self._selected = row
      self:_start_tune()
      self:_draw_list()
      self:_draw_detail()
    end
  end)
end

function SessionPicker:snapshot()
  local row = self._filtered[self._selected]
  local selected = row and ((row.icon or '') .. ' ' .. (row.label or '')) or 'none'

  return string.format(
    '%s: session picker [%s], %s mode, %d live, %d rows, query "%s", selected: %s',
    self.id,
    self.state,
    self._mode,
    #self._live,
    #self._filtered,
    self._query,
    selected
  )
end

SessionPicker.COMMANDS = {
  mode = {
    summary = 'Show sessions or the agents a new session can start on.',
    params = { { name = 'name', type = schema.literal(MODES) } },
    run = function(self, args)
      self:set_mode(args.name)
    end,
  },
  query = {
    summary = 'Filter the rows by text.',
    params = { { name = 'text', type = schema.str() } },
    run = function(self, args)
      self:query(args.text)
    end,
  },
  select = {
    summary = 'Choose the selected row: open a session in this window, or start one.',
    params = {},
    run = function(self)
      self:select()
    end,
  },
}

function SessionPicker.launch(opts)
  local picker = require('surfaces').add(SessionPicker(opts or {}))
  local ok, err = pcall(picker.open, picker)

  if not ok then
    picker:close()
    error(err, 0)
  end

  return picker
end

return SessionPicker
