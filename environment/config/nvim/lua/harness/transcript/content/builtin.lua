local Block = require('harness.transcript.Block')
local content = require('harness.transcript.content')

return function()
  content.register({
    id = 'title',
    kind = Block.KIND.title,
    render = { mode = 'markdown', batch = true },
  })

  content.register({
    id = 'message',
    kind = Block.KIND.message,
    render = { mode = 'markdown', batch = true, stream = true },
  })

  content.register({
    id = 'thought',
    kind = Block.KIND.thought,
    render = { mode = 'markdown', batch = true, quote = true, fold = true, live = true },
  })

  content.register({
    id = 'prompt',
    kind = Block.KIND.prompt,
    render = { mode = 'raw', anchor = true },
  })

  content.register({
    id = 'note',
    kind = Block.KIND.note,
    render = { mode = 'raw' },
  })

  content.register({
    id = 'plan',
    kind = Block.KIND.plan,
    render = { mode = 'raw' },
  })

  content.register({
    id = 'execute',
    kind = Block.KIND.tool,
    category = Block.CATEGORY.execute,
    priority = 10,
    render = { mode = 'markdown' },
    instructions = {
      agent = 'Keep terminal commands and output verbatim; do not wrap or reflow them.',
      when = { categories = { Block.CATEGORY.execute } },
    },
  })

  content.register({
    id = 'tool',
    kind = Block.KIND.tool,
    render = { mode = 'markdown' },
  })

  content.register({
    id = 'diff',
    kind = Block.KIND.diff,
    render = { mode = 'markdown' },
    instructions = {
      agent = 'When showing diffs, keep paths relative and do not reflow the patch.',
      when = { categories = { Block.CATEGORY.edit, Block.CATEGORY.delete, Block.CATEGORY.move } },
    },
    actions = {
      {
        key = 'diff',
        label = 'open edit in vgit',
      },
    },
  })

  content.register({
    id = 'stop',
    kind = Block.KIND.stop,
    render = { mode = 'markdown' },
  })

  content.register({
    id = 'collapsed',
    kind = Block.KIND.collapsed,
    render = { mode = 'markdown' },
  })
end
