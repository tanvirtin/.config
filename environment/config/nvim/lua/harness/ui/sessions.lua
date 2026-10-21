local settings = require('harness.settings.sessions')
local Timer = require('core.Timer')
local console = require('core.console')
local hub = require('harness.hub')
local surfaces = require('surfaces')

local sessions = {}

local NEW = { label = '+ New session', description = 'start a fresh conversation', action = 'new' }

local function when(updated_at)
  return updated_at and updated_at:sub(1, 16):gsub('T', ' ') or nil
end

function sessions.rows(listed)
  local rows = { vim.deepcopy(NEW) }

  for _, item in ipairs(listed) do
    local live = item.session
    local mark = live and (live:running() and '● ' or '○ ') or '  '
    local status = live and (live:running() and 'running' or 'open') or when(item.updated_at)

    rows[#rows + 1] = {
      label = mark .. (item.title or (live and live.title) or 'untitled'),
      description = status,
      id = item.id,
      title = item.title,
      updated_at = item.updated_at,
      key = live and live.key,
    }
  end

  return rows
end

local function warn(message)
  console.notify('Harness: ' .. message, 'warn')
end

function sessions.open(opts)
  opts = opts or {}

  local dir = opts.dir or hub.dir()
  local task = hub.list(dir)
  local opened = require('harness.async').Future.new()

  task:on_complete(function(err, listed)
    if err then
      warn(tostring(err))
      listed = {}
    end

    Timer.schedule(function()
      local rows = sessions.rows(listed)
      local pending

      local function delete(row, picker)
        if not row or row.action == 'new' then return end

        if pending ~= row.id then
          pending = row.id
          row.description = 'press <C-x> again to delete for good'
          picker:set_items(rows)

          Timer.defer(settings:get('confirm_ms'), function()
            if pending == row.id then
              pending = nil
              row.description = row.key and 'open' or when(row.updated_at)
              if picker:is_open() then picker:set_items(rows) end
            end
          end)

          return
        end

        pending = nil

        local live = row.key and hub.session(row.key)

        hub.delete({ dir = dir, id = row.id }):on_complete(function(delete_err)
          Timer.schedule(function()
            if delete_err then return warn(tostring(delete_err)) end
            if live then
              require('harness.ui.composer').forget(live)
              require('harness.ui.transcript').forget(live)
            end

            rows = vim.tbl_filter(function(r)
              return r.id ~= row.id
            end, rows)

            if picker:is_open() then picker:set_items(rows) end
          end)
        end)
        require('harness.async').drain()
      end

      local picker = surfaces.pick({
        title = 'Sessions',
        items = rows,
        width = '60vw',
        max_height = 15,
        on_select = function(row)
          if row.action == 'new' then return opts.on_new and opts.on_new() end
          local live = row.key and hub.session(row.key)

          if live then return opts.on_open and opts.on_open(live) end

          hub.load({ dir = dir, id = row.id, title = row.title }):on_complete(function(load_err, session)
            Timer.schedule(function()
              if load_err then return warn(tostring(load_err)) end
              if opts.on_open then opts.on_open(session) end
            end)
          end)
          require('harness.async').drain()
        end,
        actions = { { key = '<C-x>', desc = 'Delete the session (press twice)', run = delete } },
        hints = {
          { '<CR>', 'open / new' },
          { '<C-x><C-x>', 'delete' },
          { '<C-n>/<C-p>', 'move' },
          { '<Esc>', 'close' },
        },
      })

      opened:set_result(picker)
      require('harness.async').drain()
    end)
  end)

  return opened
end

return sessions
