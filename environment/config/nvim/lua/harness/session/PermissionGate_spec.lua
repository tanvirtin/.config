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

    eq('allow_once', answer.result.kind)
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

    eq({ { kind = 'permission', tool = 'Edit', id = 't1', title = 'Edit a.lua' } }, gate:waiting())

    later:set_result('reject_once')
    async.drain()

    eq('reject_once', answer.result.kind)
    eq({}, gate:waiting())
    eq({ events.NOTICE.waiting, events.NOTICE.waiting, events.NOTICE.permissions }, session.notified)
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

    eq('cancelled', first.result.kind)
    eq('cancelled', second.result.kind)
    eq(2, dismissed)
    eq({}, gate:waiting())
  end)

  it('logs each decision with the label of the option picked, and cancellations', function()
    local later = async.Future.new()
    local plan = permission.Request({
      tool = 'ExitPlanMode',
      title = 'Ready to code?',
      choices = {
        permission.Choice({ kind = 'allow_always', label = 'Yes, and use auto mode', option = 'auto' }),
        permission.Choice({ kind = 'allow_always', label = 'Yes, and bypass permissions', option = 'bypass' }),
      },
    })
    local answers = { permission.Decision({ kind = 'allow_always', option = 'bypass' }), later }
    local session = fake.session({
      approve = function()
        return table.remove(answers, 1)
      end,
    })
    local gate = PermissionGate(session)

    gate:request(plan)
    gate:request(PARAMS)
    gate:cancel_all()

    eq(
      {
        { 'ExitPlanMode', 'allow_always', 'Yes, and bypass permissions' },
        { 'Edit', 'cancelled', nil },
      },
      vim.tbl_map(function(entry)
        return { entry.tool, entry.kind, entry.label }
      end, gate:decisions())
    )
  end)

  it('hands the policy its grants, and revokes one, saying so', function()
    local seen
    local session = fake.session({
      approve = function(request)
        seen = request.grants
        request.grants:grant('mcp__nvim__lua')
        return 'allow_once'
      end,
    })
    local gate = PermissionGate(session)

    gate:request(PARAMS)

    eq(gate.state, seen)
    eq(
      { 'mcp__nvim__lua' },
      vim.tbl_map(function(grant)
        return grant.tool
      end, gate:grants())
    )

    session.notified = {}
    assert.is_true(gate:revoke('mcp__nvim__lua'))
    assert.is_false(gate:revoke('mcp__nvim__lua'))
    eq({}, gate:grants())
    eq({ events.NOTICE.permissions }, session.notified)
  end)

  it('rejects when approve fails', function()
    local session = fake.session({
      approve = function()
        error('boom')
      end,
    })

    eq('reject_once', PermissionGate(session):request(PARAMS).result.kind)
  end)
end)
