local async = require('harness.async')
local events = require('harness.types.events')
local session = require('harness.types.session')
local capabilities = require('harness.types.capabilities')

local FakeServer = {}

FakeServer.NAME = 'fake'

FakeServer.CAPABILITIES = {
  load = true,
  fork = true,
  list = true,
  close = true,
  delete = true,
  steer = true,
  system_prompt = true,
}

local Connection = {}
Connection.__index = Connection

function FakeServer.connect(_, _, opts)
  opts = opts or {}

  return setmetatable({
    abilities = capabilities.new(opts.capabilities or FakeServer.CAPABILITIES),
    reply = opts.reply or function(prompt)
      return { events.new({ kind = events.KIND.message, text = 'ok: ' .. prompt.text }) }
    end,
    stored = {},
    delegates = {},
    prompts = {},
    next = 0,
    closed = false,
  }, Connection)
end

function Connection:capabilities()
  return self.abilities
end

function Connection:_new()
  self.next = self.next + 1

  local id = 'fake' .. self.next

  self.stored[id] = { id = id, events = {} }

  return id
end

function Connection:_deliver(id, event)
  local stored = self.stored[id]

  if stored then stored.events[#stored.events + 1] = event end

  local delegate = self.delegates[id]

  if delegate and delegate.event then delegate.event(event) end
end

function Connection:new_session()
  return session.Opened({ id = self:_new() })
end

function Connection:load_session(id)
  local stored = self.stored[id]

  if not stored then error('no stored session ' .. tostring(id), 0) end

  local delegate = self.delegates[id]

  for _, event in ipairs(stored.events) do
    if delegate and delegate.event then delegate.event(event) end
  end

  return session.Opened({})
end

function Connection:fork_session(id)
  local fork = self:_new()

  self.stored[fork].events = vim.deepcopy((self.stored[id] or {}).events or {})

  return session.Opened({ id = fork })
end

function Connection:list_sessions()
  local out = {}

  for id in pairs(self.stored) do
    out[#out + 1] = session.Stored({ id = id })
  end

  table.sort(out, function(a, b)
    return a.id < b.id
  end)

  return out
end

function Connection:close_session(id)
  self.delegates[id] = nil
end

function Connection:delete_session(id)
  self.stored[id] = nil
  self.delegates[id] = nil
end

function Connection:prompt(id, prompt)
  self.prompts[#self.prompts + 1] = prompt

  for _, event in ipairs(self.reply(prompt) or {}) do
    self:_deliver(id, event)
  end

  async.drain()

  return events.STOP_REASON.end_turn
end

function Connection:steer(_, prompt)
  self.prompts[#self.prompts + 1] = prompt

  return true
end

function Connection:cancel() end

function Connection:set_option()
  return nil
end

function Connection:use_model()
  return nil
end

function Connection:attach(id, delegate)
  self.delegates[id] = delegate
end

function Connection:detach(id)
  self.delegates[id] = nil
end

function Connection:close()
  self.closed = true
end

return FakeServer
