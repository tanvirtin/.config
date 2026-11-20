local StaleRunNotice = require('harness.features.StaleRunNotice')
local events = require('harness.types.events')

local eq = assert.are.same

describe('harness.features.StaleRunNotice:', function()
  local idle = {
    idle = function()
      return true
    end,
  }
  local busy = {
    idle = function()
      return false
    end,
  }

  it('applies to the stop of a turn that ended well, in a session that is idle again', function()
    eq(true, StaleRunNotice.applies(idle, events.stop('end_turn')))
    eq(false, StaleRunNotice.applies(idle, events.stop('error')))
    eq(false, StaleRunNotice.applies(busy, events.stop('end_turn')))
    eq(false, StaleRunNotice.applies(idle, events.error('boom')))
  end)

  it('names the command and the files that were unsaved', function()
    local one = StaleRunNotice.message({ command = 'cargo test\nmore', paths = { '/w/a.rs' } })
    local two = StaleRunNotice.message({ command = 'make', paths = { '/w/a.rs', '/w/b.rs' } })

    assert.truthy(one:find('`cargo test` ran while a.rs was unsaved', 1, true))
    assert.truthy(two:find('a.rs, b.rs were unsaved', 1, true))
  end)
end)
