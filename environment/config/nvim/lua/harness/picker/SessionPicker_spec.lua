local hub = require('harness.session.hub')
local surfaces = require('surfaces')
local Tile = require('ui.pixel.Tile')
local agent = require('harness.agent')
local async = require('harness.async')
local graphics = require('core.editor.graphics')
local ticker = require('ui.pixel.ticker')
local indicators = require('ui.pixel.indicators')
local jsonrpc = require('harness.servers.acp.jsonrpc')
local SessionPicker = require('harness.picker.SessionPicker')
local fake_agent = require('harness.servers.acp.fake_agent')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)

local FORKABLE = {
  initialize = function(message)
    return {
      jsonrpc.result(message.id, {
        protocolVersion = 1,
        agentCapabilities = {
          loadSession = true,
          sessionCapabilities = { list = {}, close = {}, resume = {}, delete = {}, fork = {}, systemPrompt = {} },
        },
      }),
    }
  end,
}

local function settle(predicate)
  vim.wait(1000, predicate, 10)
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function stub_pixels(available)
  Tile.available = function()
    return available
  end
  graphics.upload = function() end
  graphics.delete = function() end
end

local function open()
  local picker = SessionPicker.launch({ dir = '/w' })

  settle(function()
    return #picker._stored > 0 and picker._listing == nil
  end)

  return picker
end

