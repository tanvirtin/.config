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
    id = 'tool',
    kind = Block.KIND.tool,
    render = { mode = 'markdown' },
  })

  content.register({
    id = 'diff',
    kind = Block.KIND.diff,
    render = { mode = 'markdown' },
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
