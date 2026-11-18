local Timer = require('core.Timer')
local console = require('core.console')
local motion = require('ui.design.motion')

local ticker = {}

ticker.STEP_MS = motion.STEP_MS

local steps, order, timer = {}, {}, nil

local function close()
  if timer then timer:close() end

  timer = nil
end

function ticker.add(key, step)
  if not steps[key] then order[#order + 1] = key end

  steps[key] = step

  if not timer then
    timer = Timer()
    timer:every(ticker.STEP_MS, function()
      ticker.step(Timer.now())
    end)
  end
end

function ticker.remove(key)
  if not steps[key] then return end

  steps[key] = nil

  for index, existing in ipairs(order) do
    if existing == key then
      table.remove(order, index)
      break
    end
  end

  if #order == 0 then close() end
end

function ticker.count()
  return #order
end

function ticker.running()
  return timer ~= nil
end

function ticker.step(now)
  local keys = {}

  for index, key in ipairs(order) do
    keys[index] = key
  end

  for _, key in ipairs(keys) do
    local step = steps[key]

    if step then
      local ok, keep = pcall(step, now)

      if steps[key] == step and (not ok or not keep) then
        if not ok then console.notify_now('pixel animation stopped: ' .. tostring(keep), 'warn') end

        ticker.remove(key)
      end
    end
  end
end

function ticker.stop()
  steps, order = {}, {}

  close()
end

return ticker
