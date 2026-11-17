local content = require('harness.transcript.content')

local hit_test = {}

local handlers = {}

function hit_test.bind(id, handler)
  handlers[id] = handler

  return hit_test
end

function hit_test.unbind(id)
  handlers[id] = nil

  return hit_test
end

function hit_test.reset()
  handlers = {}

  return hit_test
end

function hit_test.at(block, row, col)
  local def = content.resolve(block)
  local handler = def.hit_test and handlers[def.hit_test]

  return handler and handler(block, row, col) or nil
end

return hit_test
