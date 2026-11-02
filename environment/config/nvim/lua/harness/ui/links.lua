local lazy = require('core.lazy')

local fs = lazy('core.fs')
local Buffer = lazy('core.Buffer')
local Window = lazy('core.Window')
local console = lazy('core.console')
local INLINE = require('ui.markdown.Renderer').INLINE

local links = {}

links.TARGET = require('core.dataclass').enum({ 'file', 'buf' })

links.SCHEME = 'nvim://'

local exists_cache = {}

local function exists(path)
  if exists_cache[path] == nil then exists_cache[path] = fs.exists(path) end

  return exists_cache[path]
end

function links.clear_cache()
  exists_cache = {}
end

local function absolute(path, dir)
  local first = path:sub(1, 1)

  if first == '~' or first == '$' then path = fs.expand(path) end

  if path:sub(1, 1) == '/' then return path end

  return fs.joinpath(dir or fs.cwd(), path)
end

local function file(path, line, dir)
  local full = absolute(path, dir)

  if exists(full) and not fs.is_dir(full) then return { path = full, line = line } end
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
    if Buffer.exists(bufnr) then return { bufnr = bufnr } end
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
    console.open_url(target.url)
    return true
  end

  if target.path and fs.is_dir(target.path) then return false end

  local window = target.bufnr and Window.tab_with(Buffer(target.bufnr)) or Window.tab_edit(target.path)

  if target.line then
    window:set_cursor({ math.min(target.line, window:get_buffer():get_line_count()), 0 })
    window:normal('zz')
  end

  return true
end

return links
