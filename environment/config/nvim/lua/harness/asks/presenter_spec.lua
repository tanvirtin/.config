local asks = require('harness.asks')
local async = require('harness.async')
local client = require('harness.client')
local display = require('harness.ui.display')
local presenter = require('harness.asks.presenter')
local events = require('harness.types.events')

local eq = assert.are.same

describe('harness.asks.presenter:', function()
  local sessions, notified, opened
  local originals = {}

  local function session(key, parent)
    local found = { key = key, parent = parent }

    sessions[key] = found

    return found
  end

  local function prompt()
    return {
      future = async.Future(),
      is_open = function(self)
        return not self.future.done
      end,
      dismiss = function() end,
    }
  end

  local function open_table()
    for i = 1, 10 do
      local name, value = debug.getupvalue(asks.asks_of, i)

      if name == 'open' then return value end
    end
  end

  before_each(function()
    sessions, notified, opened = {}, {}, false
    originals.session = client.session
    originals.notify = client.notify
    originals.buffer_of = display.buffer_of
    originals.open = display.open

    client.session = function(key)
      return sessions[key]
    end
    client.notify = function(target, update)
      notified[#notified + 1] = { session = target, kind = update.kind }
    end
    display.buffer_of = function()
      return 1
    end
    display.open = function()
      opened = true
    end
  end)

  after_each(function()
    vim.wait(20)
    client.session = originals.session
    client.notify = originals.notify
    display.buffer_of = originals.buffer_of
    display.open = originals.open
  end)

  it('lists only the session itself when it has no parent', function()
    local child = session('a')

    eq({ child }, presenter.holders(child))
  end)

  it('lists the session and then each ancestor in order', function()
    local child = session('a', 'b')
    local parent = session('b', 'c')
    local grand = session('c')

    eq({ child, parent, grand }, presenter.holders(child))
  end)

  it('stops walking when a parent key does not resolve to a session', function()
    local child = session('a', 'gone')

    eq({ child }, presenter.holders(child))
  end)

  it('stops walking when the ancestors loop back on themselves', function()
    local child = session('a', 'b')
    local parent = session('b', 'a')

    eq({ child, parent }, presenter.holders(child))
  end)

  it('stops walking after MAX_HOPS ancestors', function()
    for i = 0, presenter.MAX_HOPS + 2 do
      session('n' .. i, 'n' .. (i + 1))
    end

    local holders = presenter.holders(sessions.n0)

    eq(presenter.MAX_HOPS + 1, #holders)
    eq(sessions['n' .. presenter.MAX_HOPS], holders[#holders])
  end)

  it('adds the prompt to the session and every ancestor', function()
    local child = session('a', 'b')
    local parent = session('b')
    local item = prompt()

    presenter.present(child, item)

    eq({ item }, asks.asks_of(child))
    eq({ item }, asks.asks_of(parent))
  end)

  it('leaves unrelated sessions without the prompt', function()
    local child = session('a', 'b')
    local other = session('c')

    presenter.present(child, prompt())

    eq({}, asks.asks_of(other))
  end)

  it('returns the future the prompt carries', function()
    local child = session('a')
    local item = prompt()

    eq(item.future, presenter.present(child, item))
  end)

  it('removes the prompt from every holder once its future completes', function()
    local child = session('a', 'b')
    local parent = session('b')
    local item = prompt()
    local open = open_table()

    presenter.present(child, item)
    item.future:set_result('done')
    async.drain()

    eq({}, asks.asks_of(child))
    eq({}, asks.asks_of(parent))
    eq(nil, open[child])
    eq(nil, open[parent])
  end)

  it('notifies the session and its ancestors that they are waiting', function()
    local child = session('a', 'b')
    local parent = session('b')

    presenter.present(child, prompt())
    vim.wait(20)

    eq({
      { session = child, kind = events.NOTICE.waiting },
      { session = parent, kind = events.NOTICE.waiting },
    }, notified)
  end)

  it('opens the transcript in the background when nothing shows the session', function()
    display.buffer_of = function()
      return nil
    end

    presenter.present(session('a'), prompt())
    vim.wait(20)

    assert.is_true(opened)
  end)

  it('does not open the transcript when it is already shown', function()
    presenter.present(session('a'), prompt())
    vim.wait(20)

    assert.is_false(opened)
  end)
end)
