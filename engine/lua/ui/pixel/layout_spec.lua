local layout = require('ui.pixel.layout')

local eq = assert.are.same

local function frames(root, width, height)
  local out = {}
  for i, box in ipairs(layout.compute(root, width, height)) do
    out[i] = { box.x, box.y, box.w, box.h }
  end
  return out
end

describe('ui.pixel.layout:', function()
  it('places fixed children in a row with gap and padding', function()
    local root = {
      padding = { left = 1, right = 1, top = 2, bottom = 0 },
      gap = 2,
      children = {
        { id = 'a', width = 3, height = 2 },
        { id = 'b', width = 4, height = 1 },
      },
    }

    eq({ { 0, 0, 11, 4 }, { 1, 2, 3, 2 }, { 6, 2, 4, 1 } }, frames(root, 20, 10))
  end)

  it('sizes fit containers from their children, padding and gaps', function()
    local root = {
      direction = 'column',
      padding = 1,
      gap = 1,
      children = {
        { width = 3, height = 1 },
        { width = 5, height = 2 },
      },
    }

    eq({ { 0, 0, 7, 6 }, { 1, 1, 3, 1 }, { 1, 3, 5, 2 } }, frames(root, 40, 40))
  end)

  it('splits leftover row space among grow children and gives the remainder to the first', function()
    local root = {
      width = 'grow',
      height = 1,
      children = {
        { width = 'grow', height = 1 },
        { width = 'grow', height = 1 },
        { width = 'grow', height = 1 },
      },
    }

    eq({ { 0, 0, 10, 1 }, { 0, 0, 4, 1 }, { 4, 0, 3, 1 }, { 7, 0, 3, 1 } }, frames(root, 10, 1))
  end)

  it('gives grow children the space left after fixed siblings', function()
    local root = {
      width = 'grow',
      height = 1,
      children = {
        { width = 4, height = 1 },
        { width = 'grow', height = 1 },
        { width = 'grow', height = 1 },
      },
    }

    eq({ { 0, 0, 10, 1 }, { 0, 0, 4, 1 }, { 4, 0, 3, 1 }, { 7, 0, 3, 1 } }, frames(root, 10, 1))
  end)

  it('resolves percent children against the parent inner size', function()
    local root = {
      width = 'grow',
      height = 'grow',
      children = {
        { width = '50%', height = '50%' },
        { width = '25%', height = 'grow' },
      },
    }

    eq({ { 0, 0, 20, 4 }, { 0, 0, 10, 2 }, { 10, 0, 5, 4 } }, frames(root, 20, 4))
  end)

  it('resolves a percent root against the size passed to compute', function()
    local root = { width = '50%', height = '25%' }

    eq({ { 0, 0, 10, 2 } }, frames(root, 20, 8))
  end)

  it('lays children out top to bottom in a column direction', function()
    local root = {
      direction = 'column',
      width = 6,
      height = 9,
      gap = 1,
      children = {
        { width = 'grow', height = 1 },
        { width = 2, height = 'grow' },
      },
    }

    eq({ { 0, 0, 6, 9 }, { 0, 0, 6, 1 }, { 0, 2, 2, 7 } }, frames(root, 6, 9))
  end)

  it('lays out nested containers with their own direction and padding', function()
    local root = {
      width = 12,
      height = 4,
      padding = 1,
      children = {
        {
          direction = 'column',
          padding = { left = 1 },
          width = 'grow',
          height = 'grow',
          children = {
            { width = 2, height = 1 },
            { width = 3, height = 'grow' },
          },
        },
        { width = 2, height = 2 },
      },
    }

    eq({ { 0, 0, 12, 4 }, { 1, 1, 8, 2 }, { 2, 1, 2, 1 }, { 2, 2, 3, 1 }, { 9, 1, 2, 2 } }, frames(root, 12, 4))
  end)

  it('stretches a grow child across the cross axis of its parent', function()
    local root = {
      height = 5,
      children = {
        { width = 2, height = 'grow' },
        { width = 3, height = 2 },
      },
    }

    eq({ { 0, 0, 5, 5 }, { 0, 0, 2, 5 }, { 2, 0, 3, 2 } }, frames(root, 80, 80))
  end)

  it('aligns a row run to the right and each child to the bottom', function()
    local root = {
      width = 10,
      height = 6,
      align = { x = 'right', y = 'bottom' },
      gap = 1,
      children = {
        { width = 2, height = 1 },
        { width = 3, height = 2 },
      },
    }

    eq({ { 0, 0, 10, 6 }, { 4, 5, 2, 1 }, { 7, 4, 3, 2 } }, frames(root, 10, 6))
  end)

  it('centers a row run and a child on both axes', function()
    local root = {
      width = 10,
      height = 6,
      align = { x = 'center', y = 'center' },
      children = { { width = 3, height = 2 } },
    }

    eq({ { 0, 0, 10, 6 }, { 3, 2, 3, 2 } }, frames(root, 10, 6))
  end)

  it('aligns a column run to the center and each child to the right', function()
    local root = {
      direction = 'column',
      width = 6,
      height = 10,
      align = { x = 'right', y = 'center' },
      children = { { width = 2, height = 3 } },
    }

    eq({ { 0, 0, 6, 10 }, { 4, 3, 2, 3 } }, frames(root, 6, 10))
  end)

  it('does not shift a row run when a child grows', function()
    local root = {
      width = 10,
      height = 1,
      align = { x = 'right' },
      children = {
        { width = 2, height = 1 },
        { width = 'grow', height = 1 },
      },
    }

    eq({ { 0, 0, 10, 1 }, { 0, 0, 2, 1 }, { 2, 0, 8, 1 } }, frames(root, 10, 1))
  end)

  it('measures a text leaf by its display width, with wide characters counting double', function()
    local root = { children = { { text = '漢a' } } }

    eq({ { 0, 0, 3, 1 }, { 0, 0, 3, 1 } }, frames(root, 10, 5))
  end)

  it('shrinks fit children to fit the parent and leaves fixed children alone', function()
    local root = {
      width = 10,
      height = 1,
      children = {
        { width = 6, height = 1 },
        { text = 'abcdef' },
      },
    }

    eq({ { 0, 0, 10, 1 }, { 0, 0, 6, 1 }, { 6, 0, 4, 1 } }, frames(root, 10, 1))
  end)

  it('never shrinks a child below its min size', function()
    local root = {
      width = 10,
      height = 1,
      children = {
        { width = 6, height = 1 },
        { text = 'abcdef', min_width = 5 },
      },
    }

    eq({ { 0, 0, 10, 1 }, { 0, 0, 6, 1 }, { 6, 0, 5, 1 } }, frames(root, 10, 1))
  end)

  it('clamps sizes to min and max after layout', function()
    local root = {
      height = 1,
      children = {
        { width = 2, height = 1, min_width = 5 },
        { width = 9, height = 1, max_width = 4 },
      },
    }

    eq({ { 0, 0, 9, 1 }, { 0, 0, 5, 1 }, { 5, 0, 4, 1 } }, frames(root, 30, 3))
  end)

  it('lists parents before their children, depth first in child order', function()
    local root = {
      id = 'root',
      children = {
        { id = 'a', children = { { id = 'a1' } } },
        { id = 'b' },
      },
    }

    local boxes = layout.compute(root, 10, 10)
    local ids, depths = {}, {}
    for i, box in ipairs(boxes) do
      ids[i] = box.id
      depths[i] = box.depth
    end

    eq({ 'root', 'a', 'a1', 'b' }, ids)
    eq({ 0, 1, 2, 1 }, depths)
  end)

  it('rejects invalid direction, sizing, align and count values', function()
    assert.has_error(function()
      layout.compute({ direction = 'diagonal' }, 10, 10)
    end, 'layout: invalid direction diagonal')

    assert.has_error(function()
      layout.compute({ width = 'huge' }, 10, 10)
    end, 'layout: invalid width huge')

    assert.has_error(function()
      layout.compute({ align = { x = 'middle' } }, 10, 10)
    end, 'layout: invalid align.x middle')

    assert.has_error(function()
      layout.compute({ gap = -1 }, 10, 10)
    end, 'layout: gap must be a whole number of cells, got -1')
  end)
end)
