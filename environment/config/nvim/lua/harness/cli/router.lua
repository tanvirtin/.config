local lazy = require('core.lazy')

local event = lazy('core.event')

local router = {}

router.COMMANDS =
  { 'prompt', 'new', 'sessions', 'stats', 'cancel', 'clear', 'changes', 'fork', 'revert', 'quickfix', 'permissions' }

local disposers = {}

function router.commands()
  return vim.tbl_map(function(name)
    return require('harness.cli.commands.' .. name)
  end, router.COMMANDS)
end

function router.find(name)
  for _, command in ipairs(router.commands()) do
    if command.name == name then return command end
  end
end

function router.execute(name, args)
  local command = router.find(name)

  if not command then error(string.format('unknown Harness command "%s"', tostring(name)), 2) end

  return command.execute(args or { args = '', range = 0 })
end

function router.setup()
  router.teardown()

  for _, command in ipairs(router.commands()) do
    disposers[#disposers + 1] = event.command(command.name, command.execute, command.opts)
  end

  local group = event.augroup('harness')

  group.on('VimLeavePre', function()
    require('harness.hub').shutdown()
  end)

  disposers[#disposers + 1] = group.dispose
end

function router.teardown()
  for _, dispose in ipairs(disposers) do
    dispose()
  end

  disposers = {}
end

return router
