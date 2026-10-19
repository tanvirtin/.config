local follow = {}

follow.DEBOUNCE_MS = 300
follow.GRACE_MS = 1500
follow.POLL_MS = 3000

local followers = {}
local arm

function follow.reload_session(session)
  return require('harness.hub').reload(session)
end

local function close(handle)
  if handle and not handle:is_closing() then
    handle:stop()
    handle:close()
  end
end

local function fingerprint(path)
  local stat = vim.uv.fs_stat(path)

  if not stat then return 'gone' end

  return table.concat({ stat.ino, stat.size, stat.mtime.sec, stat.mtime.nsec }, ':')
end

local function inode(path)
  local stat = vim.uv.fs_stat(path)

  return stat and stat.ino or nil
end

local function own_writes(session)
  if session:running() or session.reloading then return true end

  return session.turn_ended ~= nil and vim.uv.now() - session.turn_ended < follow.GRACE_MS
end

function follow.reload(session)
  local follower = followers[session]

  if not follower or follower.loading then return end

  follower.loading = true
  follower.seen = follower.path and fingerprint(follower.path) or follower.seen

  follow.reload_session(session):on_complete(function(err, changed)
    follower.loading = false

    if err then return end

    if changed then
      session.external = vim.uv.now()
      session:_notify({ kind = 'external' })
    end
  end)
  require('harness.async').drain()
end

function follow.check(session, absorb)
  local follower = followers[session]

  if not follower or follower.loading then return end

  local now = follower.path and fingerprint(follower.path)

  if follower.path and inode(follower.path) ~= follower.inode then arm(session, follower) end
  if follower.path and now == follower.seen then return end

  if own_writes(session) then
    follower.timer:stop()
    follower.timer:start(
      follow.GRACE_MS,
      0,
      vim.schedule_wrap(function()
        follow.check(session, true)
      end)
    )
    return
  end

  if absorb and follower.path then
    follower.seen = now
    return
  end

  follow.reload(session)
end

local function schedule(session)
  local follower = followers[session]

  if not follower or follower.timer:is_closing() then return end

  follower.timer:stop()
  follower.timer:start(
    follow.DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      follow.check(session)
    end)
  )
end

arm = function(session, follower)
  close(follower.handle)

  local handle = vim.uv.new_fs_event()

  if not handle then return end

  local ok = handle:start(follower.path, {}, function()
    vim.schedule(function()
      if followers[session] == follower then
        arm(session, follower)
        schedule(session)
      end
    end)
  end)

  if not ok then return close(handle) end

  follower.handle = handle
  follower.inode = inode(follower.path)

  vim.defer_fn(function()
    if followers[session] ~= follower then return end

    if inode(follower.path) ~= follower.inode then arm(session, follower) end
    if fingerprint(follower.path) ~= follower.seen then schedule(session) end
  end, follow.DEBOUNCE_MS)
end

local function visible(session)
  local buf = require('harness.ui.transcript').buffer_of(session)

  return buf ~= nil and #vim.fn.win_findbuf(buf) > 0
end

local function poll(session, follower)
  follower.poller = vim.uv.new_timer()
  follower.poller:start(
    follow.POLL_MS,
    follow.POLL_MS,
    vim.schedule_wrap(function()
      if followers[session] ~= follower or follower.loading then return end

      local path = session.agent and session.agent.transcript and session.agent:transcript(session.id)

      if path then
        close(follower.poller)
        follower.poller = nil
        follower.path = path
        follower.seen = fingerprint(path)
        arm(session, follower)
        return
      end

      if not visible(session) or not session.connection:supports('list') then return end

      require('harness.async').run(function()
        for _, entry in ipairs(session.connection:list_sessions(session.dir)) do
          if entry.sessionId == session.id then
            local changed = follower.updated and entry.updatedAt ~= follower.updated

            follower.updated = entry.updatedAt
            if changed and not own_writes(session) then follow.reload(session) end
          end
        end
      end)
    end)
  )
end

function follow.start(session)
  if followers[session] or not session.id then return followers[session] end

  local follower = { timer = vim.uv.new_timer() }
  local path = session.agent and session.agent.transcript and session.agent:transcript(session.id)

  followers[session] = follower

  if path then
    follower.path = path
    follower.seen = fingerprint(path)
    arm(session, follower)
  else
    poll(session, follower)
  end

  return follower
end

function follow.stop(session)
  local follower = followers[session]

  if not follower then return end

  followers[session] = nil
  close(follower.handle)
  close(follower.timer)
  close(follower.poller)
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
