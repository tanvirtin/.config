local Revert = require('harness.transcript.Revert')

local eq = assert.are.same

local function files(map)
  return function(path)
    return map[path]
  end
end

local function edit(id, ...)
  return { id = id, diffs = { ... } }
end

describe('harness.transcript.Revert:', function()
  it('undoes one edit in the file as it is now', function()
    local plan =
      Revert.plan({ edit('1', { path = 'a', old = 'x = 1', new = 'x = 2' }) }, files({ a = { 'x = 2', 'y' } }))

    eq({ { filename = 'a', old_lines = { 'x = 2', 'y' }, new_lines = { 'x = 1', 'y' } } }, plan.files)
    eq({ 1, {} }, { plan.undone, plan.skipped })
  end)

  it('undoes a turn\'s edits to one file newest first, so each finds what the next left', function()
    local plan = Revert.plan({
      edit('1', { path = 'a', old = 'x = 1', new = 'x = 2' }),
      edit('2', { path = 'a', old = 'x = 2', new = 'x = 3' }),
    }, files({ a = { 'x = 3' } }))

    eq({ 'x = 1' }, plan.files[1].new_lines)
    eq(2, plan.undone)
  end)

  it('keeps changes made after the edit, by you or the agent', function()
    local plan = Revert.plan(
      { edit('1', { path = 'a', old = 'x = 1', new = 'x = 2' }) },
      files({ a = { 'x = 2', 'added by hand' } })
    )

    eq({ 'x = 1', 'added by hand' }, plan.files[1].new_lines)
  end)

  it('skips an edit whose text has changed since, and says why', function()
    local plan = Revert.plan({
      edit('1', { path = 'a', old = 'x = 1', new = 'x = 2' }),
      edit('2', { path = 'b', old = 'y', new = 'z' }),
    }, files({ a = { 'x = 9' }, b = { 'z' } }))

    eq(
      { 'b' },
      vim.tbl_map(function(file)
        return file.filename
      end, plan.files)
    )
    eq({ { path = 'a', id = '1', reason = Revert.REASON.changed } }, plan.skipped)
  end)

  it('empties a file the agent created', function()
    local plan =
      Revert.plan({ edit('1', { path = 'n', old = '', new = 'one\ntwo\n' }) }, files({ n = { 'one', 'two' } }))

    eq({}, plan.files[1].new_lines)
  end)
end)
