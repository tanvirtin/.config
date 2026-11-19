local EditLog = require('harness.edits.EditLog')

local eq = assert.are.same

describe('harness.edits.EditLog changes:', function()
  local files

  local function file_lines(path)
    return files[path]
  end

  local function edit(id, path, old, new, status)
    return {
      kind = 'tool_call',
      id = id,
      name = 'Edit',
      status = status or 'completed',
      diffs = { { path = path, old = old, new = new } },
    }
  end

  it('compares each file from before the session first edited it to now', function()
    files = { a = { 'a3' }, b = { 'b2' } }

    local history = {
      edit('1', 'a', 'a1', 'a2'),
      edit('2', 'b', 'b1', 'b2'),
      edit('3', 'a', 'a2', 'a3'),
    }

    files.a = { 'a2' }

    local edits = EditLog(file_lines)

    edits:get(history[1].diffs[1], '1:1', true)
    files.a = { 'a3' }

    eq({
      { filename = 'a', old_lines = { 'a1' }, new_lines = { 'a3' } },
      { filename = 'b', old_lines = { 'b1' }, new_lines = { 'b2' } },
    }, edits:changes(history))
  end)

  it('leaves out failed edits, files back where they started, and edits it could not place', function()
    files = { a = { 'a1' }, b = { 'b2' }, c = { 'c9' } }

    local history = {
      edit('1', 'a', 'a1', 'a2'),
      edit('2', 'b', 'b1', 'b2', 'failed'),
      edit('3', 'c', 'x', 'y'),
    }

    files.a = { 'a2' }

    local edits = EditLog(file_lines)

    edits:get(history[1].diffs[1], '1:1', true)
    files.a = { 'a1' }

    eq({}, edits:changes(history))
  end)
end)
