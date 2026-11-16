local graphics = require('core.graphics')
local surfaces = require('surfaces')
local catalog = require('ui.pixel.catalog')
local ticker = require('ui.pixel.ticker')
local Tile = require('ui.pixel.Tile')

local eq = assert.are.same

local function drawn(canvas)
  return vim.api.nvim_buf_get_lines(canvas._body:get_bufnr(), 0, -1, false)
end

local function failure(fn)
  local ok, err = pcall(fn)

  eq(false, ok)

  return err
end

describe('surfaces.Canvas components:', function()
  local original

  before_each(function()
    surfaces.close_all()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')

    original = {
      available = Tile.available,
      upload = graphics.upload,
      delete = graphics.delete,
      render = catalog.render,
    }
    Tile.available = function()
      return false
    end
  end)

  after_each(function()
    surfaces.close_all()
    ticker.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete, catalog.render =
      original.available, original.upload, original.delete, original.render
  end)

  describe('without pixels', function()
    it('draws a bar inline and a card on its own rows, and the height counts the card rows', function()
      local canvas = surfaces.canvas({
        title = 'Dash',
        components = {
          { id = 'b', type = 'bar', value = 0.5, cols = 4 },
          { id = 'c', type = 'card', lines = { 'hi', 'there' } },
        },
        lines = { 'load {@b}', '{@c}' },
      })

      eq(
        { ' load ▰▰▱▱', ' ╭─────╮', ' │hi   │', ' │there│', ' ╰─────╯' },
        drawn(canvas)
      )
      eq(5, vim.api.nvim_win_get_height(vim.fn.bufwinid(canvas._body:get_bufnr())))
      eq(false, canvas._timer:is_active())
    end)

    it('snapshots placeholders and the component list, and no bar glyphs', function()
      local canvas = surfaces.canvas({
        title = 'Dash',
        components = {
          { id = 'b', type = 'bar', value = 0.5, cols = 4 },
          { id = 'c', type = 'card', lines = { 'hi', 'there' } },
        },
        lines = { 'load {@b}', '{@c}' },
      })
      local shown = canvas:snapshot()

      assert.is_truthy(shown:find('load [bar b]', 1, true))
      assert.is_truthy(shown:find('[card c]', 1, true))
      assert.is_falsy(shown:find('▰', 1, true))
      assert.is_truthy(shown:find('\nb bar cols=4 value=0.5', 1, true))
      assert.is_truthy(shown:find('\nc card lines=[2 items]', 1, true))
    end)

    it('sets a component props and redraws the line in place', function()
      local canvas = surfaces.canvas({
        title = 'Dash',
        components = { { id = 'b', type = 'bar', value = 0.5, cols = 4 } },
        lines = { 'load {@b}' },
      })

      canvas:command('set', { id = 'b', props = { value = 1 } })

      eq({ ' load ▰▰▰▰' }, drawn(canvas))
      assert.is_truthy(canvas:snapshot():find('\nb bar cols=4 value=1', 1, true))
    end)

    it('raises clear errors for bad components before anything opens', function()
      eq(
        'component x: unknown component nope (bar, ring, sparkline, badge, card)',
        failure(function()
          surfaces.canvas({ title = 'X', components = { { id = 'x', type = 'nope' } }, lines = { 'hi' } })
        end)
      )
      eq(
        'component b: bar.value must be a number, got string',
        failure(function()
          surfaces.canvas({ title = 'X', components = { { id = 'b', type = 'bar', value = 'high' } }, lines = { 'hi' } })
        end)
      )
      eq(
        'duplicate component id b',
        failure(function()
          surfaces.canvas({
            title = 'X',
            components = { { id = 'b', type = 'bar' }, { id = 'b', type = 'bar' } },
            lines = { 'hi' },
          })
        end)
      )
      eq({}, surfaces.all())
    end)

    it('raises clear errors from set for an unknown id and a bad prop', function()
      local canvas = surfaces.canvas({
        title = 'Dash',
        components = { { id = 'b', type = 'bar' }, { id = 'c', type = 'card' } },
        lines = { '{@b}' },
      })

      eq(
        'no component z (ids: b, c)',
        failure(function()
          canvas:command('set', { id = 'z', props = {} })
        end)
      )
      eq(
        'component b: bar.value must be a number, got string',
        failure(function()
          canvas:command('set', { id = 'b', props = { value = 'x' } })
        end)
      )
    end)

    it('releases its components when it closes', function()
      local releases = 0

      catalog.render = function(name, props)
        local rendered = original.render(name, props)
        local release = rendered.release

        rendered.release = function()
          releases = releases + 1
          release()
        end

        return rendered
      end

      local canvas = surfaces.canvas({
        title = 'Dash',
        components = { { id = 'c', type = 'card', lines = { 'hi' } }, { id = 'd', type = 'card', lines = { 'yo' } } },
        lines = { '{@c}', '{@d}' },
      })

      eq(0, releases)
      canvas:command('close')
      eq(2, releases)
    end)

    it('replaces the components when draw is given components', function()
      local canvas = surfaces.canvas({
        title = 'Dash',
        components = { { id = 'b', type = 'bar' } },
        lines = { '{@b}' },
      })

      canvas:command('draw', { lines = { '{@x}' }, components = { { id = 'x', type = 'badge', text = 'ok' } } })

      assert.is_truthy(canvas:snapshot():find('[badge x]', 1, true))
      assert.is_falsy(canvas:snapshot():find('bar b', 1, true))
      eq(
        'no component b (ids: x)',
        failure(function()
          canvas:command('set', { id = 'b', props = {} })
        end)
      )
    end)
  end)

  describe('with pixels', function()
    before_each(function()
      Tile.available = function()
        return true
      end
      graphics.upload = function() end
      graphics.delete = function() end
    end)

    it('animates an indeterminate ring with a ticker, and stops it when the canvas closes', function()
      local canvas = surfaces.canvas({
        title = 'Spin',
        components = { { id = 'r', type = 'ring', indeterminate = true } },
        lines = { '{@r}' },
      })

      eq(1, ticker.count())
      canvas:command('close')
      eq(0, ticker.count())
    end)

    it('renders a static bar without a ticker or a repaint timer', function()
      local canvas = surfaces.canvas({
        title = 'Bar',
        components = { { id = 'b', type = 'bar', value = 0.5 } },
        lines = { '{@b}' },
      })

      eq(0, ticker.count())
      eq(false, canvas._components.b.animated)
      eq(false, canvas._timer:is_active())
      canvas:close()
    end)

    it('stops the animation when set makes the component static', function()
      local canvas = surfaces.canvas({
        title = 'Load',
        components = { { id = 'r', type = 'ring', indeterminate = true } },
        lines = { '{@r}' },
      })

      eq(1, ticker.count())
      canvas:command('set', { id = 'r', props = { indeterminate = false, value = 0.5 } })
      eq(0, ticker.count())
      canvas:close()
    end)
  end)
end)
