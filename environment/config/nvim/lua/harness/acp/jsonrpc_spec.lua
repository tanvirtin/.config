local jsonrpc = require('harness.acp.jsonrpc')

local eq = assert.are.same

describe('harness.acp.jsonrpc:', function()
  it('builds a request', function()
    local message = jsonrpc.request(1, 'initialize', { protocolVersion = 1 })

    eq(message, { jsonrpc = '2.0', id = 1, method = 'initialize', params = { protocolVersion = 1 } })
  end)

  it('builds a notification without an id', function()
    local message = jsonrpc.notification('session/update', { sessionId = 's1' })

    eq(message.id, nil)
    eq(message.method, 'session/update')
  end)

  it('encodes an empty result as an object', function()
    local encoded = jsonrpc.encode(jsonrpc.result(2))

    eq(encoded:find('"result":{}', 1, true) ~= nil, true)
  end)

  it('builds an error response', function()
    local message = jsonrpc.error(3, jsonrpc.METHOD_NOT_FOUND, 'nope')

    eq(message.error.code, -32601)
    eq(message.error.message, 'nope')
  end)

  it('classifies messages', function()
    eq(jsonrpc.is_request({ method = 'x', id = 1 }), true)
    eq(jsonrpc.is_request({ method = 'x' }), false)
    eq(jsonrpc.is_response({ id = 1, result = {} }), true)
    eq(jsonrpc.is_request({ id = 1, result = {} }), false)
  end)

  it('round-trips through the codec', function()
    local original =
      jsonrpc.request(7, 'session/prompt', { sessionId = 's', prompt = { { type = 'text', text = 'hi' } } })
    local decoded = jsonrpc.decode(jsonrpc.encode(original))

    eq(decoded, original)
  end)
end)
