local Timer = require('core.Timer')
local Tile = require('ui.pixel.Tile')
local graphics = require('core.editor.graphics')
local ticker = require('ui.pixel.ticker')
local catalog = require('ui.pixel.catalog')

local eq = assert.are.same

local FAKE = 'ui.pixel.components.fake'

local function fake(calls)
  return {
    name = 'fake',
    props = {
      level = { 'number', 1 },
      label = { 'string', 'x' },
    },
    size = function(props)
      return props.level, 1
    end,
    animated = function()
      return false
    end,
    commands = function(props, width, height, now)
      calls[#calls + 1] = { props = props, width = width, height = height, now = now }

      return {}
    end,
  }
end

local BAR_DEFAULTS = {
  value = 0,
  cols = 12,
  color = 'accent',
  track = 'muted',
  indeterminate = false,
  period_ms = 1400,
}

describe('ui.pixel.catalog:', function()
  local original, uploads, calls

  before_each(function()
    uploads, calls = 0, {}
    original = {
      available = Tile.available,
      now = Timer.now,
      upload = graphics.upload,
      delete = graphics.delete,
      names = catalog.NAMES,
    }
    Tile.available = function()
      return true
    end
    Timer.now = function()
      return 42
    end
    graphics.upload = function()
      uploads = uploads + 1
    end
    graphics.delete = function() end
    package.loaded[FAKE] = fake(calls)
  end)

  after_each(function()
    ticker.stop()
    Tile.drain()
    package.loaded[FAKE] = nil
    catalog.NAMES = original.names
    Tile.available, Timer.now = original.available, original.now
    graphics.upload, graphics.delete = original.upload, original.delete
  end)

  it('knows the bar, ring, sparkline, badge, card and loader components', function()
    eq({ 'bar', 'ring', 'sparkline', 'badge', 'card', 'loader' }, catalog.NAMES)
  end)

  it('gets a component by name', function()
    eq('bar', catalog.get('bar').name)
  end)

  it('refuses an unknown component and names the ones it knows', function()
    assert.has_error(function()
      catalog.get('nope')
    end, 'unknown component nope (bar, ring, sparkline, badge, card, loader)')
  end)

  it('fills in every default when no props are given', function()
    eq(BAR_DEFAULTS, catalog.resolve('bar'))
    eq(BAR_DEFAULTS, catalog.resolve('bar', nil))
  end)

  it('keeps the props given and fills the rest from the defaults', function()
    eq(
      vim.tbl_extend('force', BAR_DEFAULTS, { value = 0.5, color = '#ff0000' }),
      catalog.resolve('bar', { value = 0.5, color = '#ff0000' })
    )
  end)

  it('refuses a prop the component does not have, and lists the ones it has, sorted', function()
    assert.has_error(function()
      catalog.resolve('bar', { nope = 1 })
    end, 'bar has no prop nope (color, cols, indeterminate, period_ms, track, value)')
  end)

  it('refuses a prop of the wrong type', function()
    assert.has_error(function()
      catalog.resolve('bar', { value = 'half' })
    end, 'bar.value must be a number, got string')
  end)

  it('makes an animation sized by the component, with its resolved props', function()
    local animation = catalog.animation('bar', { cols = 3 })

    eq(3, animation.cols)
    eq(1, animation.rows)
    eq(3, animation.props.cols)
    eq(false, animation:active())
  end)

  it('is nothing from an animation where there are no pixels', function()
    Tile.available = function()
      return false
    end
    local animation = catalog.animation('bar', {})

    eq(nil, animation:chunks())
    eq(0, ticker.count())
  end)

  it('shows an animation as one chunk as wide as its cols', function()
    local chunks = catalog.animation('bar', { cols = 3 }):chunks()

    eq(1, #chunks)
    eq(3, vim.fn.strdisplaywidth(chunks[1][1]))
    eq(1, uploads)
  end)

  it('replaces the props on set, re-resolving them, and resizes the tile when the size changes', function()
    local animation = catalog.animation('bar', { cols = 3, color = '#ff0000' })

    animation:chunks()
    animation:set({ cols = 5, value = 0.2 })

    eq(5, animation.cols)
    eq(0.2, animation.props.value)
    eq(BAR_DEFAULTS.color, animation.props.color)
    eq(false, animation:active())
    eq(5, vim.fn.strdisplaywidth(animation:chunks()[1][1]))
  end)

  it('refuses an animation for a component that only renders lines', function()
    assert.has_error(function()
      catalog.animation('badge', { text = 'ok' })
    end, 'badge has no animation, use catalog.render')
  end)

  it('renders a tile component as one row of chunks as wide as its cols', function()
    local rendered = catalog.render('bar', { cols = 3 })

    eq(1, #rendered.lines)
    eq(3, vim.fn.strdisplaywidth(rendered.lines[1][1][1]))
    eq(1, uploads)
    rendered.release()
  end)

  it('frees the images of a render when it is released', function()
    local deleted = {}

    graphics.delete = function(id)
      deleted[#deleted + 1] = id
    end

    local rendered = catalog.render('bar', {})

    rendered.release()
    eq(1, #deleted)
    rendered.release()
    eq(1, #deleted)
  end)

  it('gives the component the resolved props, the pixel size and the frame time when it paints', function()
    local animation = catalog.animation('fake', { level = 2, label = 'hi' })

    animation:chunks()

    eq(1, #calls)
    eq({ level = 2, label = 'hi' }, calls[1].props)
    eq({ 32, 32, 42 }, { calls[1].width, calls[1].height, calls[1].now })
    eq(animation.props, calls[1].props)
  end)

  it('describes each component in one line, with its props sorted by name and their defaults', function()
    catalog.NAMES = { 'bar', 'fake' }

    eq({
      'bar: color string=accent, cols number=12, indeterminate boolean=false, period_ms number=1400, track string=muted, value number=0',
      'fake: label string=x, level number=1',
    }, catalog.describe())
  end)

  it('renders the text fallback of a tile component where there are no pixels', function()
    Tile.available = function()
      return false
    end

    local rendered = catalog.render('bar', { cols = 4, value = 0.5 })

    eq({ '▰▰', '▱▱' }, { rendered.lines[1][1][1], rendered.lines[1][2][1] })
    eq(0, uploads)
    rendered.release()
  end)

  it('measures the size of a component without drawing it', function()
    eq({ 7, 1 }, { catalog.size_of('bar', { cols = 7 }) })
    eq({ 2, 1 }, { catalog.size_of('ring', {}) })
    eq({ 5, 1 }, { catalog.size_of('sparkline', { cols = 5 }) })
    eq({ 4, 1 }, { catalog.size_of('badge', { text = 'ok' }) })
    eq({ 0, 0 }, { catalog.size_of('badge', {}) })
    eq({ 4, 4 }, { catalog.size_of('card', { lines = { 'ab', 'c' } }) })
    eq({ 2, 1 }, { catalog.size_of('loader', {}) })
    eq(0, uploads)
  end)
end)
