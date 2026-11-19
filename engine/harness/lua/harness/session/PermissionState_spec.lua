local PermissionState = require('harness.session.PermissionState')

local eq = assert.are.same

describe('harness.session.PermissionState:', function()
  it('grants, lists by tool, and revokes', function()
    local state = PermissionState()

    state:grant('mcp__nvim__lua'):grant('mcp__nvim__ex')

    assert.is_true(state:granted('mcp__nvim__lua'))
    eq(
      { 'mcp__nvim__ex', 'mcp__nvim__lua' },
      vim.tbl_map(function(grant)
        return grant.tool
      end, state:grants())
    )
    assert.is_true(state:revoke('mcp__nvim__ex'))
    assert.is_false(state:revoke('mcp__nvim__ex'))
    assert.is_false(state:granted('mcp__nvim__ex'))
  end)

  it('keeps the newest decisions in order, up to its cap', function()
    local state = PermissionState()
    local cap = PermissionState.MAX_DECISIONS

    for i = 1, cap + 2 do
      state:record({ tool = 't' .. i, kind = 'allow_once' })
    end

    local decisions = state:decisions()

    eq(cap, #decisions)
    eq({ 't3', 't' .. (cap + 2) }, { decisions[1].tool, decisions[#decisions].tool })
    assert.is_number(decisions[1].time)
  end)

  it('hands out a copy of its decisions', function()
    local state = PermissionState()

    state:record({ tool = 'Bash', kind = 'reject_once' })
    table.remove(state:decisions())

    eq(1, #state:decisions())
  end)
end)
