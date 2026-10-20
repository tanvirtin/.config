local EditCheckTime = require('harness.features.EditCheckTime')
local events = require('harness.events')

local eq = assert.are.same

describe('harness.features.EditCheckTime:', function()
  it('reloads buffers after a completed tool the editor does not own, such as Claude\'s Edit', function()
    local function update(name, status)
      return events.new({ kind = events.KIND.tool_update, id = 't1', name = name, status = status })
    end

    eq(true, EditCheckTime.applies(update('Edit', 'completed')))
    eq(false, EditCheckTime.applies(update('Edit', 'in_progress')))
    eq(false, EditCheckTime.applies(update('mcp__nvim__buffer_edit', 'completed')))
    eq(false, EditCheckTime.applies(events.new({ kind = events.KIND.message, text = 'hi' })))
  end)

  it('registers once and cleans up', function()
    local feature = EditCheckTime():register_events()

    feature:cleanup()
    feature:cleanup()
  end)
end)
