local content = require('harness.transcript.content')

local actions = {}

local handlers = {}

function actions.bind(key, handler)
  handlers[key] = handler

  return actions
end

function actions.find(block, key, ctx)
  if not block then return nil end

  for _, action in ipairs(content.actions(block)) do
    if action.key == key and (not action.when or action.when(block, ctx)) then return action end
  end

  return nil
end

function actions.run(view, block, key, ctx)
  local action = actions.find(block, key, ctx)

  if not action then return false end

  local handler = action.handler or handlers[action.key] or handlers[action.id]

  if not handler then return false end

  return true, handler(view, block, ctx)
end

return actions
