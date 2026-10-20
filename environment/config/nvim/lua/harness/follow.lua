local lazy = require('core.lazy')

local Buffer = lazy('core.Buffer')
local FileWatch = lazy('core.FileWatch')
local Timer = lazy('core.Timer')
local async = lazy('harness.async')
local events = lazy('harness.events')

local follow = {}

follow.DEBOUNCE_MS = 300
follow.GRACE_MS = 1500
follow.POLL_MS = 3000

local followers = {}

function follow.reload_session(session)
  return require('harness.hub').reload(session)
end

local function own_writes(session)
  if session:running() or session.reloading then return true end

  return session.turn_ended ~= nil and Timer.now() - session.turn_ended < follow.GRACE_MS
end

function follow.reload(session)
  local follower = followers[session]

  if not follower or follower.loading then return end

  follower.loading = true
  follower.seen = follower.path and FileWatch.fingerprint(follower.path) or follower.seen

  follow.reload_session(session):on_complete(function(err, changed)
    follower.loading = false

    if err then return end

    if changed then
      session.external = Timer.now()
      session:_notify({ kind = events.NOTICE.external })
    end
  end)
  async.drain()
end

function follow.check(session, absorb)
  local follower = followers[session]

  if not follower or follower.loading then return end

  local now = follower.path and FileWatch.fingerprint(follower.path)

  if follower.path and now == follower.seen then return end

  if own_writes(session) then
    follower.grace:after(follow.GRACE_MS, function()
      follow.check(session, true)
    end)
    return
  end

  if absorb and follower.path then
    follower.seen = now
    return
  end

  follow.reload(session)
end

local function watch_file(session, follower, path)
  follower.path = path
  follower.seen = FileWatch.fingerprint(path)
  follower.watch = FileWatch(path, {
    debounce_ms = follow.DEBOUNCE_MS,
    on_change = function()
      if followers[session] == follower then follow.check(session) end
    end,
  })
  follower.watch:start()
end

local function visible(session)
  local bufnr = require('harness.ui.transcript').buffer_of(session)

  return bufnr ~= nil and #Buffer(bufnr):get_windows() > 0
end

local function poll(session, follower)
  follower.poller = Timer():every(follow.POLL_MS, function()
    if followers[session] ~= follower or follower.loading then return end

    local path = session.agent and session.agent.transcript and session.agent:transcript(session.id)

    if path then
      follower.poller:close()
      follower.poller = nil
      return watch_file(session, follower, path)
    end

    if not visible(session) or not session.connection:supports('list') then return end

    async.run(function()
      for _, entry in ipairs(session.connection:list_sessions(session.dir)) do
        if entry.sessionId == session.id then
          local changed = follower.updated and entry.updatedAt ~= follower.updated

          follower.updated = entry.updatedAt
          if changed and not own_writes(session) then follow.reload(session) end
        end
      end
    end)
  end)
end

function follow.start(session)
  if followers[session] or not session.id then return followers[session] end

  local follower = { grace = Timer() }
  local path = session.agent and session.agent.transcript and session.agent:transcript(session.id)

  followers[session] = follower

  if path then
    watch_file(session, follower, path)
  else
    poll(session, follower)
  end

  return follower
end

function follow.stop(session)
  local follower = followers[session]

  if not follower then return end

  followers[session] = nil
  follower.grace:close()
  if follower.watch then follower.watch:stop() end
  if follower.poller then follower.poller:close() end
end

function follow.is_following(session)
  return followers[session] ~= nil
end

function follow.source(session)
  local follower = followers[session]

  if not follower then return nil end

  return follower.path and 'file' or (follower.poller and 'poll' or 'none')
end

return follow
