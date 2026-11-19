local paint = {}

local max, min = math.max, math.min

paint.KINDS = { 'rectangle', 'border', 'text', 'image', 'scissor_start', 'scissor_end', 'custom' }

local painters = {
  rectangle = function(bitmap, command)
    bitmap:rect(command.x, command.y, command.w, command.h, command.color, command.opacity or 1, command.radius or 0)
  end,
  border = function(bitmap, command)
    bitmap:border(
      command.x,
      command.y,
      command.w,
      command.h,
      command.width or 1,
      command.color,
      command.opacity or 1,
      command.radius or 0
    )
  end,
  custom = function(bitmap, command)
    command.draw(bitmap, command)
  end,
}

local function intersect(outer, inner)
  if not outer then return { x = inner.x, y = inner.y, w = max(0, inner.w), h = max(0, inner.h) } end

  local x, y = max(outer.x, inner.x), max(outer.y, inner.y)
  local right, bottom = min(outer.x + outer.w, inner.x + inner.w), min(outer.y + outer.h, inner.y + inner.h)

  return { x = x, y = y, w = max(0, right - x), h = max(0, bottom - y) }
end

local function apply(bitmap, clip)
  if clip then
    bitmap:clip(clip.x, clip.y, clip.w, clip.h)
  else
    bitmap:unclip()
  end
end

local function shifted(command, ox, oy)
  if ox == 0 and oy == 0 then return command end

  local copy = {}

  for key, value in pairs(command) do
    copy[key] = value
  end

  if copy.x then copy.x = copy.x - ox end
  if copy.y then copy.y = copy.y - oy end

  return copy
end

function paint.run(bitmap, commands, ox, oy)
  local stack, current = {}, nil
  ox, oy = ox or 0, oy or 0

  for _, original in ipairs(commands) do
    local command = shifted(original, ox, oy)
    local kind = command.kind

    if kind == 'scissor_start' then
      stack[#stack + 1] = current or false
      current = intersect(current, command)
      apply(bitmap, current)
    elseif kind == 'scissor_end' then
      if #stack > 0 then
        current = stack[#stack] or nil
        stack[#stack] = nil
        apply(bitmap, current)
      end
    elseif painters[kind] then
      painters[kind](bitmap, command)
    elseif kind ~= 'text' and kind ~= 'image' then
      error('unknown render command ' .. tostring(kind), 0)
    end
  end

  bitmap:unclip()

  return bitmap
end

return paint
