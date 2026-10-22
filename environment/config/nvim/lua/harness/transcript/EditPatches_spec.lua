local EditPatches = require('harness.transcript.EditPatches')

local eq = assert.are.same

describe('harness.transcript.EditPatches:', function()
  local diff = { path = '/a.lua', old = 'x = 1', new = 'x = 2' }

  it('resolves an edit against the file and lays it out with vgit, once per file state', function()
    local file, reads = { 'x = 1' }, 0
    local edits = EditPatches(function()
      reads = reads + 1
      return file
    end)

    local pending = edits:get(diff, 't:1', false)

    eq('pending', pending.resolved.kind)
    eq({ 'x = 1', 'x = 2' }, pending:patch().lines)
    eq(pending, edits:get(diff, 't:1', false))

    file = { 'x = 2' }

    local applied = edits:get(diff, 't:1', true)

    eq('applied', applied.resolved.kind)
    eq({ '@@ -1 +1 @@', '-x = 1', '+x = 2' }, applied:text())
    eq(3, reads)
  end)

  it('keeps a finished edit as it was, whatever happens to the file later', function()
    local file = { 'x = 2' }
    local edits = EditPatches(function()
      return file
    end)
    local first = edits:get(diff, 't:1', true)

    file = { 'something else' }

    eq(first, edits:get(diff, 't:1', true))
  end)

  it('highlights syntax on demand exactly as vgit would, mapped onto the patch rows', function()
    local file = { 'local a = 0', 'local x = 2', 'return x' }
    local edit = EditPatches(function()
      return file
    end):get({ path = '/a.lua', old = 'local x = 1', new = 'local x = 2' }, 't:1', true)
    local expected = {}

    for _, hl in ipairs(require('vgit.api').patch({ edit.file }, { header = false, context = 3 }).highlights) do
      if hl.syntax then
        expected[#expected + 1] =
          { row = hl.row, col_start = hl.col_start, col_end = hl.col_end, hl_group = hl.hl_group }
      end
    end

    assert.is_nil(edit:patch().highlights[1] and edit:patch().highlights[1].syntax)
    assert.is_true(#expected > 0)
    eq(expected, edit:syntax())
    eq(edit:syntax(), edit:syntax())
  end)

  it('keeps one set per owner, so every reader of a session sees the same frozen edits', function()
    local session = {}

    eq(EditPatches.of(session), EditPatches.of(session))
    assert.are_not.equal(EditPatches.of(session), EditPatches.of({}))
  end)

  it('finds the file line under a patch row, only when the edit was found in the file', function()
    local block = {
      start = 10,
      whole = true,
      patch = { rows = { { kind = 'remove', old_lnum = 4 }, { kind = 'add', new_lnum = 4 }, { kind = 'hunk' } } },
    }

    eq({ 4, 4 }, { EditPatches.line_at(block, 12), EditPatches.line_at(block, 13) })
    assert.is_nil(EditPatches.line_at(block, 14))

    block.whole = false
    assert.is_nil(EditPatches.line_at(block, 13))
  end)
end)
