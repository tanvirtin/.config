local INLINE = require('ui.markdown.Renderer').INLINE

local links = {}

links.TARGET = require('core.dataclass').enum({ 'file', 'buf' })

links.SCHEME = 'nvim://'

local exists_cache = {}

local function exists(path)
  if exists_cache[path] == nil then exists_cache[path] = vim.uv.fs_stat(path) ~= nil end

  return exists_cache[path]
end

function links.clear_cache()
  exists_cache = {}
end

local function absolute(path, dir)
  local first = path:sub(1, 1)

  if first == '~' or first == '$' then path = vim.fn.expand(path) end

  if path:sub(1, 1) == '/' then return path end

  return vim.fs.joinpath(dir or vim.fn.getcwd(), path)
end

local function file(path, line, dir)
  local full = absolute(path, dir)

  if exists(full) then return { path = full, line = line } end
end

local function split_location(text)
  local path, line = text:match('^(.-)#L(%d+)')

  if not path then
    path, line = text:match('^(.-):(%d+)')
  end

  return path or text, tonumber(line)
end

local function from_scheme(target, dir)
  local rest = target:sub(#links.SCHEME + 1)
  local kind, value = rest:match('^(%a+)/(.+)$')

  if kind == links.TARGET.file then
    local path, line = split_location(value)
    return file(path, line, dir) or { path = absolute(path, dir), line = line, missing = true }
  end

  if kind == links.TARGET.buf then
    local bufnr = tonumber(value)
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then return { bufnr = bufnr } end
    return { bufnr = bufnr, missing = true }
  end
end

local PATH_LIKE = '^[%w%._%-/~]+$'

function links.resolve(kind, text, dir)
  if not text or text == '' then return nil end

  if kind == INLINE.link then
    if text:sub(1, #links.SCHEME) == links.SCHEME then return from_scheme(text, dir) end
    if text:match('^https?://') then return { url = text } end

    local path, line = split_location(text)
    return file(path, line, dir)
  end

  if kind == INLINE.code then
    local path, line = split_location(text)

    if not path:match(PATH_LIKE) or not (path:find('/', 1, true) or path:find('%.%w+$')) then return nil end

    return file(path, line, dir)
  end
end

links.ICONS = {
  path = { '󰈔 ', 'UiPath' },
  bufnr = { '󰈙 ', 'UiPath' },
  url = { '󰌹 ', 'UiAccent' },
  missing = { '󰈔 ', 'UiMuted' },
}

function links.icon(target)
  if target.missing then return links.ICONS.missing end
  if target.url then return links.ICONS.url end
  if target.bufnr then return links.ICONS.bufnr end

  return links.ICONS.path
end

function links.open(target)
  if not target or target.missing then return false end

  if target.url then
    vim.ui.open(target.url)
    return true
  end

  if target.bufnr then
    vim.cmd('tab sbuffer ' .. target.bufnr)
  else
    vim.cmd('tabnew ' .. vim.fn.fnameescape(target.path))
  end

  if target.line then
    local last = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { math.min(target.line, last), 0 })
    vim.cmd('normal! zz')
  end

  return true
end

return links
