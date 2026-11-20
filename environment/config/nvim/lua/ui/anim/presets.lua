local presets = {}

local function burst(at, start_ms, extra)
  return vim.tbl_extend('force', {
    type = 'emitter',
    at = at,
    start_ms = start_ms,
    burst = 36,
    life_ms = { 500, 1100 },
    speed = { 6, 18 },
    angle = { 0, 360 },
    gravity = 12,
    drag = 0.6,
    glyphs = { '✺', '✹', '✦', '•', '·' },
    hl = { 'warn', 'accent', 'muted' },
  }, extra or {})
end

presets.fireworks = {
  duration_ms = 3200,
  actors = {
    burst({ '30%', '30%' }, 0),
    burst({ '65%', '22%' }, 500, { hl = { 'info', 'accent', 'muted' } }),
    burst({ '48%', '38%' }, 1000, { hl = { 'added', 'info', 'muted' } }),
    burst({ '78%', '34%' }, 1500, { hl = { 'error', 'warn', 'muted' } }),
    burst({ '20%', '20%' }, 2000, { hl = { 'accent', 'warn', 'muted' } }),
  },
}

presets.confetti = {
  duration_ms = 3500,
  actors = {
    {
      type = 'emitter',
      at = { '50%', '70%' },
      burst = 48,
      life_ms = { 1400, 2600 },
      speed = { 10, 22 },
      angle = { 55, 125 },
      gravity = 16,
      drag = 0.5,
      mixed = true,
      glyphs = { '■', '▪', '◆', '●' },
      hl = { 'accent', 'warn', 'info', 'added', 'error' },
    },
  },
}

presets.sparks = {
  duration_ms = 1400,
  actors = {
    {
      type = 'emitter',
      at = { '50%', '50%' },
      burst = 16,
      life_ms = { 350, 800 },
      speed = { 6, 14 },
      angle = { 20, 160 },
      gravity = 26,
      glyphs = { '✦', '•', '·' },
      hl = { 'accent', 'warn', 'muted' },
    },
  },
}

presets.rain = {
  duration_ms = 4000,
  actors = {
    {
      type = 'emitter',
      at = { '50%', 0 },
      spread = '100%',
      rate = 45,
      stop_ms = 3600,
      life_ms = { 700, 1000 },
      speed = { 14, 18 },
      angle = 270,
      glyphs = { '│', '╎', '¦' },
      hl = { 'info', 'muted' },
    },
  },
}

presets.snow = {
  duration_ms = 6000,
  actors = {
    {
      type = 'emitter',
      at = { '50%', 0 },
      spread = '100%',
      rate = 14,
      stop_ms = 5000,
      life_ms = { 2500, 3500 },
      speed = { 2, 4 },
      angle = { 250, 290 },
      glyphs = { '❄', '❅', '*', '·' },
      hl = { 'info', 'muted' },
    },
  },
}

presets.matrix = {
  duration_ms = 5000,
  actors = {
    { type = 'curtain', color = '#000000', blend = { { 0, 100 }, { 600, 45 }, { 4400, 45 }, { 5000, 100 } } },
    { type = 'text', effect = 'rain', ms = 5000 },
  },
}

presets.glitch = { duration_ms = 1400, actors = { { type = 'text', effect = 'glitch', ms = 1400 } } }
presets.typewriter = { duration_ms = 2500, actors = { { type = 'text', effect = 'reveal', ms = 2400 } } }
presets.shimmer = { duration_ms = 1600, actors = { { type = 'text', effect = 'sweep', ms = 1500 } } }

presets.flash = {
  duration_ms = 600,
  actors = { { type = 'curtain', color = '#ffffff', blend = { { 0, 100 }, { 80, 30 }, { 600, 100 } } } },
}

local function wave(start_ms, color)
  return {
    type = 'shape',
    shape = 'ring',
    at = { '50%', '50%' },
    color = color,
    thick = 3,
    show_ms = start_ms,
    r = { { start_ms, 0 }, { start_ms + 1200, 14, 'out_cubic' } },
    opacity = { { start_ms, 90 }, { start_ms + 1200, 0, 'out_quad' } },
  }
end

presets.ripple = {
  duration_ms = 1800,
  actors = { wave(0, 'accent'), wave(250, 'info'), wave(500, 'muted') },
}

function presets.names()
  local names = vim.tbl_filter(function(name)
    return type(presets[name]) == 'table'
  end, vim.tbl_keys(presets))

  table.sort(names)

  return names
end

return presets
