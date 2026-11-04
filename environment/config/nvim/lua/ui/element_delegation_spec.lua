local define_single_element_methods = require('ui.element_delegation').define_single_element_methods

local eq = assert.are.same

local function component(element, opts)
  local Class = {}

  function Class:with_element(fn)
    if self.element then return fn(self.element) end
  end

  define_single_element_methods(Class, opts)

  return setmetatable({ element = element }, { __index = Class })
end

describe('ui.element_delegation:', function()
  it('passes a call to the element and returns the component, so calls chain', function()
    local seen
    local instance = component({
      set_text = function(_, ...)
        seen = { ... }
      end,
    })

    eq(instance, instance:set_text(1, 2, 'x', 3, 4))
    eq({ 1, 2, 'x', 3, 4 }, seen)
  end)

  it('keeps nil arguments in place', function()
    local count
    local instance = component({
      set_keymap = function(_, ...)
        count = select('#', ...)
      end,
    })

    instance:set_keymap('n', nil, nil, 'desc')
    eq(4, count)
  end)

  it('forwards every argument of a variadic method', function()
    local seen
    local instance = component({
      clear_extmark_highlights = function(_, ...)
        seen = { ... }
      end,
    })

    instance:clear_extmark_highlights('a', 'b', 'c')
    eq({ 'a', 'b', 'c' }, seen)
  end)

  it('returns what a read gives back, and nothing without an element', function()
    local instance = component({
      get_lines = function()
        return { 'a' }
      end,
    })

    eq({ 'a' }, instance:get_lines())
    assert.is_nil(component(nil):get_lines())
  end)

  it('leaves a read to the class when it excludes it', function()
    local instance = component({}, { exclude = { get_lines = true } })

    eq(nil, instance.get_lines)
    eq('function', type(instance.get_cursor))
  end)

  it('gives a missing element a harmless answer', function()
    local instance = component(nil)

    eq(false, instance:is_valid())
    eq(false, instance:is_focused())
    eq('function', type(instance:on_click(1)))
    eq(instance, instance:focus())
  end)
end)
