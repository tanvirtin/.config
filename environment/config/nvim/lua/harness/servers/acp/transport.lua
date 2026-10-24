local Timer = require('core.Timer')
local process = require('core.process')
local jsonrpc = require('harness.servers.acp.jsonrpc')

local transport = {}

transport.CLOSE_TIMEOUT_MS = 1000

function transport.process(cmd, opts)
  opts = opts or {}

  local self = { stderr = {} }
  local buffer = ''
  local on_message, on_close

  local function consume(chunk)
    buffer = buffer .. chunk

    local from = 1

    while true do
      local newline = buffer:find('\n', from, true)

      if not newline then break end

      if newline > from then
        local ok, message = pcall(jsonrpc.decode, buffer:sub(from, newline - 1))

        if ok and type(message) == 'table' then
          Timer.schedule(function()
            if on_message then on_message(message) end
          end)
        end
      end

      from = newline + 1
    end

    buffer = buffer:sub(from)
  end

  local proc = process.system(cmd, {
    stdin = true,
    env = opts.env,
    cwd = opts.cwd,
    stdout = function(_, data)
      if data then consume(data) end
    end,
    stderr = function(_, data)
      if data then self.stderr[#self.stderr + 1] = data end
    end,
  }, function(out)
    Timer.schedule(function()
      if on_close then on_close(out) end
    end)
  end)

  function self:send(message)
    proc:write(jsonrpc.encode(message) .. '\n')
  end

  function self:on_message(callback)
    on_message = callback
  end

  function self:on_close(callback)
    on_close = callback
  end

  function self:close()
    pcall(function()
      proc:write(nil)
      proc:kill(15)
      proc:wait(transport.CLOSE_TIMEOUT_MS)
    end)
  end

  return self
end

return transport
