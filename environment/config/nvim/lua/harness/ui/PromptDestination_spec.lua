local PromptDestination = require('harness.ui.PromptDestination')

local eq = assert.are.same

local function session(opts)
  opts = opts or {}

  return {
    key = 'h1',
    dir = '/w',
    state = opts.state or 'idle',
    running = function()
      return opts.running == true
    end,
    can = function(_, name)
      return opts.can ~= nil and opts.can[name] == true
    end,
  }
end

local function collected(destination, shown)
  local labels = {}

  destination:hints(function(lhs, label)
    labels[#labels + 1] = lhs .. ' ' .. label
  end, shown)

  return labels
end

local KEYS = { steer = '<C-s>', interrupt = '<C-c>' }

describe('harness.ui.PromptDestination:', function()
  it('is not answering anything, keeps a draft and offers the history', function()
    local destination = PromptDestination(session(), {}, nil)

    eq(nil, destination:answers())
    eq(nil, destination:label())
    eq(true, destination:keeps_draft())
    eq(true, destination:history_hint())
    assert.truthy(destination:placeholder():find('ask anything', 1, true))
  end)

  it('hints at sending when idle, and at queueing, steering and interrupting while a turn runs', function()
    local idle = PromptDestination(session(), {}, nil)
    local running = PromptDestination(session({ running = true, can = { steer = true } }), {}, nil)

    eq({ '<CR> send' }, collected(idle, { keys = KEYS, send = '<CR>', inserting = false }))
    eq(
      { '<CR> queue', '<C-s> steer', '<C-c> interrupt' },
      collected(running, { keys = KEYS, send = '<CR>', inserting = false })
    )
    eq({ '<CR> queue', '<C-s> steer' }, collected(running, { keys = KEYS, send = '<CR>', inserting = true }))
  end)

  it('sends nothing for empty text, and keeps the text of a session that has ended', function()
    eq(true, (PromptDestination(session(), {}, nil):submit('', { source = {} })))

    local sent, why = PromptDestination(session({ state = 'closed' }), {}, nil):submit('hello', { source = {} })

    eq(false, sent)
    assert.truthy(why:find('has ended', 1, true))
  end)
end)
