local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local Object = lazy('core.Object')
local permission = require('harness.types.permission')

local PermissionState = Object:extend()

PermissionState.MAX_DECISIONS = 200

function PermissionState:constructor()
  return { _grants = {}, _decisions = {} }
end

function PermissionState:grant(tool)
  self._grants[tool] = permission.Grant({ tool = tool, time = Timer.now() })

  return self
end

function PermissionState:granted(tool)
  return self._grants[tool] ~= nil
end

function PermissionState:revoke(tool)
  if not self._grants[tool] then return false end

  self._grants[tool] = nil

  return true
end

function PermissionState:grants()
  local out = {}

  for _, grant in pairs(self._grants) do
    out[#out + 1] = grant
  end

  table.sort(out, function(a, b)
    return a.tool < b.tool
  end)

  return out
end

function PermissionState:record(entry)
  local list = self._decisions

  list[#list + 1] = permission.Entry(vim.tbl_extend('keep', entry, { time = Timer.now() }))

  if #list > PermissionState.MAX_DECISIONS then table.remove(list, 1) end

  return self
end

function PermissionState:decisions()
  return vim.list_slice(self._decisions)
end

return PermissionState
