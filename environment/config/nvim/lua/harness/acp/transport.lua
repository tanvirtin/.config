local Timer = require('core.Timer')
local process = require('core.process')
local jsonrpc = require('harness.acp.jsonrpc')

local transport = {}

function transport.process(cmd, opts)
  opts = opts or {}

  local self = { stderr = {} }
  local buffer = ''
  local on_message, on_close

  local function consume(chunk)
    buffer = buffer .. chunk

    while true do
      local newline = buffer:find('\n', 1, true)

      if not newline then break end

      local line = buffer:sub(1, newline - 1)
      buffer = buffer:sub(newline + 1)

      if #line > 0 then
        local ok, message = pcall(jsonrpc.decode, line)

        if ok and type(message) == 'table' then
          Timer.schedule(function()
            if on_message then on_message(message) end
          end)
        end
      end
    end
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
    end)
  end

  return self
end

return transport
