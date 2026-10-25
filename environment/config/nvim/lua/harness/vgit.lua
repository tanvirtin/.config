local lazy = require('core.lazy')

local api = lazy('vgit.api')
local fs = require('core.fs')
local text = require('core.text')
local event = require('core.event')
local scene = lazy('vgit.settings.scene')
local symbols = lazy('vgit.settings.symbols')

local vgit = {}

vgit.COMMAND = 'VGit'

vgit.DIVIDER = ' │ '

vgit.LAYOUTS = { unified = true, split = true }

vgit.NUMBER_HL = { remove = 'GitSignsDelete', add = 'GitSignsAdd' }

vgit.BACKGROUND_HL = { remove = 'GitSignsDeleteLn', add = 'GitSignsAddLn' }

function vgit.preference()
  local ok, preference = pcall(function()
    return scene:get('diff_preference')
  end)

  if ok and vgit.LAYOUTS[preference] then return preference end

  return 'unified'
end

function vgit.layout(wanted)
  if vgit.LAYOUTS[wanted] then return wanted end

  return vgit.preference()
end

function vgit.void()
  local ok, symbol = pcall(function()
    return symbols:get('void')
  end)

  if ok and type(symbol) == 'string' and symbol ~= '' then return symbol end

  return '⣿'
end

local function void_text(width)
  local symbol = vgit.void()
  local cells = text.width(symbol)

  if cells <= 0 or width <= 0 then return nil end

  return string.rep(symbol, math.floor(width / cells))
end

local function numbered(digits, number)
  if not number then return string.rep(' ', digits) .. ' ' end

  return string.format('%' .. digits .. 'd ', number)
end

local function padded(cell, width)
  return cell .. string.rep(' ', math.max(0, width - text.width(cell)))
end

local function changes_for(changes, buftype)
  local map = {}

  for _, change in ipairs(changes or {}) do
    if change.buftype == buftype then map[change.lnum] = change end
  end

  return map
end

