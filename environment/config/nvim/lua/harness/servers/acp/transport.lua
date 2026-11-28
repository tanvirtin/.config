local Timer = require('core.Timer')
local console = require('core.console')
local process = require('core.system.process')
local jsonrpc = require('harness.servers.acp.jsonrpc')

local transport = {}

transport.CLOSE_TIMEOUT_MS = 1000
transport.MAX_FRAME_BYTES = 16 * 1024 * 1024
transport.STDERR_KEEP_BYTES = 8 * 1024

function transport.process(cmd, opts)
  opts = opts or {}

  local self = { stderr = {} }
  local pending, held = {}, 0
  local stderr_held = 0
  local on_message, on_close

  local function consume(chunk)
    pending[#pending + 1] = chunk
    held = held + #chunk

    if not chunk:find('\n', 1, true) then
      if held > transport.MAX_FRAME_BYTES then
        console.debug.warn('Harness: dropped an agent frame that grew past ' .. transport.MAX_FRAME_BYTES .. ' bytes')
        pending, held = {}, 0
      end

      return
    end

    local buffer = table.concat(pending)
    pending, held = {}, 0

    local from = 1

    while true do
      local newline = buffer:find('\n', from, true)

      if not newline then break end

      if newline > from then
        local line = buffer:sub(from, newline - 1)
        local ok, message = pcall(jsonrpc.decode, line)

        if ok and type(message) == 'table' then
          Timer.schedule(function()
            if on_message then on_message(message) end
          end)
        else
          console.debug.warn('Harness: dropped a malformed agent frame: ' .. line:sub(1, 200))
        end
      end

      from = newline + 1
    end

    if from <= #buffer then
      pending[1] = buffer:sub(from)
      held = #buffer - from + 1
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
      if not data then return end

      self.stderr[#self.stderr + 1] = data
      stderr_held = stderr_held + #data

      if stderr_held > transport.STDERR_KEEP_BYTES * 2 then
        local tail = table.concat(self.stderr):sub(-transport.STDERR_KEEP_BYTES)

        self.stderr = { tail }
        stderr_held = #tail
      end
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
      if not proc:wait(transport.CLOSE_TIMEOUT_MS) then proc:kill(9) end
    end)
  end

  return self
end

return transport
