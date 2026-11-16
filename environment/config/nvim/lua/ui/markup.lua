local text = require('core.text')
local widgets = require('ui.widgets')
local highlight = require('core.highlight')

local markup = {}

local TAG = '()(\\?)%[(/?[%w_.@]*)%]()'
local TOKEN = '{@([%w_%-]+)}'
local LONE = '^%s*{@([%w_%-]+)}%s*$'

function markup.group(tag)
  if tag == '' then return nil end

  local role = 'Ui' .. tag:sub(1, 1):upper() .. tag:sub(2)

  if highlight.exists(role) then return role end
  if tag:find('^[%u@]') and highlight.exists(tag) then return tag end
end

function markup.parse(line)
  local out, marks, stack = {}, {}, {}
  local width, at = 0, 1

  local function push(piece)
    if piece == '' then return end

    if stack[#stack] then marks[#marks + 1] = { hl = stack[#stack], from = width, to = width + #piece } end

    out[#out + 1] = piece
    width = width + #piece
  end

  for start, escape, tag, stop in line:gmatch(TAG) do
    local closes = tag == '/'
    local group = not closes and markup.group(tag)

    if escape ~= '' and (closes or group) then
      push(line:sub(at, start - 1))
      push('[' .. tag .. ']')
      at = stop
    elseif closes and #stack > 0 then
      push(line:sub(at, start - 1))
      stack[#stack] = nil
      at = stop
    elseif group then
      push(line:sub(at, start - 1))
      stack[#stack + 1] = group
      at = stop
    end
  end

  push(line:sub(at))

  return table.concat(out), marks
end

local function fetch(embed, id)
  local rows = embed(id)

  if rows == nil then error('no component ' .. id, 0) end

  return rows
end

local function split(line)
  local parts, at = {}, 1

  while true do
    local start, stop, id = line:find(TOKEN, at)

    if not start then break end

    parts[#parts + 1] = { text = line:sub(at, start - 1) }
    parts[#parts + 1] = { id = id }
    at = stop + 1
  end

  parts[#parts + 1] = { text = line:sub(at) }

  return parts
end

local function chunked(out, chunks)
  for _, chunk in ipairs(chunks) do
    if chunk[2] then out.marks[#out.marks + 1] = { hl = chunk[2], from = #out.plain, to = #out.plain + #chunk[1] } end

    out.plain = out.plain .. chunk[1]
  end
end

local function styled(out, line, tick)
  local plain, marks = markup.parse(widgets.expand(line, tick))
  local at = #out.plain

  for _, mark in ipairs(marks) do
    out.marks[#out.marks + 1] = { hl = mark.hl, from = at + mark.from, to = at + mark.to }
  end

  out.plain = out.plain .. plain
end

local function layout(lines, tick, embed)
  local outs = {}

  for _, line in ipairs(lines) do
    local id = embed and line:match(LONE)

    if id then
      for _, chunks in ipairs(fetch(embed, id)) do
        local out = { plain = '', marks = {} }

        chunked(out, chunks)
        outs[#outs + 1] = out
      end
    else
      local out = { plain = '', marks = {} }

      for _, part in ipairs(embed and split(line) or { { text = line } }) do
        if part.id then
          local rows = fetch(embed, part.id)

          if #rows > 1 then
            error('{@' .. part.id .. '} is ' .. #rows .. ' rows tall; put it on a line of its own', 0)
          end

          chunked(out, rows[1] or {})
        else
          styled(out, part.text, tick)
        end
      end

      outs[#outs + 1] = out
    end
  end

  return outs
end

function markup.render(lines, tick, pad, embed)
  pad = pad or ''

  local shown, highlights = {}, {}

  for row, out in ipairs(layout(lines, tick, embed)) do
    shown[row] = pad .. out.plain

    for _, mark in ipairs(out.marks) do
      highlights[#highlights + 1] = { hl = mark.hl, row = row - 1, from = mark.from + #pad, to = mark.to + #pad }
    end
  end

  return shown, highlights
end

function markup.width(lines, tick, embed)
  local width = 0

  for _, out in ipairs(layout(lines, tick or 0, embed)) do
    width = math.max(width, text.width(out.plain))
  end

  return width
end

return markup
