local Renderer = require('ui.markdown.Renderer')

local eq = assert.are.same

describe('ui.markdown.Renderer:', function()
  local buf

  local function render(lines, from, to)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    Renderer(buf):render(from or 0, to)
  end

  local function marks(row)
    local out = {}

    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, Renderer.NAMESPACE, 0, -1, { details = true })) do
      if row == nil or mark[2] == row then out[#out + 1] = mark[4] end
    end

    return out
  end

  local function virt_text(row)
    local out = {}

    for _, mark in ipairs(marks(row)) do
      if mark.virt_text then out[#out + 1] = mark.virt_text[1][1] end
    end

    return out
  end

  local function find(row, key)
    for _, mark in ipairs(marks(row)) do
      if mark[key] then return mark end
    end
  end

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('hides a heading\'s markers and colours it by level, with no icon or bar', function()
    render({ '## Plan' })

    eq({}, virt_text(0))
    assert.is_nil(find(0, 'line_hl_group'))
    assert.is_truthy(vim.tbl_contains(
      vim.tbl_map(function(mark)
        return mark.hl_group
      end, marks(0)),
      'UiMarkdownHeading2'
    ))
    eq(3, find(0, 'conceal').end_col)
  end)

  it('shades a code block and labels its language', function()
    render({ 'before', '```lua', 'local x = 1', 'return x', '```', 'after' })

    local shaded = {}

    for row = 0, 5 do
      shaded[#shaded + 1] = find(row, 'line_hl_group') ~= nil
    end

    eq({ false, true, true, true, true, false }, shaded)
    eq({ 'lua ' }, virt_text(2))
  end)

  it('draws bullets by depth and checkboxes as icons', function()
    render({ '- top', '  - nested', '- [x] done', '- [ ] todo' })

    eq({ Renderer.BULLETS[1] }, virt_text(0))
    eq({ Renderer.BULLETS[2] }, virt_text(1))
    eq({ '✓' }, virt_text(2))
    eq({ '○' }, virt_text(3))
    eq(2, find(2, 'conceal').end_col)
  end)

  it('draws quote bars, and callouts with their icon and colour', function()
    render({ '> plain', '', '> [!THOUGHT]', '> thinking' })

    eq({ '▎' }, virt_text(0))
    eq('UiMarkdownQuote', find(0, 'virt_text').virt_text[1][2])
    assert.is_truthy(vim.tbl_contains(virt_text(2), Renderer.CALLOUTS.thought.icon .. 'Thought'))

    for _, mark in ipairs(marks(3)) do
      if mark.virt_text then eq(Renderer.CALLOUTS.thought.hl, mark.virt_text[1][2]) end
    end
  end)

  it('draws a rule across the window', function()
    render({ 'a', '', '---', '', 'b' })

    eq(string.rep('─', Renderer.RULE_WIDTH), virt_text(2)[1])
  end)

  it('only redraws the rows it is given, keeping marks above them', function()
    render({ '# One', '', '# Two' })
    Renderer(buf):render(2)

    assert.is_truthy(find(0, 'hl_group'))
    assert.is_truthy(find(2, 'hl_group'))
  end)

  it('renders the rows it is given as a document of their own', function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'intro', '', '```lua', 'local x = 1', '```' })
    Renderer(buf):render(2)

    assert.is_nil(find(0, 'line_hl_group'))
    assert.is_truthy(find(3, 'line_hl_group'))
  end)

  it('applies the markdown highlights and conceals itself, with no parser on the buffer', function()
    render({ 'some **bold** text', '', '```lua', 'local x = 1', '```' })

    local groups, conceals = {}, 0

    for _, mark in ipairs(marks()) do
      if mark.hl_group then groups[mark.hl_group] = true end
      if mark.conceal then conceals = conceals + 1 end
    end

    assert.is_true(groups['@markup.strong.markdown_inline'])
    assert.is_true(groups['@keyword.lua'])
    assert.is_true(conceals >= 2)
    assert.is_truthy(find(2, 'conceal_lines'))
    eq(false, vim.treesitter.highlighter.active[buf] ~= nil)
  end)

  it('colours code above the code block it sits in, taking query priorities as they are', function()
    render({ '```lua', 'local x = 1', '```' })

    local block, keyword

    for _, mark in ipairs(marks()) do
      if mark.hl_group == '@markup.raw.block.markdown' and mark.end_row == 3 then block = mark end
      if mark.hl_group == '@keyword.lua' then keyword = mark end
    end

    eq(90, block.priority)
    eq(Renderer.HIGHLIGHT_PRIORITY, keyword.priority)
  end)

  it('asks resolve about links and code spans, and marks the ones it knows', function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'see [a](nvim://file/a.lua#L3) and `b.lua` and `nope`' })

    local asked = {}
    local renderer = Renderer(buf, {
      resolve = function(kind, text)
        asked[#asked + 1] = kind .. ':' .. text
        return text ~= 'nope' and { icon = { '> ', 'UiPath' } } or nil
      end,
    })

    renderer:render(0)

    eq({ 'link:nvim://file/a.lua#L3', 'code:b.lua', 'code:nope' }, asked)
    eq({ '> ', '> ' }, virt_text(0))
    eq({ 'link', 'nvim://file/a.lua#L3' }, { renderer:inline_at(0, 5) })
    eq({ 'code', 'b.lua' }, { renderer:inline_at(0, 36) })
    assert.is_nil(renderer:inline_at(0, 0))
  end)

  it('keeps hiding code fence lines after another plugin disables patterns on the shared query', function()
    local shared = vim.treesitter.query.get('markdown', 'highlights')

    assert.is_true(Renderer.highlights('markdown') ~= shared)

    for id, directives in pairs(shared.info.patterns) do
      for _, directive in ipairs(directives) do
        if vim.tbl_contains(directive, 'conceal_lines') then shared.query:disable_pattern(id) end
      end
    end

    render({ 'text', '```lua', 'local x = 1', '```' })

    assert.is_truthy(find(1, 'conceal_lines'))
    assert.is_truthy(find(3, 'conceal_lines'))
  end)
  it('annotates lines into mark specs without a buffer, shifted by the offset', function()
    local marks = Renderer(0):annotate({ '# Title', '', '- item' }, 10)
    local rows = {}

    for _, mark in ipairs(marks) do
      rows[mark.row] = true
      eq('table', type(mark.opts))
    end

    assert.is_true(rows[10])
    assert.is_true(rows[12])
    assert.is_nil(rows[0])
  end)

  it('annotates nothing for empty input', function()
    eq(
      {},
      vim.tbl_filter(function(mark)
        return mark.opts.virt_text ~= nil
      end, Renderer(0):annotate({ '' }, 0))
    )
  end)

  it('draws a pipe table as a box above its rows and hides the source rows', function()
    local marks = Renderer(0):annotate({ '| a | b |', '| --- | --: |', '| 1 | 22 |', '' }, 4)
    local box, hidden = nil, {}

    for _, mark in ipairs(marks) do
      if mark.opts.virt_lines then box = mark end
      if mark.opts.conceal_lines then hidden[mark.row] = true end
    end

    eq(7, box.row)
    eq(true, box.opts.virt_lines_above)
    eq(5, #box.opts.virt_lines)
    eq({ [4] = true, [5] = true, [6] = true }, hidden)
  end)

  it('hangs the box below the line before a table that ends the text, and leaves a lone table raw', function()
    local function box_of(lines)
      for _, mark in ipairs(Renderer(0):annotate(lines, 0)) do
        if mark.opts.virt_lines then return mark end
      end
    end

    local below = box_of({ 'intro', '', '| a |', '| - |' })

    eq(1, below.row)
    assert.is_falsy(below.opts.virt_lines_above)
    assert.is_nil(box_of({ '| a |', '| - |' }))
  end)

  it('redraws from a row with the rows above as context, matching a full render', function()
    local function all(bufnr)
      local out = {}

      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, Renderer.NAMESPACE, 0, -1, { details = true })) do
        out[#out + 1] = vim.inspect({ mark[2], mark[3], mark[4] })
      end

      table.sort(out)

      return out
    end

    render({ '> [!note]', '> one `a`', '>', '> two' })
    vim.api.nvim_buf_set_lines(buf, 3, -1, false, { '> two **b**', '>', '> three' })
    Renderer(buf):render(3, nil, 0)

    local whole = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_lines(whole, 0, -1, false, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    Renderer(whole):render(0)

    eq(all(whole), all(buf))
    vim.api.nvim_buf_delete(whole, { force = true })
  end)

  it('annotates from a row, keeping only marks on it or reaching into it', function()
    local lines = { '> quoted', '> more', '', 'after' }
    local marks = Renderer(0):annotate(lines, 10, 11)

    for _, mark in ipairs(marks) do
      assert.is_true(Renderer.reaches(mark.row, mark.opts, 11))
    end

    assert.truthy(vim.iter(marks):find(function(mark)
      return mark.row == 10 and mark.opts.end_row ~= nil
    end))
    assert.is_nil(vim.iter(marks):find(function(mark)
      return mark.row == 10 and mark.opts.end_row == nil
    end))
  end)

  it('clearing from a table also clears its box hung below the line before it', function()
    render({ '# Title', '', '| a |', '| - |' })

    assert.truthy(find(1, 'virt_lines'))

    Renderer(buf):clear(2)

    assert.is_nil(find(1, 'virt_lines'))
    assert.truthy(find(0, 'conceal'))
  end)

  it('shades code blocks by language when given a surface for it', function()
    local renderer = Renderer(0, { code_hl = { output = 'UiToolOutput' } })
    local surfaces = {}

    for _, mark in ipairs(renderer:annotate({ '```output', 'x', '```', '', '```lua', 'y', '```' }, 0)) do
      if mark.opts.line_hl_group then surfaces[mark.row] = mark.opts.line_hl_group end
    end

    eq('UiToolOutput', surfaces[1])
    eq('UiMarkdownCode', surfaces[5])
  end)

  it('shades a terminal fence with the terminal surface it is given', function()
    local renderer = Renderer(0, { code_hl = { terminal = 'UiTerminal' } })
    local surfaces = {}

    for _, mark in ipairs(renderer:annotate({ '```terminal_bash', 'ls', '```' }, 0)) do
      if mark.opts.line_hl_group then surfaces[mark.row] = mark.opts.line_hl_group end
    end

    eq({ 'UiTerminal', 'UiTerminal', 'UiTerminal' }, { surfaces[0], surfaces[1], surfaces[2] })
  end)

  it('leaves a fence with no surface when its family is set to false', function()
    local renderer = Renderer(0, { code_hl = { split = false } })
    local surfaces = 0

    for _, mark in ipairs(renderer:annotate({ '```split', 'x', '```' }, 0)) do
      if mark.opts.line_hl_group then surfaces = surfaces + 1 end
    end

    eq(0, surfaces)
  end)

  it('highlights an output fence in its language, shaded and unlabelled like any output', function()
    local renderer = Renderer(0, { hidden_labels = { output = true }, code_hl = { output = 'UiToolOutput' } })
    local surface, lua, label = false, false, false

    for _, mark in ipairs(renderer:annotate({ '```output_lua', 'local x = 1', '```' }, 0)) do
      if mark.opts.line_hl_group == 'UiToolOutput' then surface = true end
      if mark.opts.hl_group and mark.opts.hl_group:find('%.lua$') then lua = true end
      if mark.opts.virt_text_pos == 'right_align' then label = true end
    end

    eq({ true, true, false }, { surface, lua, label })
  end)

  it('colours one line of code, parsing each distinct text once, and nothing for an unknown language', function()
    local out = Renderer.code({}, 'local x = require("a")', 'lua', 3, 7)
    local groups = {}

    for _, mark in ipairs(out) do
      eq(3, mark.row)
      assert.is_true(mark.col >= 7)
      groups[mark.opts.hl_group] = true
    end

    assert.truthy(groups['@keyword.lua'])
    eq(true, Renderer.syntax('local y', 'lua') == Renderer.syntax('local y', 'lua'))
    eq({}, Renderer.syntax('anything', 'no_such_language'))
  end)

  it('maps content treesitter captures onto block rows', function()
    local marks = Renderer.content({
      start = 10,
      lines = { '-> cat a.lua', '```output_lua', 'local x = 1', '```' },
    }, { language = 'lua', first = 3, trim = 1, captures = { keyword = 'UiPath' } })

    local found

    for _, mark in ipairs(marks) do
      if mark.row == 12 and mark.opts.hl_group == 'UiPath' then found = mark end
    end

    assert.is_not_nil(found)
    eq(0, found.col)
    eq(5, found.opts.end_col)
  end)
end)
