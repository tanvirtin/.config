local Connection = require('harness.servers.acp.connection')
local transport = require('harness.servers.acp.transport')

local AcpServer = {}

AcpServer.NAME = 'acp'

function AcpServer.spawn(agent, dir)
  return transport.process(
    vim.list_extend({ agent:executable() }, agent.args),
    { cwd = dir, env = agent:environment() }
  )
end

function AcpServer.connect(agent, dir, opts)
  local spawned = opts and opts.spawn and opts.spawn(agent, dir) or AcpServer.spawn(agent, dir)
  local connection = Connection(spawned)

  connection.login = agent.login
  connection.fork_at_message = agent.fork_at_message == true
  connection:initialize()

  return connection
end

return AcpServer
