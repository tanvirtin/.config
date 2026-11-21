local text = require('core.text')
local layer = require('ui.design.layer')
local Buffer = require('core.editor.Buffer')

local guides = {}

guides.NAMESPACE = Buffer.namespace('ui.guides')
guides.PRIORITY = layer.of('mark')
guides.HL = 'UiGuide'

local placed = {}
local icon

function guides.set_icon(fn)
  icon = fn
end

local function label_text(opts)
  if opts.step and opts.label then return string.format('%d. %s', opts.step, opts.label) end
  if opts.step then return string.format('%d.', opts.step) end
  if opts.label then return '- ' .. opts.label end
end

local function width_of(chunks)
  local width = 0

  for _, chunk in ipairs(chunks) do
    width = width + text.width(chunk[1])
  end

  return width
end

local function padded(chunks, width)
  local gap = width - width_of(chunks)

  if gap > 0 then chunks[#chunks + 1] = { string.rep(' ', gap), guides.HL } end

  return chunks
end

local function indent_of(buffer, line)
  local text = buffer:get_lines(line - 1, line)[1] or ''
  local tabstop = buffer:get_option('tabstop')
  local width = 0

  for char in text:match('^%s*'):gmatch('.') do
    width = char == '\t' and (width + tabstop - width % tabstop) or (width + 1)
  end

  return width
end

function guides.mark(owner, buffer, opts)
  local last = buffer:get_line_count()
  local from = math.max(1, math.min(opts.from, last))
  local to = math.max(from, math.min(opts.to or from, last))
  local note = label_text(opts)

  if not note then return nil end

  local body = { { ' ' .. note .. ' ', guides.HL } }
  local portrait = icon and icon()
  local lines = { body }

  if portrait then
    local title = { { ' ', guides.HL } }

    for _, chunk in ipairs(portrait) do
      title[#title + 1] = { chunk[1], { guides.HL, chunk[2] } }
    end

    local width = math.max(width_of(title), width_of(body))

    lines = { padded(title, width), padded(body, width) }
  end
  local indent = indent_of(buffer, from) - 1

  if indent > 0 then
    for _, line in ipairs(lines) do
      table.insert(line, 1, { string.rep(' ', indent) })
    end
  end

  local id = buffer:set_extmark(guides.NAMESPACE, from - 1, 0, {
    virt_lines = lines,
    virt_lines_above = true,
    priority = guides.PRIORITY,
  })

  if not id then return nil end

  placed[owner] = placed[owner] or {}
  table.insert(
    placed[owner],
    { bufnr = buffer.bufnr, id = id, from = from, to = to, label = opts.label, step = opts.step }
  )

  return id
end

function guides.jump(window, direction)
  local buffer = window:get_buffer()
  local row = window:get_cursor()[1] - 1
  local rows = {}

  for _, mark in ipairs(buffer:get_extmarks(guides.NAMESPACE)) do
    rows[#rows + 1] = mark[2]
  end

  if #rows == 0 then return nil end

  table.sort(rows)

  local target = direction > 0 and rows[1] or rows[#rows]

  for i = 1, #rows do
    local candidate = direction > 0 and rows[i] or rows[#rows - i + 1]

    if (direction > 0 and candidate > row) or (direction < 0 and candidate < row) then
      target = candidate
      break
    end
  end

  window:set_cursor({ target + 1, 0 })
  window:scroll_to('center')

  return target + 1
end

function guides.list(owner)
  return vim.deepcopy(placed[owner] or {})
end

function guides.clear(owner, buffer)
  local kept, cleared = {}, 0

  for _, guide in ipairs(placed[owner] or {}) do
    if buffer and guide.bufnr ~= buffer.bufnr then
      kept[#kept + 1] = guide
    else
      Buffer(guide.bufnr):del_extmark(guides.NAMESPACE, guide.id)
      cleared = cleared + 1
    end
  end

  placed[owner] = #kept > 0 and kept or nil

  return cleared
end

return guides
