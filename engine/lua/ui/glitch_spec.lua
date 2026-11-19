local glitch = require('ui.glitch')

local eq = assert.are.same

local function width(text)
  return vim.fn.strdisplaywidth(text)
end

describe('ui.glitch:', function()
  it('leaves text alone at no density, and turns every printable character to static at full density', function()
    eq('Bash make test', glitch.scramble('Bash make test', 0, 4))

    local scrambled = glitch.scramble('Bash make test', 1, 4)

    eq(width('Bash make test'), width(scrambled))
    assert.is_nil(scrambled:find('[%w]'))
  end)

  it('keeps spaces and wide characters where they are', function()
    local scrambled = glitch.scramble('a ✓ b', 1, 9)

    eq(width('a ✓ b'), width(scrambled))
    assert.is_truthy(scrambled:find('✓', 1, true))
  end)

  it('changes from one seed to the next, and repeats for the same seed', function()
    local text = 'the quick brown fox jumps over the lazy dog'

    eq(glitch.scramble(text, 0.4, 1), glitch.scramble(text, 0.4, 1))
    assert.are_not.equal(glitch.scramble(text, 0.4, 1), glitch.scramble(text, 0.4, 2))
  end)

  it('draws a row of snow as wide as asked, different per row and per frame', function()
    local row = glitch.snow(40, 3, 1)

    eq(40, vim.fn.strdisplaywidth(row))
    assert.is_truthy(row:find('[░▒▓]'))
    assert.is_truthy(row:find(' ', 1, true))
    eq(row, glitch.snow(40, 3, 1))
    assert.are_not.equal(row, glitch.snow(40, 4, 1))
    assert.are_not.equal(row, glitch.snow(40, 3, 2))
  end)

  it('gives overlay columns on printable characters only, past an offset', function()
    local cols = glitch.cols('> ab cd', 1, 5, 2)

    eq(
      { 2, 3, 5, 6 },
      vim.tbl_map(function(entry)
        return entry[1]
      end, cols)
    )
    eq({}, glitch.cols('> ab cd', 0, 5))
  end)
end)
