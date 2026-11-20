local Watch = require('harness.session.Watch')
local fake = require('harness.session.fake_session')
local settings = require('harness.settings.wake')

local eq = assert.are.same

describe('harness.session.Watch:', function()
  local saved, session, watch

  before_each(function()
    saved = {
      enabled = settings:get('enabled'),
      max = settings:get('max'),
      max_items = settings:get('max_items'),
      preview = settings:get('preview'),
      settle_ms = settings:get('settle_ms'),
      tools = settings:get('tools'),
    }

    settings:assign({ enabled = true, max = 3, max_items = 5, preview = 60, settle_ms = 1, tools = false })

    session = fake.session()
    watch = Watch(session)
  end)

  after_each(function()
    settings:assign(saved)
  end)

  local function woken(count)
    vim.wait(80, function()
      return #(session.queued or {}) >= (count or 1)
    end)

    return session.queued or {}
  end

  local function quiet()
    vim.wait(40)

    return session.queued or {}
  end

  it('wakes with one turn when work finishes after the turn ended', function()
    watch:open('subagent', 'c1', { title = 'Explore' })
    watch:turn_ended('end_turn')
    watch:settle('subagent', 'c1', { stop = 'end_turn', summary = 'found three call sites' })

    local queued = woken()

    eq(1, #queued)
    eq(true, queued[1].opts.wake)
    assert.is_truthy(queued[1].text:find('Explore', 1, true))
    assert.is_truthy(queued[1].text:find('found three call sites', 1, true))
  end)

  it('stays quiet when the work finished inside the turn', function()
    watch:open('subagent', 'c1', { title = 'Explore' })
    watch:settle('subagent', 'c1', { stop = 'end_turn' })
    watch:turn_ended('end_turn')

    eq({}, quiet())
  end)

  it('sends one message for work that finishes together', function()
    watch:open('subagent', 'c1', { title = 'one' })
    watch:open('subagent', 'c2', { title = 'two' })
    watch:turn_ended('end_turn')
    watch:settle('subagent', 'c1', { stop = 'end_turn' })
    watch:settle('subagent', 'c2', { stop = 'end_turn' })

    local queued = woken()

    eq(1, #queued)
    assert.is_truthy(queued[1].text:find('2 items', 1, true))
  end)

  it('stops after the budget, and counts a user prompt as a fresh start', function()
    for i = 1, 4 do
      watch:open('subagent', 'c' .. i, { title = 'child ' .. i })
      watch:turn_ended('end_turn')
      watch:settle('subagent', 'c' .. i, { stop = 'end_turn' })
      vim.wait(30)
    end

    eq(3, #(session.queued or {}))

    watch:prompted()
    eq(0, watch.wakes)

    watch:open('subagent', 'c5', { title = 'child 5' })
    watch:turn_ended('end_turn')
    watch:settle('subagent', 'c5', { stop = 'end_turn' })

    eq(4, #woken(4))
  end)

  it('forgets everything a cancelled turn left running', function()
    watch:open('subagent', 'c1', { title = 'Explore' })
    watch:turn_ended('cancelled')
    watch:settle('subagent', 'c1', { stop = 'end_turn' })

    eq({}, quiet())
  end)

  it('ignores tool calls until they are asked for', function()
    watch:open('tool', 't1', { name = 'Bash' })
    watch:turn_ended('end_turn')
    watch:settle('tool', 't1', { status = 'completed', output = 'all green' })

    eq({}, quiet())

    settings:assign({ tools = true })

    watch:open('tool', 't2', { name = 'Bash' })
    watch:turn_ended('end_turn')
    watch:settle('tool', 't2', { status = 'completed', output = 'all green' })

    local queued = woken()

    eq(1, #queued)
    assert.is_truthy(queued[1].text:find('Bash', 1, true))
    assert.is_truthy(queued[1].text:find('all green', 1, true))
  end)

  it('caps the items it names and says how many more there are', function()
    settings:assign({ max_items = 2 })

    for i = 1, 3 do
      watch:open('subagent', 'c' .. i, { title = 'child ' .. i })
    end

    watch:turn_ended('end_turn')

    for i = 1, 3 do
      watch:settle('subagent', 'c' .. i, { stop = 'end_turn' })
    end

    local queued = woken()

    eq(1, #queued)
    assert.is_truthy(queued[1].text:find('(+1 more)', 1, true))
  end)
end)
