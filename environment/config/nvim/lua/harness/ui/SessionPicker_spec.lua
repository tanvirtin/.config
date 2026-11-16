local hub = require('harness.hub')
local surfaces = require('surfaces')
local Tile = require('ui.pixel.Tile')
local agent = require('harness.agent')
local async = require('harness.async')
local graphics = require('core.graphics')
local ticker = require('ui.pixel.ticker')
local indicators = require('ui.pixel.indicators')
local jsonrpc = require('harness.servers.acp.jsonrpc')
local SessionPicker = require('harness.ui.SessionPicker')
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
    return #picker._stored > 0
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

describe('harness.ui.SessionPicker:', function()
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

  it('overlays the state indicator on a running live row when pixels are available', function()
    stub_pixels(true)

    local live = hub.start({ dir = '/w' }):wait()

    live.running = function()
      return true
    end

    local picker = open()
    local placed = record_extmarks(picker._body.elements.list)

    picker:refresh()

    local found = overlays(placed)

    eq(1, #found)
    eq({ row = 1, col = 1, pos = 'overlay' }, { row = found[1].row, col = found[1].col, pos = found[1].pos })
    eq({ indicators.chunk('spinner', 'accent') }, found[1].texts)
  end)

  it('places no overlay without pixels', function()
    stub_pixels(false)

    local live = hub.start({ dir = '/w' }):wait()

    live.running = function()
      return true
    end

    local picker = open()
    local placed = record_extmarks(picker._body.elements.list)

    picker:refresh()

    eq({}, overlays(placed))
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
