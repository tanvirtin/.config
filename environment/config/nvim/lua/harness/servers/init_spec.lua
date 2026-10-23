local servers = require('harness.servers')

local eq = assert.are.same

describe('harness.servers:', function()
  it('finds the server an agent names, ACP by default', function()
    eq(require('harness.servers.acp'), servers.get('acp'))
    eq(require('harness.servers.acp'), servers.get(nil))
    eq('function', type(servers.get().connect))
  end)

  it('refuses a server it does not know', function()
    local ok, err = pcall(servers.get, 'carrier-pigeon')

    eq({ false, 'unknown agent server: carrier-pigeon' }, { ok, err })
  end)
end)
