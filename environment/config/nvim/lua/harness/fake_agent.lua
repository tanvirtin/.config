local jsonrpc = require('harness.acp.jsonrpc')

local fake_agent = {}

local CAPABILITIES = {
  loadSession = true,
  sessionCapabilities = { list = {}, close = {}, resume = {}, delete = {} },
}

function fake_agent.update(session_id, update)
  return jsonrpc.notification('session/update', { sessionId = session_id, update = update })
end

function fake_agent.chunk(session_id, text)
  return fake_agent.update(
    session_id,
    { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = text } }
  )
end

function fake_agent.permission(session_id, tool_name, id)
  return jsonrpc.request(id or 'perm-1', 'session/request_permission', {
    sessionId = session_id,
    toolCall = { toolCallId = 't1', title = tool_name, _meta = { claudeCode = { toolName = tool_name } } },
    options = {
      { optionId = 'allow', kind = 'allow_once', name = 'Allow' },
      { optionId = 'always', kind = 'allow_always', name = 'Always allow' },
      { optionId = 'reject', kind = 'reject_once', name = 'Reject' },
    },
  })
end

function fake_agent.replying(text)
  return function(message)
    local id = message.params.sessionId

    return { fake_agent.chunk(id, text), jsonrpc.result(message.id, { stopReason = 'end_turn' }) }
  end
end

function fake_agent.new(script)
  script = script or {}

  local agent = { sent = {}, stored = {}, histories = {}, sessions = 0 }

  local defaults = {
    initialize = function(message)
      return { jsonrpc.result(message.id, { protocolVersion = 1, agentCapabilities = CAPABILITIES }) }
    end,
    ['session/new'] = function(message)
      agent.sessions = agent.sessions + 1
      return { jsonrpc.result(message.id, { sessionId = 's' .. agent.sessions }) }
    end,
    ['session/list'] = function(message)
      return { jsonrpc.result(message.id, { sessions = agent.stored }) }
    end,
    ['session/load'] = function(message)
      local id = message.params.sessionId
      local replies = {}

      for _, update in ipairs(agent.histories[id] or {}) do
        replies[#replies + 1] = fake_agent.update(id, update)
      end

      replies[#replies + 1] = jsonrpc.result(message.id, {})

      return replies
    end,
    ['session/close'] = function(message)
      return { jsonrpc.result(message.id, {}) }
    end,
    ['session/delete'] = function(message)
      local id = message.params.sessionId

      agent.stored = vim.tbl_filter(function(stored)
        return stored.sessionId ~= id
      end, agent.stored)

      return { jsonrpc.result(message.id, {}) }
    end,
    ['session/set_config_option'] = function(message)
      return { jsonrpc.result(message.id, { configOptions = {} }) }
    end,
    ['session/fork'] = function(message)
      local source = message.params.sessionId
      local meta = message.params._meta
      local point = meta and meta.jetbrains and meta.jetbrains.air and meta.jetbrains.air.fork
      local copied = {}

      for _, update in ipairs(agent.histories[source] or {}) do
        copied[#copied + 1] = update
        if point and update.messageId == point.messageId then break end
      end

      agent.sessions = agent.sessions + 1
      agent.forked = { source = source, message_id = point and point.messageId }

      local id = 's' .. agent.sessions

      agent.histories[id] = copied

      return { jsonrpc.result(message.id, { sessionId = id }) }
    end,
    ['session/set_mode'] = function(message)
      return { jsonrpc.result(message.id, {}) }
    end,
    ['session/prompt'] = fake_agent.replying('ok'),
  }

  function agent:on_message(callback)
    self._deliver = callback
  end

  function agent:on_close(callback)
    self._close = callback
  end

  function agent:close()
    self.closed = true
  end

  function agent:push(...)
    for _, message in ipairs({ ... }) do
      self._deliver(message)
    end
  end

  function agent:exit(code)
    self.closed = true
    self._close({ code = code })
  end

  function agent:send(message)
    self.sent[#self.sent + 1] = message

    local handler = message.method and (script[message.method] or defaults[message.method]) or script.reply

    if message.method and message.id ~= nil and not handler then
      return self._deliver(jsonrpc.error(message.id, jsonrpc.METHOD_NOT_FOUND, 'Method not found: ' .. message.method))
    end

    for _, reply in ipairs(handler and handler(message, self) or {}) do
      self._deliver(reply)
    end
  end

  function agent:find(predicate)
    for _, message in ipairs(self.sent) do
      if predicate(message) then return message end
    end
  end

  function agent:sent_method(method)
    return self:find(function(message)
      return message.method == method
    end)
  end

  function agent:count(method)
    local n = 0

    for _, message in ipairs(self.sent) do
      if message.method == method then n = n + 1 end
    end

    return n
  end

  function agent:selected(id)
    local reply = self:find(function(message)
      return message.id == (id or 'perm-1') and message.result ~= nil
    end)

    return reply and reply.result.outcome.optionId
  end

  return agent
end

return fake_agent
