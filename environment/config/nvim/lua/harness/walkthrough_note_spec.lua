local walkthrough_note = require('harness.walkthrough_note')

local eq = assert.are.same

local function texts(virt)
  return vim.tbl_map(function(line)
    return table.concat(vim.tbl_map(function(chunk)
      return chunk[1]
    end, line))
  end, virt)
end

local function trimmed(virt)
  return vim.tbl_map(function(line)
    return (line:gsub('%s+$', ''))
  end, texts(virt))
end

describe('harness.walkthrough_note:', function()
  it('frames the note with its title and footer, every row as wide as the note', function()
    local virt = walkthrough_note.render(
      { 'Reads the diff.' },
      { width = 30, title = '1/3 · Scope', footer = ']] next' }
    )

    eq(
      { '╭─ 1/3 · Scope ───────────────', '│ Reads the diff.', '╰─ ]] next' },
      trimmed(virt)
    )
    eq(30, vim.fn.strdisplaywidth(texts(virt)[2]))
  end)

  it('wraps long text to the width, words whole', function()
    local virt = walkthrough_note.render({ 'one two three four five six' }, { width = 14 })

    eq({ '│ one two', '│ three four', '│ five six' }, vim.list_slice(trimmed(virt), 2, 4))
  end)

  it('colours inline code and bold, without their markers', function()
    local row = walkthrough_note.render({ 'Calls `git diff` **once**.' }, { width = 40 })[2]
    local parts = vim.tbl_map(function(chunk)
      return { chunk[1], chunk[2] }
    end, row)

    local function find(word)
      for _, part in ipairs(parts) do
        if part[1] == word then return part[2] end
      end
    end

    eq(walkthrough_note.HL.code, find('git diff'))
    eq(walkthrough_note.HL.strong, find('once'))
    eq('│ Calls git diff once.', trimmed({ row })[1])
  end)

  it('wraps punctuation and the code it touches together', function()
    local virt = walkthrough_note.render({ 'Each hunk gets an id (`h1`, `h2`).' }, { width = 26 })

    eq({ '│ Each hunk gets an id', '│ (h1, h2).' }, vim.list_slice(trimmed(virt), 2, 3))
  end)

  it('keeps a fenced block as written, draws rules, bullets and headings', function()
    local virt = walkthrough_note.render({ '## Flow', '- first', '---', '```', 'a ──▶ b', '```' }, { width = 30 })

    eq({
      '│ Flow',
      '│ • first',
      '│ ────────────────────────────',
      '│ a ──▶ b',
    }, vim.list_slice(trimmed(virt), 2, 5))
    eq(walkthrough_note.HL.code, virt[5][2][2])
  end)
end)
