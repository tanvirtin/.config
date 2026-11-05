local lazy = require('core.lazy')

local hub = lazy('harness.hub')
local Timer = lazy('core.Timer')
local surfaces = lazy('surfaces')
local Object = lazy('core.Object')
local async = lazy('harness.async')
local notice = lazy('harness.ui.notice')
local keymaps = lazy('harness.settings.keymaps')
local settings = lazy('harness.settings.sessions')

local SessionsView = Object:extend()

SessionsView.TITLE = 'Sessions'

function SessionsView.keys()
  return keymaps:get('sessions')
end

function SessionsView.hints()
  local keys = SessionsView.keys()

  return {
    { '<CR>', 'open / new' },
    { keys.fork, 'fork' },
    { keys.delete, 'delete (press twice)' },
    { '<C-n>/<C-p>', 'move' },
    { '<Esc>', 'close' },
  }
end

function SessionsView.warn(message)
  notice.warn(message)
end

function SessionsView:constructor(opts, rows_of, status_of)
  opts = opts or {}

  return {
    opts = opts,
    dir = opts.dir or hub.dir(),
    rows_of = rows_of,
    status_of = status_of,
    rows = {},
    pending = nil,
    picker = nil,
  }
end

function SessionsView:_refresh()
  if self.picker and self.picker:is_open() then self.picker:set_items(self.rows) end

  return self
end

function SessionsView:_confirm(row)
  self.pending = row.id
  row.description = 'press ' .. SessionsView.keys().delete .. ' again to delete for good'
  self.picker:set_items(self.rows)

  Timer.defer(settings:get('confirm_ms'), function()
    if self.pending ~= row.id then return end

    self.pending = nil
    row.description = self.status_of(row.key and hub.session(row.key), row.updated_at)
    self:_refresh()
  end)

  return self
end

function SessionsView:delete(row)
  if not row or row.action then return self end
  if self.pending ~= row.id then return self:_confirm(row) end

  self.pending = nil

  local live = row.key and hub.session(row.key)

  hub.delete({ dir = self.dir, agent = self.opts.agent, id = row.id }):on_complete(function(err)
    Timer.schedule(function()
      if err then return SessionsView.warn(tostring(err)) end

      if live then
        require('harness.ui.composer').forget(live)
        require('harness.ui.transcript').forget(live)
      end

      self.rows = vim.tbl_filter(function(candidate)
        return candidate.id ~= row.id
      end, self.rows)
      self:_refresh()
    end)
  end)
  async.drain()

  return self
end

function SessionsView:fork(row)
  local live = row and row.key and hub.session(row.key)

  if not live then return notice.info('open this session first; only a live session can be forked') end
  if not live:can('fork') then return notice.info('this agent cannot fork sessions') end

  hub.fork(live):on_complete(function(err, forked)
    Timer.schedule(function()
      if err then return SessionsView.warn('could not fork: ' .. tostring(err)) end
      if self.opts.on_open then self.opts.on_open(forked) end
    end)
  end)
  async.drain()

  return self
end

function SessionsView:_load(row)
  local on_open = self.opts.on_open
  local shown

  hub
    .load({
      dir = self.dir,
      agent = self.opts.agent,
      id = row.id,
      title = row.title,
      on_session = function(session)
        shown = session
        Timer.schedule(function()
          if on_open then on_open(session) end
        end)
      end,
    })
    :on_complete(function(err, session)
      Timer.schedule(function()
        if err then
          if shown then require('harness.ui.transcript').forget(shown) end
          return SessionsView.warn(tostring(err))
        end

        if not shown and on_open then on_open(session) end
      end)
    end)
  async.drain()

  return self
end

function SessionsView:select(row)
  local opts = self.opts

  if row.action == 'new' then return opts.on_new and opts.on_new(row.agent) end
  if row.action == 'browse' then return opts.on_browse and opts.on_browse(row.agent) end

  local live = row.key and hub.session(row.key)

  if live then return opts.on_open and opts.on_open(live) end

  return self:_load(row)
end

function SessionsView:_show(listed)
  self.rows = self.rows_of(listed)
  self.picker = surfaces.pick({
    title = SessionsView.TITLE,
    items = self.rows,
    width = '60vw',
    max_height = 15,
    on_select = function(row)
      self:select(row)
    end,
    actions = {
      {
        key = SessionsView.keys().fork,
        desc = 'Fork the session',
        run = function(row)
          self:fork(row)
        end,
      },
      {
        key = SessionsView.keys().delete,
        desc = 'Delete the session (press twice)',
        run = function(row)
          self:delete(row)
        end,
      },
    },
    hints = SessionsView.hints(),
  })

  return self.picker
end

function SessionsView:open()
  local opened = async.Future()

  hub.list(self.dir, self.opts.agent):on_complete(function(err, listed)
    if err then
      SessionsView.warn(tostring(err))
      listed = {}
    end

    Timer.schedule(function()
      opened:set_result(self:_show(listed))
      async.drain()
    end)
  end)

  return opened
end

return SessionsView
