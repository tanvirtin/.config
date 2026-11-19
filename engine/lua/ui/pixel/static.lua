local bit = require('bit')

local static = {}

static.BLOCK = 4

function static.hash(x, y, step)
  return bit.band(bit.bxor(x * 73856093, y * 19349663, (step % 65536) * 83492791), 0x7fffffff) % 100
end

function static.block(bitmap, x, y, rgb, alpha, size)
  size = size or static.BLOCK

  bitmap:rect(x * size, y * size, size, size, rgb, alpha or 1)
end

function static.noise(bitmap, x, y, width, height, step, rgb, opts)
  opts = opts or {}

  local density = opts.density or 50
  local low, high = opts.low or 0.2, opts.high or 0.8

  for gy = y, y + height - 1 do
    for gx = x, x + width - 1 do
      local h = static.hash(gx, gy, step)

      if h < density then static.block(bitmap, gx, gy, rgb, low + (high - low) * h / 100, opts.size) end
    end
  end
end

function static.sprite(bitmap, art, legend, step, opts)
  opts = opts or {}

  local ox, oy = opts.ox or 0, opts.oy or 0

  for r, row in ipairs(art) do
    for c = 1, #row do
      local entry = legend[row:sub(c, c)]

      if entry then
        local gx, gy = ox + c - 1, oy + r - 1
        local rgb, alpha

        if type(entry) == 'function' then
          rgb, alpha = entry(gx, gy, step)
        else
          rgb, alpha = entry[1], entry[2]
        end

        if rgb then static.block(bitmap, gx, gy, rgb, alpha, opts.size) end
      end
    end
  end
end

return static
