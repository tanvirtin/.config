local FleetMember = require('harness.transcript.model.FleetMember')

local eq = assert.are.same

describe('harness.transcript.model.FleetMember', function()
  local PROMPT = { kind = 'prompt', text = 'go' }
  local STOP = { kind = 'stop', reason = 'end_turn' }

  local function session(fields)
    return vim.tbl_extend('force', {
      key = 'h2',
      dir = '/w',
      state = 'open',
      history = {},
      times = {},
      agent = { name = 'claude' },
      waiting = function()
        return {}
      end,
      running = function()
        return false
      end,
      choice = function(_, key)
        return key == 'model' and { name = 'haiku' } or nil
      end,
    }, fields or {})
  end

  local function of(fields, now)
    return FleetMember.of(session(fields), now)
  end

  local function running()
    return true
  end

  local function stop(reason)
    return { kind = 'stop', reason = reason }
  end

  local function message(text)
    return { kind = 'message', text = text }
  end

  local function tool_call(id, status, input)
    return {
      kind = 'tool_call',
      id = id,
      name = 'Read',
      status = status,
      input = input or { file_path = '/w/x.lua' },
    }
  end

  it('keeps the session key', function()
    eq('h2', of({}).key)
    eq('h7', of({ key = 'h7' }).key)
  end)

  it('is gone once the session is closed', function()
    eq('gone', of({ state = 'closed', history = { PROMPT } }).state)
  end)

  it('is waiting while the session has an open ask, and names the ask by its title or tool', function()
    local titled = {
      waiting = function()
        return { { title = 'Run tests?' } }
      end,
    }
    local tooled = {
      waiting = function()
        return { { tool = 'Bash' } }
      end,
    }

    eq('waiting', of(titled).state)
    eq('Run tests?', of(titled).ask)
    eq('Bash', of(tooled).ask)
    eq('waiting', of({ running = running, waiting = titled.waiting }).state)
  end)

  it('is working while a turn runs, and idle before any prompt', function()
    eq('working', of({ running = running, history = { PROMPT } }).state)
    eq('idle', of({ history = { message('hi') } }).state)
    eq('idle', of({}).state)
  end)

  it('is done after a turn ends normally', function()
    eq('done', of({ history = { PROMPT, STOP } }).state)
  end)

  it('is cancelled after a cancelled stop', function()
    eq('cancelled', of({ history = { PROMPT, stop('cancelled') } }).state)
  end)

  it('is failed after a refusal or a token limit', function()
    eq('failed', of({ history = { PROMPT, stop('refusal') } }).state)
    eq('failed', of({ history = { PROMPT, stop('max_tokens') } }).state)
  end)

  it('is failed when an error event follows the last prompt', function()
    eq('failed', of({ history = { PROMPT, { kind = 'error', text = 'boom' } } }).state)
    eq('failed', of({ history = { PROMPT, { kind = 'error', text = 'boom' }, STOP } }).state)
  end)

  it('ignores an error from an earlier turn', function()
    local history = { PROMPT, { kind = 'error', text = 'boom' }, PROMPT, STOP }

    eq('done', of({ history = history }).state)
  end)

  it('ignores child events when deciding the state', function()
    eq(
      'working',
      of({ running = running, history = { PROMPT, { kind = 'stop', reason = 'end_turn', parent = 'a' } } }).state
    )
  end)

  it('reports the newest unfinished tool call after the last prompt as its label', function()
    local history = {
      PROMPT,
      tool_call('a', 'completed'),
      tool_call('b', 'in_progress'),
    }

    eq('Read x.lua', of({ running = running, history = history }).tool)
  end)

  it('reports no tool when every call has finished or the turn has settled', function()
    assert.is_nil(of({ running = running, history = { PROMPT, tool_call('a', 'completed') } }).tool)
    assert.is_nil(of({ history = { PROMPT, tool_call('a', 'in_progress'), STOP } }).tool)
  end)

  it('ignores child tool calls when reporting the open tool', function()
    local child = tool_call('c', 'in_progress', { command = 'ls' })

    child.parent = 'a'

    local history = { PROMPT, tool_call('a', 'in_progress'), child }

    eq('Read x.lua', of({ running = running, history = history }).tool)
  end)

  it('reports the last message after the prompt as the result once settled', function()
    eq('found 3 things', of({ history = { PROMPT, message('found 3 things'), STOP } }).result)
    eq('b', of({ history = { PROMPT, message('a'), message('b'), STOP } }).result)
    eq('found 3 things', of({ history = { PROMPT, message('  found\n\n3   things  '), STOP } }).result)
  end)

  it('reports no result while the turn is unsettled or the message came before the prompt', function()
    assert.is_nil(of({ running = running, history = { PROMPT, message('found') } }).result)
    assert.is_nil(of({ history = { message('old'), PROMPT, STOP } }).result)
  end)

  it('reads the cost from the session usage', function()
    eq(
      0.25,
      of({
        usage = function()
          return { cost = 0.25 }
        end,
      }).cost
    )
    assert.is_nil(of({}).cost)
  end)

  it('reads the model from the session choice', function()
    eq('haiku', of({}).model)
    eq(
      'sonnet',
      of({
        choice = function()
          return { value = 'sonnet' }
        end,
      }).model
    )
    assert.is_nil(of({
      choice = function()
        return nil
      end,
    }).model)
  end)

  it('reads the agent name from the session', function()
    eq('claude', of({}).agent)
    assert.is_nil(of({ agent = {} }).agent)
  end)

  it('starts at the prompt time, and finishes at the stop time only once settled', function()
    local times = { [1] = 1000, [2] = 5000 }

    local settled = of({ history = { PROMPT, STOP }, times = times })
    local unsettled = of({ running = running, history = { PROMPT, message('x') }, times = times })

    eq(1000, settled.started)
    eq(5000, settled.finished)
    eq(1000, unsettled.started)
    assert.is_nil(unsettled.finished)
  end)

  it('counts tool calls per two second bucket over the last twelve seconds while live', function()
    local history = {
      tool_call('e', 'completed'),
      PROMPT,
      tool_call('a', 'completed'),
      tool_call('b', 'completed'),
      tool_call('c', 'completed'),
      message('working'),
      tool_call('d', 'completed'),
    }
    local times = { [1] = 6000, [2] = 7000, [3] = 9000, [4] = 17000, [5] = 19000, [6] = 19500, [7] = 19800 }

    eq({ 1, 0, 0, 0, 1, 2 }, of({ running = running, history = history, times = times }, 20000).activity)
  end)

  it('leaves the tool calls of subagents out of the activity', function()
    local child = tool_call('c', 'completed')

    child.parent = 'a'

    eq(
      { 0, 0, 0, 0, 0, 0 },
      of({ running = running, history = { PROMPT, child }, times = { 19000, 19500 } }, 20000).activity
    )
  end)

  it('has no activity once the session has settled or is idle', function()
    local times = { [1] = 1000, [2] = 2000 }

    assert.is_nil(of({ history = { PROMPT, STOP }, times = times }, 20000).activity)
    assert.is_nil(of({ history = { message('hi') }, times = times }, 20000).activity)
  end)

  it('reports no result or tool for a settled turn with no message and no open call', function()
    local settled = of({ history = { PROMPT, STOP } })

    assert.is_nil(settled.tool)
    assert.is_nil(settled.result)
  end)

  it('changes its digest when the state, tool, result, ask, cost or model change', function()
    local base = of({ running = running, history = { PROMPT } }).digest

    eq(base, of({ running = running, history = { PROMPT } }).digest)
    assert.are_not.equal(base, of({ history = { PROMPT, STOP } }).digest)
    assert.are_not.equal(base, of({ running = running, history = { PROMPT, tool_call('a', 'in_progress') } }).digest)
    assert.are_not.equal(
      of({ history = { PROMPT, message('one'), STOP } }).digest,
      of({ history = { PROMPT, STOP } }).digest
    )
    assert.are_not.equal(
      of({
        waiting = function()
          return { { title = 'A' } }
        end,
      }).digest,
      of({
        waiting = function()
          return { { title = 'B' } }
        end,
      }).digest
    )
    assert.are_not.equal(
      base,
      of({
        running = running,
        history = { PROMPT },
        usage = function()
          return { cost = 0.5 }
        end,
      }).digest
    )
    assert.are_not.equal(
      base,
      of({
        running = running,
        history = { PROMPT },
        choice = function()
          return { name = 'opus' }
        end,
      }).digest
    )
  end)

  it('gives a starting member its own key and state', function()
    local member = FleetMember.starting('h9')

    eq('h9', member.key)
    eq('starting', member.state)
  end)

  it('is live only while starting, working or waiting', function()
    eq(true, FleetMember.live(FleetMember.starting('h9')))
    eq(true, FleetMember.live(of({ running = running, history = { PROMPT } })))
    eq(
      true,
      FleetMember.live(of({
        waiting = function()
          return { { tool = 'Bash' } }
        end,
      }))
    )
    eq(false, FleetMember.live(of({ history = { PROMPT, STOP } })))
    eq(false, FleetMember.live(of({})))
    eq(false, FleetMember.live(of({ state = 'closed' })))
    eq(false, FleetMember.live(nil))
  end)
end)
