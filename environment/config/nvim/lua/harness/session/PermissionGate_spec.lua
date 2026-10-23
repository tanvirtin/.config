local PermissionGate = require('harness.session.PermissionGate')
local async = require('harness.async')
local events = require('harness.types.events')
local fake = require('harness.session.fake_session')
local permission = require('harness.types.permission')

local eq = assert.are.same

local PARAMS = permission.Request({
  tool = 'Edit',
  id = 't1',
  title = 'Edit a.lua',
  choices = { { kind = 'allow_once', label = 'Yes' }, { kind = 'reject_once', label = 'No' } },
})

describe('harness.session.PermissionGate:', function()
  it('asks approve and answers with the chosen option, recording the decision', function()
    local session = fake.session({
      approve = function()
        return 'allow_once'
      end,
    })
    local gate = PermissionGate(session)
    local answer = gate:request(PARAMS)

    eq('allow_once', answer.result)
    eq({ kind = events.KIND.permission, tool = 'Edit', allowed = true, id = 't1' }, session.emitted[1])
    eq({}, gate:waiting())
  end)

  it('lists what it is waiting on until the answer comes', function()
    local later = async.Future.new()
    local session = fake.session({
      approve = function()
        return later
      end,
    })
    local gate = PermissionGate(session)
    local answer = gate:request(PARAMS)

    eq({ { tool = 'Edit', id = 't1', title = 'Edit a.lua' } }, gate:waiting())

    later:set_result('reject_once')
    async.drain()

    eq('reject_once', answer.result)
    eq({}, gate:waiting())
    eq({ events.NOTICE.waiting, events.NOTICE.waiting }, session.notified)
  end)

  it('answers everything open with cancelled, dismissing each prompt', function()
    local dismissed = 0
    local session = fake.session({
      approve = function()
        local later = async.Future.new()
        later.dismiss = function()
          dismissed = dismissed + 1
        end
        return later
      end,
    })
    local gate = PermissionGate(session)
    local first, second = gate:request(PARAMS), gate:request(PARAMS)

    gate:cancel_all()

    eq('cancelled', first.result)
    eq('cancelled', second.result)
    eq(2, dismissed)
    eq({}, gate:waiting())
  end)

  it('rejects when approve fails', function()
    local session = fake.session({
      approve = function()
        error('boom')
      end,
    })

    eq('reject_once', PermissionGate(session):request(PARAMS).result)
  end)
end)
