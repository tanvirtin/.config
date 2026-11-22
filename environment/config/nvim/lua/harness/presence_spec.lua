local Lens = require('ui.Lens')
local Timer = require('core.Timer')
local guides = require('ui.guides')
local Window = require('core.editor.Window')
local events = require('harness.types.events')
local presence = require('harness.presence')

local eq = assert.are.same
local Presence = presence.Presence
local K = events.KIND

local function fake_session()
  local listeners = {}

  return {
    key = 's1',
    queue = {},
    pending = {},
    waiting = function(self)
      return self.pending
    end,
    subscribe = function(_, fn)
      listeners[#listeners + 1] = fn

      return function()
        for i, candidate in ipairs(listeners) do
          if candidate == fn then table.remove(listeners, i) end
        end
      end
    end,
    emit = function(self, event)
      for _, fn in ipairs(vim.list_slice(listeners)) do
        fn(event, self)
      end
    end,
    listeners = function()
      return #listeners
    end,
  }
end

describe('harness.presence:', function()
  local window, buffer, session

  local function marks()
    return buffer:get_extmarks(Lens.NAMESPACE, 0, -1, { details = true })
  end

  local function row(n)
    local mark = marks()[1]
    local line = mark and mark[4].virt_lines[n]

    return line and table.concat(vim.tbl_map(function(chunk)
      return chunk[1]
    end, line)) or ''
  end

  local function text()
    return row(1) .. '\n' .. row(2)
  end

  local function group_of(n, needle)
    for _, chunk in ipairs(marks()[1][4].virt_lines[n]) do
      if chunk[1]:find(needle, 1, true) then return chunk[2] end
    end
  end

  local function start(line)
    return presence.show(session, { win = window.win_id, line = line or 20 })
  end

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')

    window = Window.get_current()
    buffer = window:get_buffer()
    session = fake_session()

    local lines = {}

    for i = 1, 60 do
      lines[i] = 'line ' .. i
    end

    buffer:set_lines(lines)
    vim.wo.scrolloff = 0
    vim.api.nvim_win_set_cursor(window.win_id, { 20, 0 })
  end)

  after_each(function()
    presence.clear_all()
    guides.clear('s1')
    buffer:clear_namespace(Lens.NAMESPACE)
  end)

  describe('bar', function()
    local function shape(step)
      return table.concat(vim.tbl_map(function(chunk)
        return chunk[1]
      end, Presence.bar(step, 10)))
    end

    it('should be the width asked for, in three runs', function()
      eq(10, vim.fn.strchars(shape(0)))
      eq(3, #Presence.bar(4, 10))
    end)

    it('should move exactly one cell per frame, bouncing at the ends, never skipping or stalling', function()
      for step = 0, 100 do
        eq(1, math.abs(Presence.head(step + 1, 10) - Presence.head(step, 10)))
      end
    end)

    it('should keep the bright part inside the bar', function()
      for step = 0, 100 do
        local head = Presence.head(step, 10)

        assert.is_true(head >= 0 and head <= 9)
      end
    end)
  end)

  describe('count', function()
    it('should say one thing and several things', function()
      eq('1 step', Presence.count(1, 'step'))
      eq('2 steps', Presence.count(2, 'step'))
      eq('0 notes', Presence.count(0, 'note'))
    end)
  end)

  describe('tail', function()
    it('should keep the newest end of the last line that has text', function()
      eq('second line', Presence.tail('first line\nsecond line\n\n', 40))
      eq('…world', Presence.tail('hello world', 6))
      eq('a b', Presence.tail('  a\t  b  ', 40))
      eq('', Presence.tail(nil, 40))
    end)

    it('should count characters, not bytes, so it never cuts one in half', function()
      local tail = Presence.tail('héllö wörld', 5)

      eq(5, vim.fn.strchars(tail))
      eq('…örld', tail)
    end)
  end)

  describe('detail', function()
    it('should name what a tool touches: a location, then a command or a pattern', function()
      eq('/w/a.lua', Presence.detail({ locations = { { path = '/w/a.lua' } } }))
      eq('make test', Presence.detail({ input = { command = 'make test' } }))
      eq('Session:prompt', Presence.detail({ input = { pattern = 'Session:prompt' } }))
      eq('', Presence.detail({ title = 'Think' }))
    end)
  end)

  describe('sentence', function()
    it('should take the first sentence, or the first line when there is no full stop', function()
      eq('It is used twice.', Presence.sentence('It is used twice. Once in a spec.'))
      eq('what is this?', Presence.sentence('what is this?'))
      eq('first', Presence.sentence('first\nsecond'))
      eq('', Presence.sentence(nil))
    end)
  end)

  describe('starting', function()
    it('should reserve two rows above the line it was asked from', function()
      start()

      eq(1, #marks())
      eq(19, marks()[1][2])
      eq(2, #marks()[1][4].virt_lines)
      eq(true, marks()[1][4].virt_lines_above)
    end)

    it('should give nothing for a window that is gone', function()
      eq(nil, presence.show(session, { win = 99999, line = 1 }))
      eq(0, #marks())
    end)

    it('should replace an earlier presence for the same session', function()
      start(10)
      start(30)

      eq(1, #marks())
      eq(29, marks()[1][2])
      eq(1, session.listeners())
    end)
  end)

  describe('working', function()
    it('should say what the agent is doing now, and count its steps', function()
      start()
      session:emit({ kind = K.tool_call, id = 't1', title = 'Read DepthTree.lua' })
      session:emit({ kind = K.tool_update, id = 't1', title = 'Read DepthTree.lua' })
      session:emit({ kind = K.tool_call, id = 't2', title = 'Grep value' })
      presence.get('s1'):draw(Timer.now())

      assert.is_truthy(text():find('Grep value', 1, true))
      assert.is_truthy(text():find('2 steps', 1, true))
    end)

    it('should say it is thinking, and then that it is writing', function()
      start()
      session:emit({ kind = K.thought, text = 'hm' })
      presence.get('s1'):draw(Timer.now())
      assert.is_truthy(text():find('thinking', 1, true))

      session:emit({ kind = K.message, text = 'It is used here.' })
      presence.get('s1'):draw(Timer.now())
      assert.is_truthy(text():find('writing the answer', 1, true))
    end)

    it('should point at the request that needs you, and the key to reach it', function()
      start()
      session.pending = { { title = 'Run rm -rf build' } }
      presence.get('s1'):draw(Timer.now())

      assert.is_truthy(text():find('waiting for you', 1, true))
      assert.is_truthy(text():find('Run rm -rf build', 1, true))
      assert.is_truthy(text():find('<leader>aw', 1, true))
    end)

    it('should count the notes the agent has put on screen', function()
      start()
      guides.mark('s1', buffer, { from = 40, step = 1, label = 'here' })
      presence.get('s1'):draw(Timer.now())

      assert.is_truthy(text():find('1 note, ]g', 1, true))
    end)
  end)

  describe('finishing', function()
    it('should show the first sentence of the answer, and keep it for a while', function()
      start()
      session:emit({ kind = K.message, text = 'It is used in two places. One is a spec.' })
      session:emit({ kind = K.stop, reason = 'end_turn' })

      eq('done', presence.get('s1').phase)
      assert.is_truthy(text():find('✓', 1, true))
      assert.is_truthy(text():find('It is used in two places.', 1, true))
      assert.is_nil(text():find('One is a spec', 1, true))
      assert.is_truthy(text():find('<leader>as chat', 1, true))
    end)

    it('should say done when the agent said nothing', function()
      start()
      session:emit({ kind = K.stop, reason = 'end_turn' })

      assert.is_truthy(text():find('done', 1, true))
    end)

    it('should stay while a queued prompt is still to run', function()
      start()
      session.queue = { 'next' }
      session:emit({ kind = K.stop, reason = 'end_turn' })

      eq('working', presence.get('s1').phase)
    end)

    it('should say it failed, with the reason', function()
      start()
      session:emit({ kind = K.error, message = 'the agent crashed' })

      eq('failed', presence.get('s1').phase)
      assert.is_truthy(text():find('the agent crashed', 1, true))
    end)

    it('should say it was stopped when cancelled', function()
      start()
      session:emit({ kind = K.stop, reason = 'cancelled' })

      eq('stopped', presence.get('s1').phase)
      assert.is_truthy(text():find('stopped', 1, true))
    end)

    it('should fade away after lingering, giving the room back', function()
      start()
      session:emit({ kind = K.stop, reason = 'end_turn' })

      local shown = presence.get('s1')

      shown.finished = Timer.now() - Presence.LINGER_MS - 1
      shown:tick()

      eq(nil, presence.get('s1'))
      eq(0, #marks())
      eq(0, session.listeners())
    end)

    it('should go when a new turn starts on the session, once it is finished', function()
      start()
      session:emit({ kind = K.stop, reason = 'end_turn' })
      session:emit({ kind = K.prompt, text = 'next' })

      eq(nil, presence.get('s1'))
      eq(0, #marks())
    end)

    it('should ignore a prompt while it is still working, such as its own queue', function()
      start()
      session:emit({ kind = K.prompt, text = 'queued' })

      assert.is_truthy(presence.get('s1'))
    end)
  end)

  describe('streaming on the second row', function()
    it('should show the newest words of the answer as they arrive', function()
      start()
      session:emit({ kind = K.message, text = 'It is used in two places.\nThe first one is' })
      presence.get('s1'):draw(Timer.now())

      eq(true, row(2):find('The first one is', 1, true) ~= nil)
      eq(nil, row(2):find('two places', 1, true))
    end)

    it('should show a thought in the thought colour', function()
      start()
      session:emit({ kind = K.thought, text = 'maybe it is the spec' })
      presence.get('s1'):draw(Timer.now())

      assert.is_truthy(row(2):find('maybe it is the spec', 1, true))
      eq({ Lens.BAND, 'UiThought' }, group_of(2, 'maybe'))
    end)

    it('should show the file a tool is reading', function()
      start()
      session:emit({ kind = K.tool_call, id = 't1', title = 'Read', locations = { { path = '/w/DepthTree.lua' } } })
      presence.get('s1'):draw(Timer.now())

      assert.is_truthy(row(2):find('DepthTree.lua', 1, true))
      eq({ Lens.BAND, 'UiPath' }, group_of(2, 'DepthTree'))
    end)

    it('should keep the loader on the first row while it streams', function()
      start()
      session:emit({ kind = K.message, text = 'streaming' })
      presence.get('s1'):draw(Timer.now())

      assert.is_truthy(row(1):find('writing the answer', 1, true))
      assert.is_truthy(row(1):find('▰', 1, true))
    end)

    it('should keep both rows when done, so the code below does not jump', function()
      start()
      session:emit({ kind = K.message, text = 'It is used twice. Once in a spec.' })
      session:emit({ kind = K.stop, reason = 'end_turn' })

      eq(2, #marks()[1][4].virt_lines)
      assert.is_truthy(row(1):find('done', 1, true))
      assert.is_truthy(row(2):find('It is used twice.', 1, true))
      eq(nil, row(2):find('Once in a spec', 1, true))
    end)

    it('should put the reason on the second row when it fails', function()
      start()
      session:emit({ kind = K.error, message = 'the agent crashed' })

      assert.is_truthy(row(1):find('failed', 1, true))
      assert.is_truthy(row(2):find('the agent crashed', 1, true))
    end)
  end)

  describe('drawing', function()
    it('should redraw only when the line changes', function()
      start()

      local shown = presence.get('s1')
      local now = Timer.now()

      eq(false, shown:draw(now))

      shown.frame = shown.frame + 1
      eq(true, shown:draw(now))
      eq(false, shown:draw(now))

      session:emit({ kind = K.thought, text = 'hm' })
      eq(true, shown:draw(now))
    end)

    it('should advance one frame per tick', function()
      start()

      local shown = presence.get('s1')

      shown:tick()
      shown:tick()

      eq(2, shown.frame)
    end)

    it('should stop moving once finished, so a still line costs nothing', function()
      start()
      session:emit({ kind = K.stop, reason = 'end_turn' })

      local shown = presence.get('s1')
      local now = shown.finished

      shown.frame = shown.frame + 5
      eq(false, shown:draw(now))
    end)
  end)

  describe('failing', function()
    local console = require('core.console')
    local warn, warned

    before_each(function()
      warn, warned = console.warn, {}
      console.warn = function(message)
        warned[#warned + 1] = message
      end
    end)

    after_each(function()
      console.warn = warn
    end)

    it('should stop itself, give the room back and warn once when a frame fails', function()
      start()

      local shown = presence.get('s1')

      shown.chunks = function()
        error('boom')
      end

      shown:tick()
      shown:tick()

      eq(nil, presence.get('s1'))
      eq(0, #marks())
      eq(0, session.listeners())
      eq(false, shown.ticker:is_active())
      eq(1, #warned)
      assert.is_truthy(warned[1]:find('boom', 1, true))
    end)

    it('should start nothing, with no timer left running, when the first frame fails', function()
      local chunks = Presence.chunks

      Presence.chunks = function()
        error('broken from the start')
      end

      local shown = start()

      Presence.chunks = chunks

      eq(nil, shown)
      eq(nil, presence.get('s1'))
      eq(0, #marks())
      eq(0, session.listeners())
      eq(1, #warned)
    end)

    it('should stop when the frame that finishes it fails', function()
      start()

      local shown = presence.get('s1')

      shown.chunks = function()
        error('boom')
      end

      session:emit({ kind = K.stop, reason = 'end_turn' })

      eq(nil, presence.get('s1'))
      eq(0, #marks())
    end)
  end)

  describe('clearing', function()
    it('should go when the window it sits in closes', function()
      vim.cmd('vsplit')

      window = Window.get_current()
      buffer = window:get_buffer()
      start(5)

      window:close()
      vim.wait(300, function()
        return presence.get('s1') == nil
      end)

      eq(nil, presence.get('s1'))
      eq(0, session.listeners())
    end)

    it('should stop its timer and its listener when cleared', function()
      start()
      presence.clear('s1')

      eq(0, session.listeners())
      eq(0, #marks())
      eq(nil, presence.get('s1'))
    end)

    it('should follow its line when text is inserted above it', function()
      start(20)
      vim.api.nvim_buf_set_lines(buffer.bufnr, 0, 0, false, { 'a', 'b' })

      eq(21, marks()[1][2])
    end)
  end)
end)
