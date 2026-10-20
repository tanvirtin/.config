local lazy = require('core.lazy')

local Object = lazy('core.Object')
local Timer = lazy('core.Timer')

local FileWatch = Object:extend()

FileWatch.DEBOUNCE_MS = 80

function FileWatch.stat(path)
  return path and vim.uv.fs_stat(path) or nil
end

function FileWatch.exists(path)
  local stat = FileWatch.stat(path)

  return stat ~= nil and stat.type == 'file'
end

function FileWatch.fingerprint(path)
  local stat = FileWatch.stat(path)

  if not stat then return 'gone' end

  return table.concat({ stat.ino, stat.size, stat.mtime.sec, stat.mtime.nsec }, ':')
end

local function inode(path)
  local stat = FileWatch.stat(path)

  return stat and stat.ino or nil
end

function FileWatch:constructor(path, opts)
  opts = opts or {}

  return {
    path = path,
    debounce_ms = opts.debounce_ms or FileWatch.DEBOUNCE_MS,
    on_change = opts.on_change or function() end,
    _handle = nil,
    _inode = nil,
    _armed = nil,
    _debounce = Timer(),
    _verify = Timer(),
    _stopped = false,
  }
end

local function close(handle)
  if handle and not handle:is_closing() then
    handle:stop()
    handle:close()
  end
end

function FileWatch:_changed()
  if self._stopped then return end

  self._debounce:after(self.debounce_ms, function()
    if not self._stopped then self.on_change(self) end
  end)
end

function FileWatch:_arm()
  close(self._handle)
  self._handle = nil

  local handle = vim.uv.new_fs_event()

  if not handle then return false end

  local ok = handle:start(self.path, {}, function()
    vim.schedule(function()
      if self._stopped then return end
      self:_arm()
      self:_changed()
    end)
  end)

  if not ok then
    close(handle)
    return false
  end

  self._handle = handle
  self._inode = inode(self.path)
  self._armed = FileWatch.fingerprint(self.path)

  self._verify:after(self.debounce_ms, function()
    if self._stopped then return end

    local changed = FileWatch.fingerprint(self.path) ~= self._armed

    if inode(self.path) ~= self._inode then self:_arm() end
    if changed then self:_changed() end
  end)

  return true
end

function FileWatch:start()
  self._stopped = false

  return self:_arm()
end

function FileWatch:rearm()
  if self._stopped then return false end

  return self:_arm()
end

function FileWatch:is_watching()
  return not self._stopped and self._handle ~= nil
end

function FileWatch:stop()
  self._stopped = true
  close(self._handle)
  self._handle = nil
  self._debounce:close()
  self._verify:close()

  return self
end

return FileWatch
