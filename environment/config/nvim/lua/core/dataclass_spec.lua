local dataclass = require('core.dataclass')

local eq = assert.are.same

describe('core.dataclass:', function()
  local Color = dataclass.enum({ 'red', 'green' })
  local Point = dataclass.define('Point', {
    x = { type = 'number', required = true },
    y = { type = 'number', default = 0 },
    tags = {
      type = 'table',
      default = function()
        return {}
      end,
    },
    color = { type = 'string', enum = Color },
    label = { type = { 'string', 'number' } },
  })

  it('builds instances with defaults, and fresh table defaults for each', function()
    local a, b = Point({ x = 1 }), Point({ x = 2, color = Color.red, label = 3 })

    eq({ 1, 0, {} }, { a.x, a.y, a.tags })
    eq({ 'red', 3 }, { b.color, b.label })
    assert.is_true(a.tags ~= b.tags)
    assert.is_true(Point.is(a))
    assert.is_false(Point.is({}))
  end)

  it('rejects missing, unknown and mistyped fields, and values outside an enum', function()
    assert.has_error(function()
      Point({})
    end, nil)
    assert.is_truthy(select(2, pcall(Point, {})):find('missing required field "x"', 1, true))
    assert.is_truthy(select(2, pcall(Point, { x = 1, z = 2 })):find('unknown field "z"', 1, true))
    assert.is_truthy(select(2, pcall(Point, { x = 'one' })):find('Point.x: expected number, got string', 1, true))
    assert.is_truthy(select(2, pcall(Point, { x = 1, color = 'blue' })):find('not one of its values', 1, true))
    assert.is_truthy(select(2, pcall(Point, { x = 1, label = true })):find('expected string|number', 1, true))
  end)

  it('makes enums that refuse unknown members', function()
    eq('green', Color.green)
    assert.is_true(dataclass.is_member(Color, 'red'))
    assert.is_false(dataclass.is_member(Color, 'blue'))
    assert.is_truthy(select(
      2,
      pcall(function()
        return Color.blue
      end)
    ):find('unknown enum value "blue"', 1, true))
  end)
end)
