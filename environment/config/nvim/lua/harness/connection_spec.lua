local agent = require('harness.agent')
local async = require('harness.async')
local connection = require('harness.connection')
local content = require('harness.types.content')
local capabilities = require('harness.types.capabilities')
local fake_agent = require('harness.servers.acp.fake_agent')
local jsonrpc = require('harness.servers.acp.jsonrpc')

local eq = assert.are.same

local function run(fn)
  return async.run(fn):wait()
end

local SERVERS = {
  {
    name = 'fake',
    connect = function()
      return require('harness.servers.fake').connect(nil, '/w')
    end,
  },
  {
    name = 'acp',
    connect = function()
      local fake = fake_agent.new({
        initialize = function(message)
          return {
            jsonrpc.result(message.id, {
              protocolVersion = 1,
              agentCapabilities = { loadSession = true, sessionCapabilities = { list = {} } },
              _meta = { steering = { supported = true } },
            }),
          }
        end,
        ['_session/steering'] = function(message)
          return { jsonrpc.result(message.id, { outcome = 'injected' }) }
        end,
      })

      fake.stored = { { sessionId = 'old', cwd = '/w', title = 'yesterday' } }

      return run(function()
        return require('harness.servers.acp').connect(agent.Agent('t', { command = 'agent' }), '/w', {
          spawn = function()
            return fake
          end,
        })
      end)
    end,
  },
}

for _, server in ipairs(SERVERS) do
  describe('harness.connection, ' .. server.name .. ' server:', function()
    local conn

    before_each(function()
      conn = server.connect()
    end)

    it('implements every method of the interface', function()
      eq({}, connection.missing(conn))
      eq(false, conn.closed)
    end)

    it('describes what it can do as a capability record', function()
      local record = conn:capabilities()

      eq(#capabilities.NAMES, vim.tbl_count(record))

      for _, name in ipairs(capabilities.NAMES) do
        eq('boolean', type(record[name]))
      end
    end)

    it('opens a session and answers a prompt with events, then a stop reason', function()
      local seen = {}

      local reason = run(function()
        local opened = conn:new_session({ cwd = '/w' })

        eq('string', type(opened.id))
        conn:attach(opened.id, {
          event = function(event)
            seen[#seen + 1] = event.kind
          end,
        })

        return conn:prompt(opened.id, content.prompt('hi'))
      end)

      eq('end_turn', reason)
      eq('message', seen[#seen])
    end)

    it('lists stored sessions by id', function()
      local listed = run(function()
        conn:new_session({ cwd = '/w' })

        return conn:list_sessions('/w')
      end)

      assert.is_true(#listed > 0)

      for _, stored in ipairs(listed) do
        eq('string', type(stored.id))
      end
    end)

    it('says whether a running turn took a steer, when it can steer', function()
      eq(true, conn:capabilities().steer)

      local taken = run(function()
        local opened = conn:new_session({ cwd = '/w' })

        return conn:steer(opened.id, content.prompt('turn left'))
      end)

      eq(true, taken)
    end)
  end)
end
