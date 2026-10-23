local servers = {}

servers.DEFAULT = 'acp'

servers.MODULES = {
  acp = 'harness.servers.acp',
}

function servers.get(name)
  local module = servers.MODULES[name or servers.DEFAULT]

  if not module then error('unknown agent server: ' .. tostring(name), 0) end

  return require(module)
end

return servers
