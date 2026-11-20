local hl = require('ui.hl')
local markup = require('ui.markup')

local eq = assert.are.same

describe('ui.markup:', function()
  before_each(function()
    hl.define()
  end)

  it('names the group of a tag: a Ui role in lower case, or any highlight group by its capitalised name', function()
    eq('UiAccent', markup.group('accent'))
    eq('UiFade3', markup.group('UiFade3'))
    eq('Comment', markup.group('Comment'))
    assert.is_nil(markup.group('comment'))
    assert.is_nil(markup.group('nosuchgroup'))
    assert.is_nil(markup.group(''))
  end)

  it('takes the tags out of a line and says which bytes each one styled', function()
    eq({ 'a hot word', { { hl = 'UiAccent', from = 2, to = 5 } } }, { markup.parse('a [accent]hot[/] word') })
    eq({ 'plain', {} }, { markup.parse('plain') })
  end)

  it('styles to the end of the line when a tag is left open, and counts bytes, not characters', function()
    eq({ '▓▓ on', { { hl = 'UiMuted', from = 0, to = 6 }, { hl = 'UiMuted', from = 6, to = 9 } } }, {
      markup.parse('[muted]▓▓[muted] on'),
    })
  end)

  it('gives a span inside another its own style, then returns to the outer one', function()
    eq({
      'abc',
      {
        { hl = 'UiMuted', from = 0, to = 1 },
        { hl = 'UiAccent', from = 1, to = 2 },
        { hl = 'UiMuted', from = 2, to = 3 },
      },
    }, { markup.parse('[muted]a[accent]b[/]c[/]') })
  end)

  it('leaves brackets alone when they name no style, close nothing, or are escaped', function()
    eq({ 'items[1] [x] [/] []', {} }, { markup.parse('items[1] [x] [/] []') })
    eq({ '[accent] is a tag', {} }, { markup.parse('\\[accent] is a tag') })
    eq({ 'a[/]', { { hl = 'UiAccent', from = 0, to = 1 }, { hl = 'UiAccent', from = 1, to = 4 } } }, {
      markup.parse('[accent]a\\[/]'),
    })
  end)

  it('puts an inline embed in its row, with its highlights at the bytes it fills after a styled prefix', function()
    local embed = {
      a = { { { 'ab', 'Foo' }, { 'c' } } },
    }

    eq(
      { { 'x abc y' }, { { hl = 'UiAccent', row = 0, from = 0, to = 1 }, { hl = 'Foo', row = 0, from = 2, to = 4 } } },
      {
        markup.render({ '[accent]x[/] {@a} y' }, 0, '', function(id)
          return embed[id]
        end),
      }
    )
  end)

  it('expands a line that is only a token into each row of the embed, with the pad in front', function()
    local embed = {
      b = { { { 'one', 'A' } }, { { 'two' } }, { { 'three', 'B' } } },
    }
    local shown, highlights = markup.render({ '  {@b}  ' }, 0, '  ', function(id)
      return embed[id]
    end)

    eq({ '  one', '  two', '  three' }, shown)
    eq({ { hl = 'A', row = 0, from = 2, to = 5 }, { hl = 'B', row = 2, from = 2, to = 7 } }, highlights)
  end)

  it('numbers the highlights by output row once a token line has grown into several rows', function()
    local embed = {
      b = { { { 'one' } }, { { 'two', 'C' } } },
    }
    local shown, highlights = markup.render({ '[accent]x[/]', '{@b}', '[muted]y[/]' }, 0, '', function(id)
      return embed[id]
    end)

    eq({ 'x', 'one', 'two', 'y' }, shown)
    eq({
      { hl = 'UiAccent', row = 0, from = 0, to = 1 },
      { hl = 'C', row = 2, from = 0, to = 3 },
      { hl = 'UiMuted', row = 3, from = 0, to = 1 },
    }, highlights)
  end)

  it('refuses an inline token whose embed is taller than one row', function()
    local embed = {
      b = { { { 'one' } }, { { 'two' } } },
    }

    assert.has_error(function()
      markup.render({ 'a {@b} c' }, 0, '', function(id)
        return embed[id]
      end)
    end, '{@b} is 2 rows tall; put it on a line of its own')
  end)

  it('refuses a token whose embed does not exist', function()
    assert.has_error(function()
      markup.render({ '{@zz}' }, 0, '', function()
        return nil
      end)
    end, 'no component zz')
  end)

  it('leaves a token as text when there is no embed, and leaves lines without tokens unchanged with one', function()
    local embed = function()
      return { { { 'never' } } }
    end

    eq({ { '{@a} x' }, {} }, { markup.render({ '{@a} x' }, 0, '') })
    eq({ markup.render({ '[accent]y[/] z' }, 0, ' ') }, { markup.render({ '[accent]y[/] z' }, 0, ' ', embed) })
  end)

  it('counts the width of each embed row, and the widest line, with embeds', function()
    local embed = {
      a = { { { 'xyz' } } },
      b = { { { 'one' } }, { { 'four' } } },
    }
    local function find(id)
      return embed[id]
    end

    eq(6, markup.width({ 'ab {@a}' }, 0, find))
    eq(4, markup.width({ '{@b}' }, 0, find))
    eq(2, markup.width({ '[accent]ab[/]' }, 0))
  end)
end)
