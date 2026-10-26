local Block = require('harness.transcript.Block')
local content = require('harness.transcript.content')
local instructions = require('harness.types.instructions')
local builtin = require('harness.transcript.content.builtin')

local eq = assert.are.same

describe('harness.transcript.content:', function()
  before_each(function()
    content.reset()
    builtin()
  end)

  after_each(function()
    content.reset()
    builtin()
  end)

  it('should give every current block a render mode', function()
    eq('raw', content.mode(Block.make(Block.KIND.prompt, { 'x' })))
    eq('raw', content.mode(Block.make(Block.KIND.note, { 'x' })))
    eq('raw', content.mode(Block.make(Block.KIND.plan, { 'x' })))
    eq('markdown', content.mode(Block.make(Block.KIND.message, { 'x' })))
    eq('markdown', content.mode(Block.make(Block.KIND.thought, { 'x' })))
    eq('markdown', content.mode(Block.make(Block.KIND.tool, { 'x' })))
    eq('markdown', content.mode(Block.make(Block.KIND.diff, { 'x' })))
  end)

  it('should register a treesitter content type', function()
    local block = { kind = Block.KIND.tool, lang = 'json' }
    local spec = content.option(block, 'treesitter')

    eq('json', spec.language)
    eq('UiPath', spec.captures.property())
    eq('json', content.resolve(block).hit_test)
    eq('markdown', content.mode(block))
  end)

  it('should give markdown messages a table hit test', function()
    eq('markdown', content.resolve(Block.make(Block.KIND.message, { 'x' })).hit_test)
  end)

  it('should register a table content type', function()
    local block = { kind = Block.KIND.tool, lang = 'csv' }
    local spec = content.option(block, 'table')

    eq(3, spec.first)
    eq(1, spec.trim)
    eq('csv', content.resolve(block).id)
    eq('csv', content.resolve(block).hit_test)
  end)

  it('should expose the built-in options', function()
    local thought = Block.make(Block.KIND.thought, { 'x' })

    eq(true, content.option(thought, 'quote'))
    eq(true, content.option(thought, 'live'))
  end)

  it('should prefer a more specific match', function()
    content.register({
      id = 'execute',
      kind = Block.KIND.tool,
      category = Block.CATEGORY.execute,
      priority = 10,
      render = { mode = 'raw' },
    })

    local tool = Block.make(Block.KIND.tool, { 'x' }, { category = Block.CATEGORY.execute })

    eq('execute', content.resolve(tool).id)
    eq('raw', content.mode(tool))
  end)

  it('should accept a match function', function()
    content.register({
      id = 'sql',
      match = function(block)
        return block.name == 'sql'
      end,
      priority = 20,
      render = { mode = 'raw' },
    })

    eq('sql', content.resolve({ kind = Block.KIND.tool, name = 'sql' }).id)
    eq('tool', content.resolve({ kind = Block.KIND.tool, name = 'other' }).id)
  end)

  it('should fall back for unknown blocks', function()
    local unknown = { kind = 'unknown' }

    eq('fallback', content.resolve(unknown).id)
    eq('raw', content.mode(unknown))
    eq(nil, content.decorate(unknown))
    eq({}, content.actions(unknown))
  end)

  it('should let a type supply decorate, actions and instructions', function()
    local decorate = function()
      return { { row = 0 } }
    end
    local actions = { { key = '<CR>', label = 'open' } }
    local instructions = { agent = 'be careful' }

    content.register({
      id = 'custom',
      kind = 'custom',
      render = { mode = 'raw' },
      decorate = decorate,
      actions = actions,
      instructions = instructions,
    })

    local block = { kind = 'custom' }

    eq({ { row = 0 } }, content.decorate(block))
    eq(actions, content.actions(block))
  end)

  it('should replace a type with the same id and clear the cache', function()
    content.register({ id = 'same', kind = 'same', render = { mode = 'raw' } })
    eq('raw', content.mode({ kind = 'same' }))

    content.register({ id = 'same', kind = 'same', render = { mode = 'markdown' } })
    eq('markdown', content.mode({ kind = 'same' }))
  end)

  it('should unregister a type and its instructions', function()
    content.register({
      id = 'gone',
      kind = 'gone',
      render = { mode = 'raw' },
      instructions = { agent = 'gone' },
    })

    eq('gone', content.resolve({ kind = 'gone' }).id)
    eq('gone', instructions.text({}))

    content.unregister('gone')

    eq('fallback', content.resolve({ kind = 'gone' }).id)
    eq('', instructions.text({}))
  end)

  it('should invalidate the resolution cache when a new type is registered', function()
    local block = { kind = 'late' }

    eq('fallback', content.resolve(block).id)

    content.register({ id = 'late', kind = 'late', render = { mode = 'raw' } })

    eq('late', content.resolve(block).id)
  end)

  it('should look types up by id', function()
    eq('message', content.get('message').id)
    eq(nil, content.get('missing'))
  end)

  it('should forward agent instructions to the instruction registry', function()
    content.register({
      id = 'instructed',
      kind = 'instructed',
      render = { mode = 'raw' },
      instructions = { agent = 'be careful', when = { categories = { 'custom' } } },
    })

    eq('be careful', instructions.text({ categories = { custom = true } }))
    eq('', instructions.text({}))
  end)
end)
