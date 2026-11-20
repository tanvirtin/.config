local Edit = require('harness.edits.Edit')
local EditLog = require('harness.edits.EditLog')

local eq = assert.are.same

local function files(map)
  return function(path)
    return map[path]
  end
end

local function edit(id, ...)
  return { id = id, diffs = { ... } }
end

describe('harness.edits.EditLog revert_plan:', function()
  it('undoes one edit in the file as it is now', function()
    local plan =
      EditLog(files({ a = { 'x = 2', 'y' } })):revert_plan({ edit('1', { path = 'a', old = 'x = 1', new = 'x = 2' }) })

    eq({ { filename = 'a', old_lines = { 'x = 2', 'y' }, new_lines = { 'x = 1', 'y' } } }, plan.files)
    eq({ 1, {} }, { plan.undone, plan.skipped })
  end)

  it('undoes a turn\'s edits to one file newest first, so each finds what the next left', function()
    local plan = EditLog(files({ a = { 'x = 3' } })):revert_plan({
      edit('1', { path = 'a', old = 'x = 1', new = 'x = 2' }),
      edit('2', { path = 'a', old = 'x = 2', new = 'x = 3' }),
    })

    eq({ 'x = 1' }, plan.files[1].new_lines)
    eq(2, plan.undone)
  end)

  it('keeps changes made after the edit, by you or the agent', function()
    local plan = EditLog(files({ a = { 'x = 2', 'added by hand' } })):revert_plan({
      edit('1', { path = 'a', old = 'x = 1', new = 'x = 2' }),
    })

    eq({ 'x = 1', 'added by hand' }, plan.files[1].new_lines)
  end)

  it('skips an edit whose text has changed since, and says why', function()
    local plan = EditLog(files({ a = { 'x = 9' }, b = { 'z' } })):revert_plan({
      edit('1', { path = 'a', old = 'x = 1', new = 'x = 2' }),
      edit('2', { path = 'b', old = 'y', new = 'z' }),
    })

    eq(
      { 'b' },
      vim.tbl_map(function(file)
        return file.filename
      end, plan.files)
    )
    eq({ { path = 'a', id = '1', reason = Edit.REASON.changed } }, plan.skipped)
  end)

  it('undoes one edit in each of two files from two tools, with nothing skipped', function()
    local plan = EditLog(files({
      a = { 'if x then', '\tlocal y = 2' },
      b = { 'z = 2' },
    })):revert_plan({
      { id = 't1', diffs = { { path = 'a', old = 'if x then\n  local y = 1', new = 'if x then\n\tlocal y = 2' } } },
      { id = 't2', diffs = { { path = 'b', old = 'z = 1', new = 'z = 2' } } },
    })

    eq({ undone = 2, skipped = {} }, { undone = plan.undone, skipped = plan.skipped })
    local by_name = {}

    for _, file in ipairs(plan.files) do
      by_name[file.filename] = file.new_lines
    end

    eq({ a = { 'if x then', '  local y = 1' }, b = { 'z = 1' } }, by_name)
  end)

  it('empties a file the agent created', function()
    local plan =
      EditLog(files({ n = { 'one', 'two' } })):revert_plan({ edit('1', { path = 'n', old = '', new = 'one\ntwo\n' }) })

    eq({}, plan.files[1].new_lines)
  end)
end)
