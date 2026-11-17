local widgets = {}

widgets.CYCLE = 20
widgets.LEVELS = { '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' }

local function number(value, fallback)
  return tonumber(value) or fallback
end

local function percent(value, tick)
  if value == '@' then return (tick % (widgets.CYCLE + 1)) * 100 / widgets.CYCLE end

  return math.max(0, math.min(100, number(value, 0)))
end

widgets.BUILD = {
  bar = function(args, tick)
    local width = math.max(1, math.floor(number(args[2], 20)))
    local filled = math.floor(percent(args[1], tick) * width / 100 + 0.5)

    return string.format('[added]%s[/][muted]%s[/]', ('█'):rep(filled), ('░'):rep(width - filled))
  end,
  spark = function(args)
    local values, top = {}, 0

    for value in (args[1] or ''):gmatch('[^,]+') do
      values[#values + 1] = number(value, 0)
      top = math.max(top, values[#values])
    end

    return table.concat(vim.tbl_map(function(value)
      local level = top > 0 and math.max(1, math.ceil(value / top * #widgets.LEVELS)) or 1

      return widgets.LEVELS[level]
    end, values))
  end,
  rule = function(args)
    return (args[2] or '─'):rep(math.max(0, math.floor(number(args[1], 20))))
  end,
  rep = function(args)
    return (args[1] or ''):rep(math.max(0, math.floor(number(args[2], 1))))
  end,
  spin = function(_, tick)
    local frames = require('ui.pixel.indicators').GLYPHS.busy

    return frames[tick % #frames + 1]
  end,
}

function widgets.expand(line, tick)
  return (
    line:gsub('{(%l+)([^{}]*)}', function(name, rest)
      local build = widgets.BUILD[name]

      if not build or (rest ~= '' and rest:sub(1, 1) ~= ':') then return nil end

      return build(vim.split(rest:sub(2), ':', { plain = true }), tick or 0)
    end)
  )
end

return widgets
