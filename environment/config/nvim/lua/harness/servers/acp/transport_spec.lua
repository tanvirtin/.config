local process = require('core.process')
local transport = require('harness.servers.acp.transport')

local eq = assert.are.same

describe('harness.servers.acp.transport:', function()
  local system, stdout

  before_each(function()
    system = process.system
    process.system = function(_, opts)
      stdout = opts.stdout
      return { write = function() end, kill = function() end }
    end
  end)

  after_each(function()
    process.system = system
  end)

  local function received(chunks)
    local messages = {}
    local proc = transport.process({ 'agent' })

    proc:on_message(function(message)
      messages[#messages + 1] = message.id
    end)

    for _, chunk in ipairs(chunks) do
      stdout(nil, chunk)
    end

    vim.wait(100, function()
      return false
    end)

    return messages
  end

  it('decodes several messages from one chunk, in order, skipping blank lines and junk', function()
    eq({ 1, 2, 3 }, received({ '{"id":1}\n\n{"id":2}\nnot json\n{"id":3}\n' }))
  end)

  it('joins a message split across chunks and keeps a partial line for the next', function()
    eq({ 1, 2 }, received({ '{"i', 'd":1}\n{"id"', ':2}', '\n{"id":3' }))
  end)
end)
