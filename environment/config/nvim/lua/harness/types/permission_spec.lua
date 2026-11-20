local permission = require('harness.types.permission')

local eq = assert.are.same

describe('harness.types.permission:', function()
  it('names the decisions, and says which allow', function()
    local D = permission.DECISION

    eq({ true, true, false, false, false }, {
      permission.allows(D.allow_once),
      permission.allows(D.allow_always),
      permission.allows(D.reject_once),
      permission.allows(D.reject_always),
      permission.allows(D.cancelled),
    })
    eq(false, permission.allows(nil))
  end)
end)
