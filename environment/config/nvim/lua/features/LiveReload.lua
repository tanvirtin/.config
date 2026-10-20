local lazy = require('core.lazy')

local Buffer = lazy('core.Buffer')
local FileWatch = lazy('core.FileWatch')
local Object = lazy('core.Object')
local Timer = lazy('core.Timer')
local Window = lazy('core.Window')
local buffers = lazy('core.buffers')
local console = lazy('core.console')
local event = lazy('core.event')
local text = lazy('core.text')

require('ui.hl')

local LiveReload = Object:extend()

LiveReload.MAX = 128
LiveReload.DEBOUNCE_MS = 80
LiveReload.FLASH_MS = 4000
LiveReload.FLASH_MAX_LINES = 20000
LiveReload.NAMESPACE = Buffer.namespace('features.live_reload')

function LiveReload:constructor(opts)
  opts = opts or {}

  return {
    max = opts.max or LiveReload.MAX,
    debounce_ms = opts.debounce_ms or LiveReload.DEBOUNCE_MS,
    _watched = {},
    _count = 0,
    _clock = 0,
    _warned = {},
    _disposers = {},
  }
end

local function path_of(buffer)
  if not buffer:is_loaded() or buffer:get_option('buftype') ~= '' then return nil end

  local name = buffer:get_name()

  return name ~= '' and FileWatch.exists(name) and name or nil
end

function LiveReload:stop(buffer)
  local entry = self._watched[buffer.bufnr]

  if not entry then return end

  entry.watch:stop()
  self._watched[buffer.bufnr] = nil
  self._count = self._count - 1
end

function LiveReload:stop_all()
  for bufnr in pairs(self._watched) do
    self:stop(Buffer(bufnr))
  end
end

function LiveReload:_evict()
  local oldest, oldest_used

  for bufnr, entry in pairs(self._watched) do
    if not oldest_used or entry.used < oldest_used then
      oldest, oldest_used = bufnr, entry.used
    end
  end

  if oldest then self:stop(Buffer(oldest)) end
end

function LiveReload:_flash(buffer, old)
  if #old > LiveReload.FLASH_MAX_LINES then return end

  buffer:clear_namespace(LiveReload.NAMESPACE)

  for _, row in ipairs(text.changed_rows(old, buffer:get_lines())) do
    buffer:set_extmark(LiveReload.NAMESPACE, row, 0, { line_hl_group = 'UiExternalChange' })
  end

  Timer.defer(LiveReload.FLASH_MS, function()
    buffer:clear_namespace(LiveReload.NAMESPACE)
  end)
end

function LiveReload:_reload(buffer)
  if not self._watched[buffer.bufnr] then return end

  if not path_of(buffer) then
    buffer:checktime()
    return self:stop(buffer)
  end

  local before = not buffer:is_modified() and buffer:get_lines() or nil
  local tick = buffer:get_changedtick()

  buffer:checktime()

  if before and buffer:is_valid() and buffer:get_changedtick() ~= tick then self:_flash(buffer, before) end
end

function LiveReload:start(buffer)
  local path = path_of(buffer)

  if not path then return self:stop(buffer) end

  self._clock = self._clock + 1

  local entry = self._watched[buffer.bufnr]

  if entry and entry.path == path then
    entry.used = self._clock
    return
  end

  self:stop(buffer)

  if self._count >= self.max then self:_evict() end

  local watch = FileWatch(path, {
    debounce_ms = self.debounce_ms,
    on_change = function()
      self:_reload(buffer)
    end,
  })

  if not watch:start() then return end

  self._watched[buffer.bufnr] = { path = path, used = self._clock, watch = watch }
  self._count = self._count + 1
end

function LiveReload:is_watching(buffer)
  return self._watched[buffer.bufnr] ~= nil
end

function LiveReload:count()
  return self._count
end

function LiveReload:_warn_once(buffer, message)
  local key = buffer.bufnr .. ':' .. FileWatch.fingerprint(buffer:get_name())

  if self._warned[key] then return end

  self._warned[key] = true
  console.warn(message)
end

function LiveReload:on_file_changed(buffer)
  local name = text.display_path(buffer:get_name())

  if event.file_changed_reason() == 'deleted' then
    event.answer_file_changed('')
    self:_warn_once(buffer, name .. ' was deleted on disk. The buffer keeps its text; :w writes it back.')
  elseif buffer:is_modified() then
    event.answer_file_changed('')
    self:_warn_once(buffer, name .. ' changed on disk while you have unsaved changes. :DiffDisk compares them.')
  else
    event.answer_file_changed('reload')
  end
end

function LiveReload:diff_disk(buffer)
  buffer = buffer or Buffer(0)

  local path = buffer:get_name()

  if path == '' or not FileWatch.exists(path) then
    console.info('DiffDisk: this buffer has no file on disk')
    return
  end

  local window = Window.tab_with(buffer):diff_this()
  local disk = Buffer():create(false, true)

  disk:set_option('bufhidden', 'wipe')
  disk:set_lines(text.read_file(path))
  disk:set_option('modifiable', false)
  disk:set_option('filetype', buffer:get_filetype())
  pcall(disk.set_name, disk, 'disk://' .. path)
  window:split_right(disk):diff_this()
end

function LiveReload:register_events()
  local function each(names, fn)
    self._disposers[#self._disposers + 1] = event.disposable_on(names, function(args)
      fn(Buffer(args.buf))
    end)
  end

  each({ 'BufReadPost', 'BufWritePost', 'BufFilePost', 'BufEnter' }, function(buffer)
    self:start(buffer)
  end)
  each({ 'BufUnload', 'BufDelete', 'BufWipeout', 'BufFilePre' }, function(buffer)
    self:stop(buffer)
  end)
  each('FileChangedShell', function(buffer)
    self:on_file_changed(buffer)
  end)

  self._disposers[#self._disposers + 1] = event.disposable_on('VimLeavePre', function()
    self:stop_all()
  end)
  self._disposers[#self._disposers + 1] = event.command('DiffDisk', function()
    self:diff_disk()
  end, { desc = 'Compare the buffer with its file on disk, in a new tab' })

  for _, buffer in ipairs(buffers.list()) do
    self:start(buffer)
  end

  return self
end

function LiveReload:cleanup()
  self:stop_all()

  for _, dispose in ipairs(self._disposers) do
    dispose()
  end

  self._disposers = {}
  self._warned = {}
end

return LiveReload
