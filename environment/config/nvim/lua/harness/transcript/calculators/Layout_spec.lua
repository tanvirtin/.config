local Layout = require('harness.transcript.calculators.Layout')

local eq = assert.are.same

local function block(kind, lines)
  return { kind = kind, lines = lines }
end

describe('harness.transcript.calculators.Layout:', function()
  it('places blocks one after another with a blank line between, except a streaming reply', function()
    local list = { block('prompt', { 'hi' }), block('message', { 'a', 'b' }) }

    eq({ 'hi', '', 'a', 'b' }, Layout.place(list, 1, 0))
    eq({ 0, 2 }, { list[1].start, list[1].finish })
    eq({ 2, 4 }, { list[2].start, list[2].finish })
  end)

  it('places from a given block and row, leaving earlier blocks alone', function()
    local list = { block('prompt', { 'hi' }), block('tool', { 'x' }) }

    list[1].start, list[1].finish = 0, 2

    eq({ 'x', '' }, Layout.place(list, 2, 2))
    eq({ 2, 4 }, { list[2].start, list[2].finish })
  end)

  it('finds the first block whose kind or lines changed', function()
    local a, b = block('prompt', { 'hi' }), block('message', { 'x' })

    assert.is_nil(Layout.first_changed({ a, b }, { a, block('message', { 'x' }) }))
    eq(2, Layout.first_changed({ a, b }, { a, block('message', { 'y' }) }))
    eq(2, Layout.first_changed({ a }, { a, b }))
    eq(1, Layout.first_changed({ a }, { block('tool', { 'hi' }) }))
  end)

  it('treats a reply that stops streaming as changed, since it gains its trailing blank', function()
    local reply = block('message', { 'x' })

    eq(1, Layout.first_changed({ reply }, { reply, block('stop', { 'done' }) }))
  end)

  it('finds the block at a row by binary search, falling back to the last block', function()
    local list = { block('prompt', { 'a' }), block('tool', { 'b', 'c' }), block('stop', { 'd' }) }

    Layout.place(list, 1, 0)

    eq(list[1], Layout.block_at(list, 0))
    eq(list[2], Layout.block_at(list, 3))
    eq(list[3], Layout.block_at(list, 5))
    eq(list[3], Layout.block_at(list, 99))
  end)

  it('signs a block by the fields that change its decoration', function()
    local a = { kind = 'tool', status = 'pending' }
    local b = { kind = 'tool', status = 'completed' }

    assert.are_not.equal(Layout.signature(a), Layout.signature(b))
    eq(Layout.signature(a), Layout.signature({ kind = 'tool', status = 'pending', lines = { 'other' } }))
    assert.are_not.equal(Layout.signature(a), Layout.signature({ kind = 'tool', status = 'pending', nested = 2 }))
  end)

  it('finds the prompt of the turn a row is in, once that prompt starts above the row', function()
    local list = {
      block('title', { '# t' }),
      block('prompt', { '> one' }),
      block('message', { 'a', 'b', 'c' }),
      block('prompt', { '> two' }),
      block('message', { 'd' }),
    }

    list[4].steered = nil
    Layout.place(list, 1, 0)

    for i, item in ipairs(list) do
      item.index = i
    end

    assert.is_nil(Layout.prompt_above(list, 0))
    assert.is_nil(Layout.prompt_above(list, list[2].start))
    eq(list[2], Layout.prompt_above(list, list[3].start + 1))
    eq(list[4], Layout.prompt_above(list, list[5].start))
  end)

  it('skips steering prompts, which belong to the turn they steer', function()
    local list = { block('prompt', { '> one' }), block('prompt', { '> nudge' }), block('message', { 'x' }) }

    list[2].steered = true
    Layout.place(list, 1, 0)

    for i, item in ipairs(list) do
      item.index = i
    end

    eq(list[1], Layout.prompt_above(list, list[3].start))
  end)

  it('settles a streaming reply up to the last top-level block that starts after a blank line', function()
    local lines = { '# Title', '', 'one', 'two', '', '- item', '', 'three' }

    eq(7, Layout.settled(lines, #lines))
    eq(5, Layout.settled(lines, 6))
    eq(2, Layout.settled(lines, 4))
    eq(0, Layout.settled(lines, 1))
  end)

  it('never settles at a table, which hangs its box on the line before it', function()
    eq(2, Layout.settled({ 'intro', '', 'para', '', '| a |', '| - |' }, 6))
    eq(6, Layout.settled({ 'intro', '', '| a |', '| - |', '', '', 'after' }, 7))
  end)

  it('never settles inside a code fence, closed or still streaming, or before an indented line', function()
    eq(0, Layout.settled({ 'intro', '```lua', 'a', '', 'b' }, 5))
    eq(0, Layout.settled({ 'intro', '```lua', 'a', '', 'b', '```', '', 'after' }, 5))
    eq(7, Layout.settled({ 'intro', '```lua', 'a', '', 'b', '```', '', 'after' }, 8))
    eq(0, Layout.settled({ '- one', '', '  continued' }, 3))
  end)

  it('keeps placement, lookup and change detection consistent over generated blocks', function()
    local seed = 17
    local kinds = { 'prompt', 'message', 'tool', 'diff', 'stop' }

    local function next(n)
      seed = (seed * 1103515245 + 12345) % 2147483648

      return seed % n
    end

    for _ = 1, 40 do
      local list = {}

      for i = 1, 1 + next(8) do
        local lines = {}

        for j = 1, 1 + next(4) do
          lines[j] = 'line ' .. i .. ':' .. j
        end

        list[i] = block(kinds[1 + next(#kinds)], lines)
      end

      local rendered = Layout.place(list, 1, 0)

      for i, item in ipairs(list) do
        local expected = item.start + #item.lines + (Layout.streaming(list, i) and 0 or 1)

        eq(expected, item.finish)
        eq(item, Layout.block_at(list, item.start))
        eq(item, Layout.block_at(list, item.finish - 1))
      end

      eq(list[#list].finish, #rendered)
      assert.is_nil(Layout.first_changed(list, list))

      local changed = 1 + next(#list)
      local copy = {}

      for i, item in ipairs(list) do
        copy[i] = block(item.kind, item.lines)
      end

      copy[changed].lines = { 'different' }

      eq(changed, Layout.first_changed(list, copy))
    end
  end)
end)