local function record_extmarks(element)
  local placed = {}
  local original = element.place_extmark_text

  element.place_extmark_text = function(self, opts)
    placed[#placed + 1] = opts

    return original(self, opts)
  end

  return placed
end

local function overlays(placed)
  local out = {}

  for _, opts in ipairs(placed) do
    if opts.pos == 'overlay' then out[#out + 1] = opts end
  end

  return out
end

local function glitches(element)
  local namespace = vim.api.nvim_get_namespaces()['harness.session_picker.glitch']
  local buffer = element:get_buffer()
  local marks = vim.api.nvim_buf_get_extmarks(buffer.bufnr, namespace, 0, -1, { details = true })

  return vim.tbl_filter(function(mark)
    local text = mark[4].virt_text

    return text and text[1] and text[1][1]:find('[░▒▓▚▞]') ~= nil
  end, marks)
end

describe('harness.picker.SessionPicker:', function()
  local fake, original, agent_names

  before_each(function()
    async.drain()
    hub.shutdown()
    surfaces.close_all()
    hub.config = vim.deepcopy(defaults)
    hub.config.spawn = function()
      fake = fake_agent.new(FORKABLE)
      fake.stored = { { sessionId = 'old', cwd = '/w', title = 'Yesterday', updatedAt = '2026-10-17T09:30:00Z' } }

      return fake
    end
    agent_names = agent.names
    agent.names = function()
      return { 'claude' }
    end
    original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
  end)

  after_each(function()
    indicators.stop()
    ticker.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
    agent.names = agent_names
    surfaces.close_all()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
  end)

  it('tells the user its fork and delete keys in the footer', function()
    local picker = open()
    local footer = picker._body.elements.footer:get_lines()[1]

    assert.is_truthy(footer:find('<C-f> fork', 1, true))
    assert.is_truthy(footer:find('<C-x> delete (press twice)', 1, true))
  end)

  it('forks the selected stored session through its agent', function()
    local picker = open()

    picker:query('Yesterday')
    press('<C-f>')
    settle(function()
      return fake.forked ~= nil
    end)

    eq('old', fake.forked.source)
  end)

  it('does not fork the new-session row', function()
    local picker = open()

    picker:fork()

    eq(nil, fake.forked)
    assert.is_truthy(picker:snapshot():find('New session', 1, true))
  end)

  it('deletes a stored session only on a second press of the delete key', function()
    local picker = open()

    picker:query('Yesterday')
    press('<C-x>')

    assert.is_truthy(picker:snapshot():find('Yesterday', 1, true))
    eq(nil, (fake:sent_method('session/delete')))

    press('<C-x>')
    settle(function()
      return fake:sent_method('session/delete') ~= nil
    end)

    eq('old', fake:sent_method('session/delete').params.sessionId)
    settle(function()
      return #picker._stored == 0
    end)
    eq(0, #picker._stored)
  end)

  it('does not delete the new-session row', function()
    local picker = open()

    press('<C-x>')
    press('<C-x>')
    vim.wait(50, function()
      return false
    end)

    eq(nil, (fake:sent_method('session/delete')))
    assert.is_truthy(picker:snapshot():find('New session', 1, true))
  end)

  it('overlays the state indicator on an idle live row when pixels are available', function()
    stub_pixels(true)

    hub.start({ dir = '/w' }):wait()

    local picker = open()
    local placed = record_extmarks(picker._body.elements.list)

    picker._drawn = nil
    picker:refresh()

    local found = overlays(placed)

    eq(1, #found)
    eq({ row = 2, col = 1, pos = 'overlay' }, { row = found[1].row, col = found[1].col, pos = found[1].pos })
    eq({ indicators.chunk('idle', 'muted') }, found[1].texts)
  end)

  it('places no overlay without pixels', function()
    stub_pixels(false)

    local live = hub.start({ dir = '/w' }):wait()

    live.running = function()
      return true
    end

    local picker = open()
    local placed = record_extmarks(picker._body.elements.list)

    picker._drawn = nil
    picker:refresh()

    eq({}, overlays(placed))
  end)

  local function list_lines(picker)
    return picker._body.elements.list:get_lines()
  end

  local function talk(live, prompt, reply)
    live.log:append({ kind = 'prompt', text = prompt })
    live.log:append({ kind = 'message', text = reply })
  end

  it('groups the rows under Live and Recent headers, and moves past them', function()
    hub.start({ dir = '/w' }):wait()

    local picker = open()
    local lines = list_lines(picker)

    eq({ 'New session', 'Live 1', 'Recent 1' }, {
      vim.trim(lines[1]:gsub('^%s*%+', '')),
      vim.trim(lines[2]),
      vim.trim(lines[4]),
    })

    eq(2, picker._selected)
    eq({ 3, 5 }, { picker._line_of[2], picker._line_of[3] })

    picker:move('down')

    eq(3, picker._selected)
    eq(5, picker._body.elements.list:get_cursor()[1])

    picker:query('Yesterday')
    eq(
      {},
      vim.tbl_filter(function(line)
        return line:find('Recent', 1, true) ~= nil
      end, list_lines(picker))
    )
  end)

  it('ranks the best match first, and highlights what matched in the label', function()
    local picker = open()
    local list = picker._body.elements.list
    local marks = {}
    local place = list.place_extmark_highlight

    list.place_extmark_highlight = function(self, opts)
      marks[#marks + 1] = opts

      return place(self, opts)
    end

    picker:query('yest')

    eq(1, #picker._filtered)
    eq({ 1, 2, 3, 4 }, picker._filtered[1].match)

    local matched = vim.tbl_filter(function(mark)
      return mark.hl == 'UiAccent' and mark.col_range.to - mark.col_range.from == 4
    end, marks)

    eq(1, #matched)
  end)

  it('finds a live session by what was said in it, ranked below title matches', function()
    local live = hub.start({ dir = '/w' }):wait()

    talk(live, 'please untangle the scroll pin', 'it is the sticky bottom')

    local picker = open()

    picker:query('sticky')

    eq(1, #picker._filtered)
    eq(live, picker._filtered[1].session)

    picker:query('zzzzzz')
    eq(0, #picker._filtered)
    assert.is_truthy(list_lines(picker)[1]:find('no matches', 1, true))
  end)

  it('shows context, turns and the buffer in the detail of a live session', function()
    local live = hub.start({ dir = '/w' }):wait()

    talk(live, 'hello', 'hi')
    live.log:append({ kind = 'usage', used = 40, size = 100, cost = 0.5 })

    local picker = open()

    picker._selected = 2
    picker:refresh()

    local detail = table.concat(picker._body.elements.detail:get_lines(), '\n')

    assert.is_truthy(detail:find('context  40%% · 1 turn · $0.50'))
    assert.is_truthy(detail:find('buffer  not loaded', 1, true))
  end)

  it('leaves the list alone when a refresh changes nothing', function()
    hub.start({ dir = '/w' }):wait()

    local picker = open()
    local list = picker._body.elements.list
    local writes = 0
    local set_lines = list.set_lines

    list.set_lines = function(self, lines)
      writes = writes + 1

      return set_lines(self, lines)
    end

    picker:refresh()
    picker:refresh()

    eq(0, writes)
  end)

  it('tunes the selected label in out of static as the selection moves, then settles', function()
    hub.start({ dir = '/w' }):wait()

    local picker = open()
    local placed = record_extmarks(picker._body.elements.list)

    picker:move('down')

    local flickers = vim.tbl_filter(function(mark)
      return mark.pos == 'overlay' and mark.texts[1][1]:find('[░▒▓▚▞]') ~= nil
    end, placed)

    assert.is_true(#flickers > 0)

    vim.wait(400, function()
      return picker._tune == nil
    end, 20)

    eq(nil, picker._tune)
  end)

  it('keeps autocompletion out of its search line', function()
    local picker = open()

    eq(false, vim.b[picker._body.elements.input:get_buffer().bufnr].completion)
  end)

  it('gives up on the listing static when an agent never answers', function()
    local picker = SessionPicker.launch({ dir = '/w' })

    picker._listing.pending = 99
    picker._listing.gives_up = require('core.Timer').now()

    settle(function()
      return picker._listing == nil
    end)

    eq(nil, picker._listing)
    eq(nil, picker._lister)
  end)

  it('glitches the rows while it lists the stored sessions', function()
    local picker = SessionPicker.launch({ dir = '/w' })
    local body = picker._body.elements

    assert.is_not_nil(picker._listing)
    assert.is_truthy(body.title:get_lines()[1]:find('Harness', 1, true))
    assert.is_truthy(table.concat(list_lines(picker), '\n'):find('New session', 1, true))

    local flickered = vim.wait(200, function()
      return #glitches(body.list) > 0
    end, 10)

    assert.is_true(flickered)

    settle(function()
      return picker._listing == nil
    end)

    eq(nil, picker._listing)
    eq(0, #glitches(body.list))
    assert.is_truthy(table.concat(list_lines(picker), '\n'):find('Recent', 1, true))
  end)

  it('keeps the rows glitched while a stored session loads, then opens it', function()
    local picker = open()

    picker:query('Yesterday')
    picker:select()

    assert.is_not_nil(picker._loading)
    eq(true, picker._loader:is_active())

    local body = picker._body.elements
    local title = body.title:get_lines()[1]

    assert.is_truthy(title:find('loading', 1, true))
    assert.is_truthy(title:find('Yesterday', 1, true))
    assert.is_truthy(table.concat(list_lines(picker), '\n'):find('Yesterday', 1, true))
    assert.is_true(#glitches(body.list) > 0)
    assert.is_true(#glitches(body.detail) > 0)

    picker:select()
    eq('old', picker._loading.id)

    settle(function()
      return picker.state == 'closed'
    end)

    eq('closed', picker.state)
    eq(nil, picker._loading)
    eq(false, picker._loader and picker._loader:is_active() or false)
  end)

  it('leaves insert mode when it closes, so the transcript it opens is normal', function()
    local Window = require('core.editor.Window')
    local picker = open()
    local stopped = false
    local original = Window.stop_insert

    Window.stop_insert = function()
      stopped = true
    end

    picker:close()

    Window.stop_insert = original

    eq(true, stopped)
  end)

  it('stops its refresh timer and releases the state badge on close', function()
    hub.start({ dir = '/w' }):wait()

    local picker = open()

    assert.is_not_nil(picker._badge)
    eq(true, picker._timer:is_active())

    local released = false
    local release = picker._badge.release

    picker._badge.release = function()
      released = true
      release()
    end

    picker:close()

    eq(true, released)
    eq(nil, picker._badge)
    eq(false, picker._timer:is_active())
  end)
end)
