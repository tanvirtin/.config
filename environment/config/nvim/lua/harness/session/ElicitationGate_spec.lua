local async = require('harness.async')
local events = require('harness.types.events')
local fake = require('harness.session.fake_session')
local elicitation = require('harness.types.elicitation')
local ElicitationGate = require('harness.session.ElicitationGate')

local eq = assert.are.same

local FORM = elicitation.Request({
  mode = 'form',
  message = 'Which database?',
  tool = 't1',
  fields = {
    elicitation.Field({
      key = 'db',
      kind = 'choice',
      title = 'Database',
      other = 'db_custom',
      options = { elicitation.Option({ value = 'pg', label = 'Postgres' }) },
    }),
    elicitation.Field({ key = 'db_custom', kind = 'text' }),
  },
})

local URL = elicitation.Request({ mode = 'url', message = 'Sign in', url = 'https://x', id = 'e1' })

local function gate_with(elicit)
  local session = fake.session()

  session.elicit = elicit

  return ElicitationGate(session), session
end

describe('harness.session.ElicitationGate:', function()
  it('asks the session\'s elicit and answers with it, recording what was answered', function()
    local asked
    local gate, session = gate_with(function(ask)
      asked = ask
      return elicitation.accept({ db = 'pg', db_custom = 'v16' })
    end)
    local answer = gate:request(FORM)

    eq(FORM, asked.request)
    eq(session, asked.session)
    eq('accept', answer.result.action)

    local event = session.emitted[1]

    eq(events.KIND.elicitation, event.kind)
    eq({ 'Which database?', 'accept', 't1' }, { event.message, event.action, event.tool })
    eq({ { label = 'Database', value = 'Postgres; v16' } }, event.answers)
    eq({}, gate:waiting())
  end)

  it('declines when nobody can answer, or when answering fails', function()
    eq('decline', gate_with(nil):request(FORM).result.action)
    eq(
      'decline',
      gate_with(function()
        error('boom')
      end):request(FORM).result.action
    )
  end)

  it('lists the question while it waits, and settles when the answer comes', function()
    local later = async.Future.new()
    local gate, session = gate_with(function()
      return later
    end)
    local answer = gate:request(FORM)

    eq({ { kind = 'elicitation', id = 't1', title = 'Which database?' } }, gate:waiting())

    later:set_result(elicitation.decline())
    async.drain()

    eq('decline', answer.result.action)
    eq({}, gate:waiting())
    eq({ events.NOTICE.waiting, events.NOTICE.waiting }, session.notified)
  end)

  it('cancels everything open, dismissing each prompt once', function()
    local dismissed = 0
    local gate = gate_with(function()
      local later = async.Future.new()

      later.dismiss = function()
        dismissed = dismissed + 1
        later:set_result(elicitation.cancel())
      end

      return later
    end)
    local first, second = gate:request(FORM), gate:request(URL)

    gate:cancel_all()

    eq({ 'cancel', 'cancel' }, { first.result.action, second.result.action })
    eq(2, dismissed)
    eq({}, gate:waiting())
  end)

  it('cancels one question when the agent withdraws it', function()
    local later = async.Future.new()
    local gate = gate_with(function()
      return later
    end)
    local answer = gate:request(FORM)

    answer.cancel()

    eq('cancel', answer.result.action)
    eq({}, gate:waiting())
  end)

  it('closes an open url question the agent finished on its own', function()
    local later = async.Future.new()
    local dismissed = false
    local gate, session = gate_with(function()
      later.dismiss = function()
        dismissed = true
      end
      return later
    end)
    local answer = gate:request(URL)

    gate:complete('e1')

    eq('accept', answer.result.action)
    assert.is_true(dismissed)
    assert.is_true(session.emitted[1].completed)
  end)

  it('notes when a url question the user accepted is finished, once', function()
    local gate, session = gate_with(function()
      return elicitation.accept()
    end)

    gate:request(URL)
    gate:complete('e1')
    gate:complete('e1')
    gate:complete('unknown')

    eq(2, #session.emitted)
    eq({ nil, true }, { session.emitted[1].completed, session.emitted[2].completed })
  end)
end)
