local graphics = require('core.editor.graphics')
local Layer = require('ui.anim.Layer')
local presets = require('ui.anim.presets')
local spec = require('ui.anim.spec')

local eq = assert.are.same

local function floats()
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative ~= ''
  end, vim.api.nvim_list_wins())
end

local function fails(scene)
  local ok, err = pcall(spec.build, scene)

  eq(false, ok)

  return err
end

describe('ui.anim.spec:', function()
  local original, drawn

  before_each(function()
    vim.cmd('silent! only!')
    drawn = {}
    original = { available = Layer.available, draw = graphics.draw, delete = graphics.delete }
    graphics.draw = function(_, _, width, height, place)
      drawn[#drawn + 1] = { width = width, height = height, place = place }
    end
    graphics.delete = function() end
  end)

  after_each(function()
    Layer.available, graphics.draw, graphics.delete = original.available, original.draw, original.delete
  end)

  local function pixels()
    Layer.available = function()
      return true
    end
  end

  it('names every preset, and builds each one where pixels are available', function()
    pixels()

    eq({
      'confetti',
      'fireworks',
      'flash',
      'glitch',
      'matrix',
      'rain',
      'ripple',
      'shimmer',
      'snow',
      'sparks',
      'typewriter',
    }, presets.names())

    for _, name in ipairs(presets.names()) do
      local stage = spec.build({ preset = name })

      stage:update(0)
      stage:update(stage.duration / 2)
      eq(nil, stage.error)
      stage:stop()
    end

    eq({}, floats())
  end)

  it('merges a scene over its preset: the duration, more actors, and where it happens', function()
    local scene = spec.expand({
      preset = 'sparks',
      duration_ms = 900,
      at = { 3, 4 },
      actors = { { type = 'curtain', blend = 50 } },
    })

    eq(900, scene.duration_ms)
    eq({ 'emitter', 'curtain' }, { scene.actors[1].type, scene.actors[2].type })
    eq({ 3, 4 }, scene.actors[1].at)
    eq(nil, presets.sparks.actors[2])
  end)

  it('glides a sprite from at to to, resolving percentages against the screen', function()
    local stage = spec.build({
      actors = {
        { type = 'sprite', lines = { 'hi' }, at = { 0, '50%' }, to = { '50%', '50%' }, ms = 100, ease = 'linear' },
      },
    })
    local float = floats()[1]
    local row = math.floor((vim.o.lines - 1) * 0.5 + 0.5)

    eq({ row, 0 }, { vim.api.nvim_win_get_config(float).row, vim.api.nvim_win_get_config(float).col })

    stage:update(100)
    eq(math.floor(vim.o.columns * 0.5 + 0.5), vim.api.nvim_win_get_config(float).col)
    eq({ 'hi' }, vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float), 0, -1, false))

    stage:stop()
    eq({}, floats())
  end)

  it('fades a sprite in and out through its blend', function()
    local stage = spec.build({
      actors = { { type = 'sprite', lines = { 'hi' }, fade = 'inout', fade_ms = 100, life_ms = 400 } },
    })
    local float = floats()[1]

    eq(100, vim.wo[float].winblend)
    stage:update(100)
    eq(0, vim.wo[float].winblend)
    stage:update(400)
    eq(100, vim.wo[float].winblend)
    stage:stop()
  end)

  it('draws an emitter as glyphs in floats where there are no pixels', function()
    local stage = spec.build({
      actors = { { type = 'emitter', at = { 10, 5 }, burst = 3, speed = 0, life_ms = 500, glyphs = { '*' }, seed = 1 } },
    })

    stage:update(0)
    eq(nil, stage.layer)
    eq(3, #floats())
    eq({ '*' }, vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(floats()[1]), 0, -1, false))

    stage:stop()
    eq({}, floats())
  end)

  it('draws an emitter as denser pixels where they are available, unless the scene refuses', function()
    pixels()

    local actor = { type = 'emitter', at = { 10, 5 }, burst = 3, speed = 0, life_ms = 500, seed = 1 }
    local stage = spec.build({ actors = { actor } })

    stage:update(0)
    eq({}, floats())
    eq(9, #stage.actors[1].emitter:motes())
    eq(1, #drawn)
    stage:stop()

    stage = spec.build({ pixels = false, actors = { actor } })
    stage:update(0)
    eq(3, #floats())
    stage:stop()
  end)

  it('draws shapes on the pixel layer, moving and resizing them along their tracks', function()
    pixels()

    local stage = spec.build({
      front = true,
      actors = {
        { type = 'shape', shape = 'rect', at = { 2, 1 }, w = { { 0, 2 }, { 100, 6 } }, h = 2, color = '#ff0000' },
        { type = 'shape', shape = 'circle', at = { 20, 4 }, to = { 30, 4 }, ms = 100, ease = 'linear', r = 0.5 },
        { type = 'shape', shape = 'line', at = { 2, 8 }, ['end'] = { 12, 8 }, show_ms = 50 },
        { type = 'shape', shape = 'ring', at = { 40, 4 }, r = 1, opacity = { { 0, 100 }, { 100, 0 } } },
        { type = 'shape', shape = 'glow', at = { 50, 4 }, r = 1, hide_ms = 50 },
      },
    })

    stage:update(0)
    eq({ 255, 0, 0, 255 }, { stage.layer.bitmap:pixel(2 * 8 + 4, 1 * 16 + 4) })
    eq(0, select(4, stage.layer.bitmap:pixel(6 * 8 + 4, 1 * 16 + 4)))
    eq(0, select(4, stage.layer.bitmap:pixel(7 * 8, 8 * 16)))
    assert.is_true(select(4, stage.layer.bitmap:pixel(20 * 8, 4 * 16)) > 0)
    assert.is_true(select(4, stage.layer.bitmap:pixel(50 * 8, 4 * 16)) > 0)
    eq(50, drawn[1].place.z)

    stage:update(100)
    eq(255, select(4, stage.layer.bitmap:pixel(6 * 8 + 4, 1 * 16 + 4)))
    eq(0, select(4, stage.layer.bitmap:pixel(20 * 8, 4 * 16)))
    eq(255, select(4, stage.layer.bitmap:pixel(30 * 8, 4 * 16)))
    eq(255, select(4, stage.layer.bitmap:pixel(7 * 8, 8 * 16)))
    eq(0, select(4, stage.layer.bitmap:pixel(41 * 8, 4 * 16)))
    eq(0, select(4, stage.layer.bitmap:pixel(50 * 8, 4 * 16)))
    stage:stop()
  end)

  it('animates the real text and the real cursor without editing the buffer', function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three', 'four' })
    vim.bo.modified = false

    local stage = spec.build({
      actors = {
        { type = 'text', effect = 'reveal', ms = 100 },
        { type = 'camera', move = 'cursor', to = { 4, 0 }, ms = 100, ease = 'linear' },
      },
    })

    stage:update(0)
    stage:update(100)

    eq({ 4, 0 }, vim.api.nvim_win_get_cursor(0))
    eq(false, vim.bo.modified)
    stage:stop()
    eq({ 'one', 'two', 'three', 'four' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    eq({}, vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('ui_anim_text'), 0, -1, {}))
  end)

  it('says which actor is wrong, and what would be right', function()
    eq('a scene needs actors: [...] or a preset', fails({}))
    assert.is_truthy(fails({ preset = 'nope' }):find('unknown preset nope (confetti, ', 1, true))
    eq(
      'actor 1: unknown type blob (sprite, emitter, shape, text, camera, curtain)',
      fails({ actors = { { type = 'blob' } } })
    )
    eq('actor 1: a sprite needs lines or frames', fails({ actors = { { type = 'sprite' } } }))
    eq(
      'actor 2: unknown text effect wobble (reveal, sweep, glitch, rain)',
      fails({ actors = { { type = 'sprite', lines = { 'x' } }, { type = 'text', effect = 'wobble' } } })
    )
    eq(
      'actor 1: shapes need a terminal that speaks the kitty graphics protocol, outside tmux',
      fails({ actors = { { type = 'shape', shape = 'circle' } } })
    )
    assert.is_truthy(
      fails({ actors = { { type = 'sprite', lines = { 'x' }, at = { 'left', 0 } } } }):find(
        'is not a number or a percentage',
        1,
        true
      )
    )
    eq({}, floats())

    pixels()
    eq(
      'actor 1: unknown shape blob (circle, glow, ring, rect, line)',
      fails({ actors = { { type = 'shape', shape = 'blob' } } })
    )

    local many = {}

    for index = 1, spec.MAX_ACTORS + 1 do
      many[index] = { type = 'curtain', blend = 50 }
    end

    eq('at most 24 actors', fails({ actors = many }))
  end)
end)
