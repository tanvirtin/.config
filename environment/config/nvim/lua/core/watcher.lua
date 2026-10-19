require('ui.hl')

local watcher = {}

watcher.MAX = 128
watcher.DEBOUNCE_MS = 80
watcher.FLASH_MS = 4000
watcher.FLASH_MAX_LINES = 20000
watcher.NAMESPACE = vim.api.nvim_create_namespace('core.watcher')

local watched = {}
local count = 0
local warned = {}

local function close(handle)
  if handle and not handle:is_closing() then
    handle:stop()
    handle:close()
  end
end

local function path_of(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return nil end
  if vim.bo[buf].buftype ~= '' then return nil end

  local name = vim.api.nvim_buf_get_name(buf)

  if name == '' then return nil end

  local stat = vim.uv.fs_stat(name)

  return stat and stat.type == 'file' and name or nil
end

function watcher.stop(buf)
  local entry = watched[buf]

  if not entry then return end

  close(entry.handle)
  close(entry.timer)
  watched[buf] = nil
  count = count - 1
end

function watcher.stop_all()
  for buf in pairs(watched) do
    watcher.stop(buf)
  end
end

local function evict()
  local oldest, oldest_used

  for buf, entry in pairs(watched) do
    if not oldest_used or entry.used < oldest_used then
      oldest, oldest_used = buf, entry.used
    end
  end

  if oldest then watcher.stop(oldest) end
end

local fire

local function fingerprint(path)
  local stat = vim.uv.fs_stat(path)

  if not stat then return 'gone' end

  return table.concat({ stat.ino, stat.size, stat.mtime.sec, stat.mtime.nsec }, ':')
end

local function verify(buf, entry)
  vim.defer_fn(function()
    if watched[buf] == entry and fingerprint(entry.path) ~= entry.fingerprint then fire(buf) end
  end, watcher.DEBOUNCE_MS)
end

local function arm(buf, entry)
  close(entry.handle)

  local handle = vim.uv.new_fs_event()

  if not handle then return false end

  local ok = handle:start(entry.path, {}, function()
    if not entry.timer or entry.timer:is_closing() then return end

    entry.timer:stop()
    entry.timer:start(
      watcher.DEBOUNCE_MS,
      0,
      vim.schedule_wrap(function()
        fire(buf)
      end)
    )
  end)

  if not ok then
    close(handle)
    return false
  end

  entry.handle = handle
  entry.fingerprint = fingerprint(entry.path)
  verify(buf, entry)

  return true
end

local clock = 0

function watcher.start(buf)
  local path = path_of(buf)

  if not path then return watcher.stop(buf) end

  clock = clock + 1

  local entry = watched[buf]

  if entry and entry.path == path then
    entry.used = clock
    return
  end

  watcher.stop(buf)

  if count >= watcher.MAX then evict() end

  entry = { path = path, used = clock, timer = vim.uv.new_timer() }

  if not arm(buf, entry) then return close(entry.timer) end

  watched[buf] = entry
  count = count + 1
end

local function flash(buf, old)
  if #old > watcher.FLASH_MAX_LINES then return end

  local new = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local diff = (vim.text and vim.text.diff) or vim.diff
  local hunks = diff(table.concat(old, '\n') .. '\n', table.concat(new, '\n') .. '\n', { result_type = 'indices' })

  vim.api.nvim_buf_clear_namespace(buf, watcher.NAMESPACE, 0, -1)

  for _, hunk in ipairs(hunks or {}) do
    local start, length = hunk[3], hunk[4]
    local first = math.max(start - 1, 0)
    local last = length > 0 and start + length - 2 or first

    for row = first, math.min(last, #new - 1) do
      pcall(vim.api.nvim_buf_set_extmark, buf, watcher.NAMESPACE, row, 0, { line_hl_group = 'UiExternalChange' })
    end
  end

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, watcher.NAMESPACE, 0, -1) end
  end, watcher.FLASH_MS)
end

fire = function(buf)
  local entry = watched[buf]

  if not entry then return end

  if not path_of(buf) then
    vim.cmd.checktime(buf)
    return watcher.stop(buf)
  end

  arm(buf, entry)

  local before = not vim.bo[buf].modified and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or nil
  local tick = vim.api.nvim_buf_get_changedtick(buf)

  vim.cmd.checktime(buf)

  if before and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_changedtick(buf) ~= tick then
    flash(buf, before)
  end
end

function watcher.is_watching(buf)
  return watched[buf] ~= nil
end

function watcher.count()
  return count
end

local function warn_once(buf, message)
  local stat = vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
  local key = buf .. ':' .. (stat and stat.mtime.sec .. '.' .. stat.mtime.nsec or 'gone')

  if warned[key] then return end

  warned[key] = true
  vim.notify(message, vim.log.levels.WARN)
end

function watcher.on_file_changed(buf)
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':~:.')
  local reason = vim.v.fcs_reason

  if reason == 'deleted' then
    vim.v.fcs_choice = ''
    warn_once(buf, name .. ' was deleted on disk. The buffer keeps its text; :w writes it back.')
  elseif vim.bo[buf].modified then
    vim.v.fcs_choice = ''
    warn_once(buf, name .. ' changed on disk while you have unsaved changes. :DiffDisk compares them.')
  else
    vim.v.fcs_choice = 'reload'
  end
end

function watcher.diff_disk(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  local path = vim.api.nvim_buf_get_name(buf)

  if path == '' or vim.fn.filereadable(path) ~= 1 then
    vim.notify('DiffDisk: this buffer has no file on disk', vim.log.levels.INFO)
    return
  end

  local filetype = vim.bo[buf].filetype

  vim.cmd('tab sbuffer ' .. buf)
  vim.cmd('diffthis')
  vim.cmd('vertical rightbelow new')

  local disk = vim.api.nvim_get_current_buf()

  vim.bo[disk].buftype = 'nofile'
  vim.bo[disk].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(disk, 0, -1, false, vim.fn.readfile(path))
  vim.bo[disk].modifiable = false
  vim.bo[disk].filetype = filetype
  pcall(vim.api.nvim_buf_set_name, disk, 'disk://' .. path)
  vim.cmd('diffthis')
end

function watcher.teardown()
  watcher.stop_all()
  pcall(vim.api.nvim_del_augroup_by_name, 'core.watcher')
  pcall(vim.api.nvim_del_user_command, 'DiffDisk')
  warned = {}
end

function watcher.setup()
  local group = vim.api.nvim_create_augroup('core.watcher', { clear = true })

  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'BufFilePost', 'BufEnter' }, {
    group = group,
    callback = function(args)
      watcher.start(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufUnload', 'BufDelete', 'BufWipeout', 'BufFilePre' }, {
    group = group,
    callback = function(args)
      watcher.stop(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = watcher.stop_all })

  vim.api.nvim_create_autocmd('FileChangedShell', {
    group = group,
    callback = function(args)
      watcher.on_file_changed(args.buf)
    end,
  })

  vim.api.nvim_create_user_command('DiffDisk', function()
    watcher.diff_disk()
  end, { desc = 'Compare the buffer with its file on disk, in a new tab' })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    watcher.start(buf)
  end
end

return watcher
