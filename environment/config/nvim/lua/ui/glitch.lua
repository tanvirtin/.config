local static = require('ui.pixel.static')

local glitch = {}

glitch.GLYPHS = { '░', '▒', '▓', '▚', '▞' }

local function hit(col, seed, density)
  return static.hash(col, 7, seed) < density * 100
end

local function glyph(col, seed)
  return glitch.GLYPHS[static.hash(col, 3, seed) % #glitch.GLYPHS + 1]
end

function glitch.cols(text, density, seed, from)
  local out = {}

  if density <= 0 then return out end

  for col = (from or 0) + 1, #text do
    local byte = text:byte(col)

    if byte > 32 and byte < 127 and hit(col, seed, density) then out[#out + 1] = { col - 1, glyph(col, seed) } end
  end

  return out
end

glitch.SNOW = { ' ', ' ', ' ', '░', '░', '░', '▒', '▒', '▓' }

function glitch.snow(width, seed, row)
  local out = {}

  for col = 1, width do
    out[col] = glitch.SNOW[static.hash(col, row or 0, seed) % #glitch.SNOW + 1]
  end

  return table.concat(out)
end

function glitch.scramble(text, density, seed)
  if density <= 0 then return text end

  local out = {}

  for col = 1, #text do
    local byte = text:byte(col)

    if byte > 32 and byte < 127 and hit(col, seed, density) then
      out[#out + 1] = glyph(col, seed)
    else
      out[#out + 1] = text:sub(col, col)
    end
  end

  return table.concat(out)
end

return glitch
