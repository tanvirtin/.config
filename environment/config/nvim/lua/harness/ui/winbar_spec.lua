local winbar = require('harness.ui.winbar')

local eq = assert.are.same

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
    waiting = function()
      return fields.waiting or {}
    end,
  }

  for key, value in pairs(fields) do
    if key ~= 'mode' and key ~= 'model' and key ~= 'waiting' then out[key] = value end
  end

  return out
end

describe('harness.ui.winbar:', function()
  it('counts running agents, and says how long the quietest has been silent', function()
    local summary = { active = 2, quiet = 125000 }
    local text = winbar.transcript(session({
      state = 'running',
      subagents = {
        summary = function()
          return summary
        end,
      },
    }))

    assert.truthy(text:find('2 agents · quiet 2m', 1, true))

    summary = { active = 1, quiet = 1000 }
    text = winbar.transcript(session({
      subagents = {
        summary = function()
          return summary
        end,
      },
    }))

    assert.truthy(text:find('1 agent', 1, true))
    assert.is_nil(text:find('quiet', 1, true))
  end)

  it('flags a permission ask waiting for you', function()
    assert.truthy(winbar.transcript(session({ waiting = { { tool = 'Bash' } } })):find('waiting for you', 1, true))
    assert.is_nil(winbar.transcript(session({})):find('waiting for you', 1, true))
  end)

  it('shows the hints, the state, the mode and the model', function()
    local text = winbar.transcript(session({ mode = { id = 'plan', name = 'Plan' }, model = { name = 'Sonnet' } }))

    assert.truthy(text:find(winbar.hints(), 1, true))
    assert.truthy(text:find('○ idle', 1, true))
    assert.truthy(text:find('[Plan]', 1, true))
    assert.truthy(text:find('Sonnet', 1, true))
  end)

  it('shows running and closed states', function()
    assert.truthy(winbar.transcript(session({ state = 'running' })):find('◆ running', 1, true))
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

  it('shows the scrolled-past prompt in place of the hints', function()
    local text = winbar.transcript(session({}), { lines = { '> fix the 100% bug', '> please' } })

    assert.is_nil(text:find(winbar.hints(), 1, true))
    assert.truthy(text:find('❯ %#UiMuted#fix the 100%% bug', 1, true))
  end)

  it('fits the scrolled-past prompt into what the status leaves of the window', function()
    local text = winbar.transcript(session({ mode = { id = 'plan', name = 'Plan' } }), {
      lines = { '> ' .. string.rep('word ', 40) },
    }, 60)

    assert.is_true(winbar.visible_width(text) <= 60)
    assert.truthy(text:find('[Plan]', 1, true))
  end)

  it('measures what a winbar shows, without its highlight codes', function()
    eq(5, winbar.visible_width('%#UiMuted#a%%b%=cd'))
  end)
end)