local function visible(marks, total, context)
  local ranges = {}

  for _, mark in ipairs(marks or {}) do
    local top = math.max(1, (mark.top or 1) - context)
    local bot = math.min(total, (mark.bot or mark.top or total) + context)

    if bot >= top then ranges[#ranges + 1] = { top, bot } end
  end

  table.sort(ranges, function(a, b)
    return a[1] < b[1]
  end)

  local merged = {}

  for _, range in ipairs(ranges) do
    local last = merged[#merged]

    if last and range[1] <= last[2] + 1 then
      last[2] = math.max(last[2], range[2])
    else
      merged[#merged + 1] = { range[1], range[2] }
    end
  end

  return merged
end

local function cells_of(diff, numbers)
  local previous, current = diff.previous_lines or {}, diff.current_lines or {}
  local previous_changes = changes_for(diff.lnum_changes, 'previous')
  local current_changes = changes_for(diff.lnum_changes, 'current')
  local digits = math.max(1, #tostring(math.max(#previous, 1)), #tostring(math.max(#current, 1)))
  local cells, old, new = {}, 1, 1

  for i = 1, #previous do
    local ptype = previous_changes[i] and previous_changes[i].type or 'context'
    local ctype = current_changes[i] and current_changes[i].type or 'context'
    local old_lnum, new_lnum

    if ptype ~= 'void' then
      old_lnum = old
      old = old + 1
    end

    if ctype ~= 'void' then
      new_lnum = new
      new = new + 1
    end

    cells[i] = {
      left = numbered(digits, numbers and old_lnum) .. (previous[i] or ''),
      right = numbered(digits, numbers and new_lnum) .. (current[i] or ''),
      old_text = previous[i] or '',
      new_text = current[i] or '',
      old_change = previous_changes[i],
      new_change = current_changes[i],
      ptype = ptype,
      ctype = ctype,
      old_lnum = old_lnum,
      new_lnum = new_lnum,
    }
  end

  return cells, digits
end

local function context(cell)
  return cell.ptype == 'context' and cell.ctype == 'context'
end

local function range_width(cells, range)
  local width = 0

  for i = range[1], range[2] do
    width = math.max(width, text.width(cells[i].left), text.width(cells[i].right))
  end

  return width
end

local function add_word(out, row, offset, change, line)
  local overlay = api.words(change, line)

  if overlay then out.words[#out.words + 1] = { row = row, col = offset + overlay.col, texts = overlay.texts } end
end

local function split_row(out, cell, width, digits)
  local row = #out.lines
  local left = padded(text.truncate(cell.left, width), width)
  local right = padded(text.truncate(cell.right, width), width)
  local right_col = #left + #vgit.DIVIDER
  local line = left .. vgit.DIVIDER .. right
  local left_bg, right_bg = vgit.BACKGROUND_HL[cell.ptype], vgit.BACKGROUND_HL[cell.ctype]
  local highlights = out.highlights

  if cell.ptype == 'void' then
    local fill = void_text(width)

    if fill then out.voids[#out.voids + 1] = { row = row, col = 0, text = fill } end
  end

  if cell.ctype == 'void' then
    local fill = void_text(width)

    if fill then out.voids[#out.voids + 1] = { row = row, col = right_col, text = fill } end
  end

  out.lines[#out.lines + 1] = line
  out.rows[#out.rows + 1] = {
    kind = cell.ptype == 'remove' and 'remove' or (cell.ctype == 'add' and 'add' or 'context'),
    old_lnum = cell.old_lnum,
    new_lnum = cell.new_lnum,
    old_code = cell.old_lnum and digits + 1 or nil,
    new_code = cell.new_lnum and right_col + digits + 1 or nil,
  }

  highlights[#highlights + 1] =
    { row = row, col_start = 0, col_end = digits, hl_group = vgit.NUMBER_HL[cell.ptype] or 'GitLineNr' }
  highlights[#highlights + 1] = {
    row = row,
    col_start = right_col,
    col_end = right_col + digits,
    hl_group = vgit.NUMBER_HL[cell.ctype] or 'GitLineNr',
  }

  if left_bg then highlights[#highlights + 1] = { row = row, col_start = 0, col_end = #left, hl_group = left_bg } end
  if right_bg then
    highlights[#highlights + 1] = { row = row, col_start = right_col, col_end = #line, hl_group = right_bg }
  end

  if cell.old_lnum then add_word(out, row, digits + 1, cell.old_change, cell.old_text) end
  if cell.new_lnum then add_word(out, row, right_col + digits + 1, cell.new_change, cell.new_text) end
end

local function unified_row(out, cell, kind, digits)
  local row = #out.lines
  local old = kind == 'remove'
  local line = old and cell.left or cell.right
  local highlights = out.highlights

  out.lines[#out.lines + 1] = line
  out.rows[#out.rows + 1] = {
    kind = kind,
    old_lnum = kind ~= 'add' and cell.old_lnum or nil,
    new_lnum = not old and cell.new_lnum or nil,
    old_code = old and digits + 1 or nil,
    new_code = not old and digits + 1 or nil,
  }

  highlights[#highlights + 1] =
    { row = row, col_start = 0, col_end = digits, hl_group = vgit.NUMBER_HL[kind] or 'GitLineNr' }

  if vgit.BACKGROUND_HL[kind] then
    highlights[#highlights + 1] = { row = row, col_start = 0, col_end = #line, hl_group = vgit.BACKGROUND_HL[kind] }
  end

  if old then
    add_word(out, row, digits + 1, cell.old_change, cell.old_text)
  elseif kind == 'add' then
    add_word(out, row, digits + 1, cell.new_change, cell.new_text)
  end
end

local function unified_range(out, cells, range, digits)
  local i = range[1]

  while i <= range[2] do
    if context(cells[i]) then
      unified_row(out, cells[i], 'context', digits)
      i = i + 1
    else
      local j = i

      while j <= range[2] and not context(cells[j]) do
        j = j + 1
      end

      for k = i, j - 1 do
        if cells[k].ptype == 'remove' then unified_row(out, cells[k], 'remove', digits) end
      end

      for k = i, j - 1 do
        if cells[k].ctype == 'add' then unified_row(out, cells[k], 'add', digits) end
      end

      i = j
    end
  end
end

function vgit.split(file, opts)
  local diff = api.diff(file.old_lines or {}, file.new_lines or {}, { layout = 'split' })
  local cells, digits = cells_of(diff, opts.numbers ~= false)
  local ranges = visible(diff.marks, #cells, opts.context or api.CONTEXT)
  local out = { layout = 'split', lines = {}, rows = {}, highlights = {}, words = {}, voids = {}, stat = diff.stat }
  local overflow = opts.overflow or 'truncate'

  if #ranges == 0 then return out end

  local limit = opts.width and math.floor((opts.width - 2 - text.width(vgit.DIVIDER)) / 2)

  if limit and limit < 12 then return nil end

  local fits, width = {}, 0

  for r, range in ipairs(ranges) do
    local needed = range_width(cells, range)

    fits[r] = not limit or needed <= limit
    if fits[r] then width = math.max(width, needed) end
  end

  if limit then
    if overflow == 'unified' and not vim.tbl_contains(fits, true) then return nil end

    width = limit
  end

  for r, range in ipairs(ranges) do
    if r > 1 then
      out.lines[#out.lines + 1] = ''
      out.rows[#out.rows + 1] = { kind = 'hunk' }
    end

    if fits[r] or overflow ~= 'unified' then
      for i = range[1], range[2] do
        split_row(out, cells[i], width, digits)
      end
    else
      unified_range(out, cells, range, digits)
    end
  end

  return out
end

function vgit.patch(file, opts)
  opts = opts or {}

  if vgit.layout(opts.layout) == 'split' then
    local split = vgit.split(file, opts)

    if split then return split end
  end

  return api.patch({ file }, vim.tbl_extend('force', { syntax = false }, opts))
end

function vgit.stat(file)
  return api.diff(file.old_lines, file.new_lines).stat or { added = 0, removed = 0 }
end

function vgit.patch_text(file, opts)
  return api.patch_text({ file }, opts)
end

function vgit.show(files, opts)
  opts = opts or {}

  local relative = vim.tbl_map(function(file)
    return vim.tbl_extend('force', file, { filename = file.filename and fs.relative_filename(file.filename) })
  end, files)
  local ok, shown = pcall(api.show, { files = relative, layout = opts.layout, keymaps = opts.keymaps })

  if not ok then return false, tostring(shown) end
  if not shown then return false, 'nothing to show' end

  return true
end

function vgit.git_diff(path)
  if not event.has_command(vgit.COMMAND) then return false, 'vgit is not available' end

  local ok, err = pcall(event.run_command, vgit.COMMAND, { 'diff', '--', path })

  if not ok then return false, tostring(err) end

  return true
end

return vgit
