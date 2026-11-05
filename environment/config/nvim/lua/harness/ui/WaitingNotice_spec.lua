local WaitingNotice = require('harness.ui.WaitingNotice')
local Toast = require('harness.ui.Toast')

local eq = assert.are.same

local function session(waiting)
  return {
    key = 'h7',
    waiting = function()
      return waiting
    end,
  }
end

describe('harness.ui.WaitingNotice:', function()
  local shown
  local original

  before_each(function()
    shown = {}
    original = Toast.show
    Toast.show = function(message)
      shown[#shown + 1] = message
    end
  end)

  after_each(function()
    Toast.show = original
  end)

  it('says nothing when nothing is waiting', function()
    WaitingNotice(session({}), -1):announce()

    eq({}, shown)
  end)

  it('names the session and the tool when a permission waits out of sight', function()
    WaitingNotice(session({ { title = 'Edit a.lua', kind = 'permission' } }), -1):announce()

    eq(1, #shown)
    assert.truthy(shown[1]:find('h7', 1, true))
    assert.truthy(shown[1]:find('waiting for permission', 1, true))
    assert.truthy(shown[1]:find('Edit a.lua', 1, true))
  end)

  it('asks for the answer when it is a question, and stays quiet when the transcript is in sight', function()
    WaitingNotice(session({ { title = 'Which database?', kind = 'elicitation' } }), -1):announce()
    assert.truthy(shown[1]:find('waiting for your answer', 1, true))

    local bufnr = vim.api.nvim_get_current_buf()

    WaitingNotice(session({ { title = 'x', kind = 'permission' } }), bufnr):announce()
    eq(1, #shown)
  end)
end)
