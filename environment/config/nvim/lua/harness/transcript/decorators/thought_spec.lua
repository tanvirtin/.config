local Tile = require('ui.pixel.Tile')
local Block = require('harness.transcript.Block')
local decorators = require('harness.transcript.decorators')

local eq = assert.are.same

local function make(lines, fields)
  local block = Block.make(Block.KIND.thought, lines, fields)

  block.start = 0
  block.finish = #lines + 1

  return block
end

local function concealed(marks)
  return vim.tbl_map(
    function(mark)
      return mark.row
    end,
    vim.tbl_filter(function(mark)
      return mark.opts.conceal_lines ~= nil
    end, marks)
  )
end

local function body_group(marks, row)
  local found = vim.tbl_filter(function(mark)
    return mark.row == row and mark.opts.hl_group ~= nil
  end, marks)

  return found[1] and found[1].opts.hl_group
end

local function inline(marks)
  return vim.tbl_filter(function(mark)
    return mark.opts.virt_text_pos == 'inline'
  end, marks)[1].opts.virt_text
end

local function tail(marks)
  local found = vim.tbl_filter(function(mark)
    return mark.opts.virt_text_pos == 'eol'
  end, marks)[1]
  local text = {}

  for _, chunk in ipairs(found.opts.virt_text) do
    text[#text + 1] = chunk[1]
  end

  return table.concat(text)
end

local SIX = { '> [!thought]', '> one', '> two', '> three', '> four', '> five', '> six' }

describe('harness.transcript.decorators.thought:', function()
  local original

  before_each(function()
    original = Tile.available
    Tile.available = function()
      return false
    end
  end)

  after_each(function()
    Tile.available = original
  end)

  it('conceals the older body rows of a pulsing thought and fades in its last three', function()
    local marks = decorators.decorate(make(SIX, { live = true, started = 0 }), { running = true, now = 0 })

    eq({ 1, 2, 3 }, concealed(marks))
    eq('UiThoughtFade2', body_group(marks, 4))
    eq('UiThoughtFade1', body_group(marks, 5))
    eq('UiThought', body_group(marks, 6))
    eq(nil, body_group(marks, 3))
  end)

  it('shows a lone body row of a pulsing thought in the full thought colour, hiding nothing', function()
    local marks = decorators.decorate(make({ '> [!thought]', '> only' }, { live = true }), { running = true, now = 0 })

    eq({}, concealed(marks))
    eq('UiThought', body_group(marks, 1))
  end)

  it('fades in two rows when only two body rows exist, the newest in the full thought colour', function()
    local marks =
      decorators.decorate(make({ '> [!thought]', '> one', '> two' }, { live = true }), { running = true, now = 0 })

    eq({}, concealed(marks))
    eq('UiThoughtFade1', body_group(marks, 1))
    eq('UiThought', body_group(marks, 2))
  end)

  it('hides nothing of a revealed pulsing thought', function()
    local marks = decorators.decorate(
      make(SIX, { live = true, first_event = 7 }),
      { running = true, now = 0, revealed = { [7] = true } }
    )

    eq({}, concealed(marks))
    eq('UiThought', body_group(marks, 1))
  end)

  it('is labelled Thinking while it pulses and Thought once it is done', function()
    local live = decorators.decorate(make(SIX, { live = true, started = 0 }), { running = true, now = 0 })
    local done = decorators.decorate(make(SIX, { started = 0, finished = 2000 }), {})

    eq('Thinking', inline(live)[2][1])
    eq('Thought', inline(done)[1][1])
  end)

  it('says how long a finished thought took, before its gist', function()
    local done = decorators.decorate(make({ '> [!thought]', '> the idea' }, { started = 0, finished = 2000 }), {})

    eq('  for 2s · the idea', tail(done))
  end)

  it('shows only the elapsed time of a pulsing thought, with no gist', function()
    local live = decorators.decorate(make(SIX, { live = true, started = 0 }), { running = true, now = 4200 })

    eq('  4s', tail(live))
  end)

  it('conceals nothing and dims the whole body once it is done', function()
    local done = decorators.decorate(make(SIX, { started = 0, finished = 2000 }), {})

    eq({}, concealed(done))
    eq('UiThought', body_group(done, 1))
  end)
end)
