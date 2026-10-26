local instructions = require('harness.types.instructions')
local builtin = require('harness.transcript.content.builtin')

local eq = assert.are.same

describe('harness.types.instructions:', function()
  after_each(function()
    instructions.reset()
    builtin()
  end)

  it('should join registered instructions in id order', function()
    instructions.register('b', 'B')
    instructions.register('a', 'A')

    eq('A\nB', instructions.text())
  end)

  it('should filter by categories, names and kinds', function()
    instructions.register('exec', 'run carefully', { categories = { 'custom-execute' } })
    instructions.register('named', 'named tool', { names = { 'sql' } })
    instructions.register('kind', 'kind rule', { kinds = { 'tool_call' } })

    eq('', instructions.text())
    eq('run carefully', instructions.text({ categories = { ['custom-execute'] = true } }))
    eq('named tool', instructions.text({ names = { sql = true } }))
    eq('kind rule', instructions.text({ kinds = { tool_call = true } }))
  end)

  it('should dedupe identical text', function()
    instructions.register('a', 'same')
    instructions.register('b', 'same')

    eq('same', instructions.text())
  end)

  it('should unregister and reset', function()
    instructions.register('a', 'A')
    instructions.unregister('a')

    eq('', instructions.text())

    instructions.register('b', 'B')
    instructions.reset()

    eq('', instructions.text())
  end)
end)
