local link_text = require('harness.transcript.link_text')

local eq = assert.are.same

describe('harness.transcript.link_text:', function()
  it('keeps only the label of each link, noting where it sits and where it goes', function()
    local lines, links = link_text.strip({
      'See [Session.lua:26](nvim://file/lua/harness/Session.lua#L26) and [docs](https://x.dev/a).',
    })

    eq({ 'See Session.lua:26 and docs.' }, lines)
    eq({
      { row = 1, col = 4, end_col = 18, target = 'nvim://file/lua/harness/Session.lua#L26', label = 'Session.lua:26' },
      { row = 1, col = 23, end_col = 27, target = 'https://x.dev/a', label = 'docs' },
    }, links)
  end)

  it('leaves links alone inside code, fenced or inline, and leaves images', function()
    local input = {
      'Use `[a](b)` as written, ![logo](img.png) too.',
      '```markdown',
      '[inside](fence)',
      '```',
      '> [quoted](nvim://buf/3)',
    }
    local lines, links = link_text.strip(input)

    eq({ input[1], input[2], input[3], input[4], '> quoted' }, lines)
    eq(1, #links)
    eq({ 5, 2, 'nvim://buf/3' }, { links[1].row, links[1].col, links[1].target })
  end)

  it('reads angle-bracketed targets, and leaves an unfinished link as it is while it streams', function()
    local lines, links = link_text.strip({ '[a file](<path with spaces.lua>) and [half](nvim://file/x' })

    eq({ 'a file and [half](nvim://file/x' }, lines)
    eq('path with spaces.lua', links[1].target)
  end)

  it('puts the links back for a yank, exactly as the agent wrote them', function()
    local input = { 'See [a](x) then [b](y).', 'plain', '- [c](z)' }
    local lines, links = link_text.strip(input)

    eq({ 'See a then b.', 'plain', '- c' }, lines)
    eq(input, link_text.restore(lines, links))
  end)

  it('finds the link under a column', function()
    local _, links = link_text.strip({ 'go to [here](nvim://file/a.lua#L2) now' })

    eq('nvim://file/a.lua#L2', link_text.at(links, 1, 6).target)
    eq('nvim://file/a.lua#L2', link_text.at(links, 1, 9).target)
    assert.is_nil(link_text.at(links, 1, 10))
    assert.is_nil(link_text.at(links, 2, 6))
  end)
end)
