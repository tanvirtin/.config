local vgit = require('harness.vgit')

local eq = assert.are.same

describe('harness.vgit:', function()
  local function file()
    return {
      filename = 'demo.lua',
      old_lines = { 'local a = 1', 'local b = 2', 'local c = 3' },
      new_lines = { 'local a = 1', 'local B = 22', 'local c = 3' },
    }
  end

  it('reads the layout off the vgit diff preference', function()
    eq('unified', vgit.preference())
  end)

  it('lays a split patch out in two aligned, numbered columns', function()
    local patch = vgit.patch(file(), { layout = 'split', context = 1 })

    eq('split', patch.layout)
    eq(3, #patch.lines)
    eq(3, #patch.rows)
    eq({ added = 1, removed = 1 }, patch.stat)

    for _, line in ipairs(patch.lines) do
      assert.truthy(line:find(' │ ', 1, true))
    end

    assert.truthy(patch.lines[2]:find('local b = 2', 1, true))
    assert.truthy(patch.lines[2]:find('local B = 22', 1, true))
    eq({ 2, 2 }, { patch.rows[2].old_lnum, patch.rows[2].new_lnum })
    eq({ 2, 21 }, { patch.rows[2].old_code, patch.rows[2].new_code })

    for _, line in ipairs(patch.lines) do
      eq(#patch.lines[1], #line)
    end
  end)

  it('gives each changed side its own line background and number colour', function()
    local patch = vgit.patch(file(), { layout = 'split', context = 1 })
    local seen = {}

    for _, hl in ipairs(patch.highlights) do
      seen[hl.hl_group] = true
    end

    eq({ true, true, true, true }, {
      seen.GitSignsDeleteLn == true,
      seen.GitSignsAddLn == true,
      seen.GitSignsDelete == true,
      seen.GitSignsAdd == true,
    })
  end)

  it('falls back to unified when a split would not fit the window', function()
    local wide = {
      filename = 'demo.lua',
      old_lines = { 'local a = 1', 'local b = 2', 'local c = 3' },
      new_lines = { 'local a = 1', 'local b = "a replacement line that is far too long to fit"', 'local c = 3' },
    }
    local patch = vgit.patch(wide, { layout = 'split', context = 1, width = 60, overflow = 'unified' })

    eq(nil, patch.layout)
    assert.truthy(patch.rows[1])
  end)

  it('truncates a hunk too wide for the window, so every diff stays split', function()
    local old, new = {}, {}

    for i = 1, 5 do
      old[i], new[i] = 'line ' .. i, 'line ' .. i
    end

    new[3] = 'line three = "a replacement line that is far too long to fit in half the window"'

    local patch = vgit.patch({ filename = 'demo.lua', old_lines = old, new_lines = new }, {
      layout = 'split',
      context = 1,
      width = 100,
    })

    eq('split', patch.layout)

    for _, line in ipairs(patch.lines) do
      assert.is_true(vim.fn.strchars(line) <= 100)
    end

    assert.truthy(table.concat(patch.lines, '\n'):find('…', 1, true))
  end)

  it('lays a hunk too wide for the window out unified, keeping the hunks that fit split', function()
    local old, new = {}, {}

    for i = 1, 20 do
      old[i], new[i] = 'line ' .. i, 'line ' .. i
    end

    new[2] = 'line two'
    new[18] = 'line 18 = "a replacement line that is far too long to fit beside its old side"'

    local patch = vgit.patch({ filename = 'demo.lua', old_lines = old, new_lines = new }, {
      layout = 'split',
      context = 1,
      width = 100,
      overflow = 'unified',
    })
    local hunk

    for i, row in ipairs(patch.rows) do
      if row.kind == 'hunk' then hunk = i end
    end

    eq('split', patch.layout)
    assert.truthy(patch.lines[2]:find(' │ ', 1, true))

    local tail = vim.list_slice(patch.lines, hunk + 1)

    eq(4, #tail)
    eq(nil, table.concat(tail, '\n'):find(' │ ', 1, true))
    eq(
      { 'context', 'remove', 'add', 'context' },
      vim.tbl_map(function(row)
        return row.kind
      end, vim.list_slice(patch.rows, hunk + 1))
    )
    eq({ 18, nil, 3 }, { patch.rows[hunk + 2].old_lnum, patch.rows[hunk + 2].new_lnum, patch.rows[hunk + 2].old_code })
    eq({ nil, 18, 3 }, { patch.rows[hunk + 3].old_lnum, patch.rows[hunk + 3].new_lnum, patch.rows[hunk + 3].new_code })
    eq('18 line 18', patch.lines[hunk + 2])
  end)

  it('marks the changed words on both sides of a split row', function()
    local patch = vgit.patch(file(), { layout = 'split', context = 1 })
    local cols = {}

    for _, word in ipairs(patch.words) do
      eq(1, word.row)
      cols[#cols + 1] = word.col
    end

    eq(2, #cols)
    assert.is_true(cols[2] > patch.rows[2].new_code)
    eq('b', patch.lines[2]:sub(cols[1] + 1, cols[1] + 1))
  end)

  it('leaves the numbers blank when asked to, keeping the columns aligned', function()
    local patch = vgit.patch(file(), { layout = 'split', context = 1, numbers = false })

    eq('  local a = 1', patch.lines[1]:sub(1, 13))
    eq({ 2, 2 }, { patch.rows[2].old_lnum, patch.rows[2].old_code })
  end)

  it('keeps split when both sides fit the window', function()
    local patch = vgit.patch(file(), { layout = 'split', context = 1, width = 200 })

    eq('split', patch.layout)
  end)

  it('gives every split the same width, so the divider lines up', function()
    local one = vgit.patch(file(), { layout = 'split', context = 1, width = 200 })
    local two = vgit.patch({
      filename = 'demo.lua',
      old_lines = { 'local a = 1' },
      new_lines = { 'local a = 2' },
    }, { layout = 'split', context = 1, width = 200 })

    eq('split', one.layout)
    eq('split', two.layout)
    eq(vim.fn.strdisplaywidth(one.lines[1]), vim.fn.strdisplaywidth(two.lines[1]))
  end)

  it('hatches the empty side of a split row with the void symbol', function()
    local patch = vgit.patch({
      filename = 'demo.lua',
      old_lines = { 'local a = 1' },
      new_lines = { 'local a = 1', 'local b = 2' },
    }, { layout = 'split', context = 0 })

    assert.truthy(patch.voids[1])
    assert.truthy(patch.voids[1].text:find('⣿', 1, true))
    eq(0, patch.voids[1].col)
  end)

  it('keeps unified the default, without a layout marker', function()
    local patch = vgit.patch(file(), { context = 1 })

    eq(nil, patch.layout)
    assert.truthy(patch.rows[1])
  end)
end)
