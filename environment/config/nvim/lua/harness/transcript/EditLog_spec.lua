local EditLog = require('harness.transcript.EditLog')

local eq = assert.are.same

describe('harness.transcript.EditLog:', function()
  local diff = { path = 'a', old = 'x', new = 'y' }
  local history = {
    { kind = 'prompt', text = 'go' },
    { kind = 'tool_call', id = '1', name = 'Edit', diffs = { diff } },
    { kind = 'tool_update', id = '1', status = 'completed', diffs = {} },
    { kind = 'tool_call', id = '2', name = 'Edit', status = 'failed', diffs = { diff } },
    { kind = 'tool_call', id = '3', name = 'Read', status = 'completed', diffs = {} },
    { kind = 'prompt', text = 'again' },
    { kind = 'tool_call', id = '4', name = 'Write', status = 'completed', diffs = { diff } },
  }

  it('lists the edits that completed, in order, with where they started', function()
    eq({ { id = '1', index = 2, diffs = { diff } }, { id = '4', index = 7, diffs = { diff } } }, EditLog.edits(history))
  end)

  it('keeps only the edits that started within a range of the history', function()
    eq(
      { '4' },
      vim.tbl_map(function(edit)
        return edit.id
      end, EditLog.edits(history, 6, 7))
    )
  end)
end)
