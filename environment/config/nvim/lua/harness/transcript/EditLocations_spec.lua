local EditLocations = require('harness.transcript.EditLocations')
local EditPatches = require('harness.transcript.EditPatches')

local eq = assert.are.same

describe('harness.transcript.EditLocations:', function()
  local function lines(n, changed)
    local out = {}

    for i = 1, n do
      out[i] = changed and changed[i] or ('line ' .. i)
    end

    return out
  end

  it('gives one location per changed hunk, at its line, with its counts and the turn\'s prompt', function()
    local file = lines(30, { [5] = 'five', [25] = 'twenty five' })
    local patches = EditPatches(function()
      return file
    end)
    local history = {
      { kind = 'prompt', text = '<editor-context>x</editor-context>\nrename the lines\nplease' },
      { kind = 'tool_call', id = 'e1', diffs = {} },
    }
    local edits = {
      {
        id = 'e1',
        index = 2,
        diffs = {
          { path = '/a.txt', old = 'line 5', new = 'five' },
          { path = '/a.txt', old = 'line 25', new = 'twenty five' },
        },
      },
    }

    eq({
      { path = '/a.txt', line = 5, text = '+1 −1  · rename the lines' },
      { path = '/a.txt', line = 25, text = '+1 −1  · rename the lines' },
    }, EditLocations.items(history, edits, patches))
  end)

  it('points at the top of a file when the edit could not be placed in it', function()
    local patches = EditPatches(function()
      return { 'unrelated' }
    end)
    local items = EditLocations.items(
      {},
      { { id = 'e1', index = 1, diffs = { { path = '/b', old = 'x', new = 'y' } } } },
      patches
    )

    eq({ { path = '/b', line = 1, text = '+1 −1' } }, items)
  end)
end)
