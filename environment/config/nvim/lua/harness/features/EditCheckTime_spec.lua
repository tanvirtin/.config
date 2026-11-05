local EditCheckTime = require('harness.features.EditCheckTime')
local events = require('harness.types.events')

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

  it('reloads on the store\'s tool updates while registered, and stops after cleanup', function()
    local buffers = require('core.buffers')
    local session_store = require('harness.session_store')
    local original = buffers.checktime
    local reloads = 0
    local update = events.new({ kind = events.KIND.tool_update, id = 't1', name = 'Edit', status = 'completed' })

    buffers.checktime = function()
      reloads = reloads + 1
    end

    local feature = EditCheckTime():register_events()

    session_store.dispatch(session_store.EVENT.event, {}, update)
    vim.wait(50, function()
      return reloads > 0
    end)
    eq(1, reloads)

    feature:cleanup()
    feature:cleanup()
    session_store.dispatch(session_store.EVENT.event, {}, update)
    vim.wait(50)
    eq(1, reloads)

    buffers.checktime = original
  end)
end)
