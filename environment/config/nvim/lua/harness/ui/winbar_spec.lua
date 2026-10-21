local winbar = require('harness.ui.winbar')

local function session(fields)
  local out = {
    history = {},
    state = 'idle',
    running = function(self)
      return self.state == 'running'
    end,
    mode = function()
      return fields.mode
    end,
    choice = function()
      return fields.model
    end,
  }

  for key, value in pairs(fields) do
    if key ~= 'mode' and key ~= 'model' then out[key] = value end
  end

  return out
end

describe('harness.ui.winbar:', function()
  it('shows the hints, the state, the mode and the model', function()
    local text = winbar.transcript(session({ mode = { id = 'plan', name = 'Plan' }, model = { name = 'Sonnet' } }))

    assert.truthy(text:find(winbar.HINTS, 1, true))
    assert.truthy(text:find('○ idle', 1, true))
    assert.truthy(text:find('󰒓 Plan', 1, true))
    assert.truthy(text:find('Sonnet', 1, true))
  end)

  it('shows running and closed states', function()
    assert.truthy(winbar.transcript(session({ state = 'running' })):find('● running', 1, true))
    assert.truthy(winbar.transcript(session({ state = 'closed' })):find('○ closed', 1, true))
  end)

  it('shows context use and cost from the last usage event, escaping percent signs', function()
    local text = winbar.transcript(session({
      history = { { kind = 'usage', used = 50, size = 200, cost = 0.5 } },
      mode = { id = '100%' },
    }))

    assert.truthy(text:find('ctx 25%%', 1, true))
    assert.truthy(text:find('$0.50', 1, true))
    assert.truthy(text:find('100%%', 1, true))
  end)
end)
