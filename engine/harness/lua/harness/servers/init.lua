local servers = {}

servers.DEFAULT = 'acp'

servers.MODULES = {
  acp = 'harness.servers.acp',
}

function servers.get(name)
  local module = servers.MODULES[name or servers.DEFAULT]

  if not module then return nil, 'unknown agent server: ' .. tostring(name) end

  return require(module)
end

return servers
