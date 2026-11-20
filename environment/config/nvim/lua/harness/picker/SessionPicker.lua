local lazy = require('core.lazy')

local View = lazy('ui.View')
local Timer = lazy('core.Timer')
local event = lazy('core.event')
local async = lazy('harness.async')
local client = lazy('harness.client')
local schema = lazy('nvim_mcp.schema')
local Component = lazy('ui.Component')
local notice = lazy('harness.ui.notice')
local Surface = lazy('surfaces.Surface')
local Buffer = lazy('core.editor.Buffer')
local Window = lazy('core.editor.Window')
local display = lazy('harness.ui.display')
local Element = lazy('ui.elements.Element')
local format = require('harness.picker.format')
local LayoutSpec = lazy('ui.layout.LayoutSpec')
local keymaps = lazy('harness.settings.keymaps')
local confirm = lazy('harness.settings.sessions')
local transcript = lazy('harness.transcript.view')

local PROMPT, MODES = format.PROMPT, format.MODES
local one_line = format.one_line

local function active_agent(dir)
  local view = display.last()

  if view and view.session and view.session.state ~= 'closed' and view.session.dir == dir and view.session.agent then
    return view.session.agent.name
  end

  local latest, at

  for _, session in ipairs(client.sessions(dir)) do
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

for _, part in ipairs({
  require('harness.picker.rows'),
  require('harness.picker.detail'),
  require('harness.picker.list'),
  require('harness.picker.loading'),
}) do
  for name, method in pairs(part) do
    SessionPicker[name] = method
  end
end

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
  instance._dir = opts.dir or client.dir()
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
  for _, name in ipairs(client.agents()) do
    client.list(self._dir, name):on_complete(function(err, listed)
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

function SessionPicker:_resume(entry)
  if not self:_begin_loading(entry) then return self end

  client
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
    client.start({ agent = name, dir = self._dir }):on_complete(function(err, session)
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

  client.fork(session):on_complete(function(err, forked)
    Timer.schedule(function()
      if err then return notice.warn('could not fork: ' .. tostring(err)) end

      self:_open(forked)
    end)
  end)
  async.drain()

  return self
end

function SessionPicker:_fork_stored(entry)
  local spec = client.agent(entry.agent)

  if not spec or not spec.fork_at_message then
    notice.info('this agent cannot fork sessions')

    return self
  end

  if not self:_begin_loading(entry) then return self end

  client
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

  client.delete({ dir = self._dir, agent = entry.agent, id = entry.id }):on_complete(function(err)
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
    text = #client.agents() .. ' agents'
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
  local agents_label = 'New session ' .. #client.agents()
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
