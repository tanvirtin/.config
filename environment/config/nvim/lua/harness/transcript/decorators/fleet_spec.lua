local Tile = require('ui.pixel.Tile')
local glyph = require('ui.design.glyph')
local theme = require('harness.transcript.theme')
local Block = require('harness.transcript.model.Block')
local fleet = require('harness.transcript.decorators.fleet')
local FleetMember = require('harness.transcript.model.FleetMember')

local eq = assert.are.same
local NOW = 5000
local BODY = 'h2%s+claude%s+haiku%s+Read x%.lua$'

local function find(marks, predicate)
  for _, mark in ipairs(marks) do
    if predicate(mark.opts, mark) then return mark end
  end
end

local function virt(opts)
  return opts.virt_text and table.concat(vim.tbl_map(function(chunk)
    return chunk[1]
  end, opts.virt_text))
end

local function mark_on(marks, row, pos)
  return find(marks, function(opts, mark)
    return mark.row == row and opts.virt_text_pos == pos
  end)
end

local function tail_on(marks, row)
  return find(marks, function(opts, mark)
    return mark.row == row and (opts.virt_text_pos == 'right_align' or opts.virt_text_pos == 'eol')
  end)
end

local function chunk_on(marks, row, value)
  local mark = mark_on(marks, row, 'inline')

  return vim.tbl_filter(function(chunk)
    return chunk[1] == value
  end, mark.opts.virt_text)[1]
end

local function fleet_block(members, lines)
  members = members or { { key = 'h2', agent = 'claude', prompt = 'scout' }, { key = 'h3', agent = 'codex' } }

  if not lines then
    lines = { '-> fleet' }

    for _, info in ipairs(members) do
      lines[#lines + 1] = '   ' .. info.key
    end
  end

  local block = Block.make(Block.KIND.fleet, lines, {
    id = 'fleet:t1',
    members = members,
    folds = { { 1, 2 } },
  })

  block.start = 0
  block.finish = #lines

  return block
end

local function run(block, snapshot, width)
  return fleet(block, { now = NOW, width = width or 100, fleet = snapshot })
end

local function live_snapshot(h2_started)
  return {
    h2 = FleetMember({
      key = 'h2',
      state = 'working',
      agent = 'claude',
      model = 'haiku',
      tool = 'Read x.lua',
      cost = 0.004,
      started = h2_started or 1000,
      activity = { 0, 1, 2, 0, 3, 1 },
      digest = 'x',
    }),
    h3 = FleetMember({
      key = 'h3',
      state = 'waiting',
      agent = 'codex',
      ask = 'edit x.lua',
      cost = 0.002,
      started = 1000,
      digest = 'y',
    }),
  }
end

describe('harness.transcript.decorators.fleet', function()
  local original

  before_each(function()
    original = { available = Tile.available, reduced = theme.reduced }
    Tile.available = function()
      return false
    end
  end)

  after_each(function()
    Tile.available, theme.reduced = original.available, original.reduced
  end)

  it('gives every row a concealed raw-text mark on the surface band', function()
    local block = fleet_block()
    local marks = run(block, live_snapshot())

    for row = 0, #block.members do
      local conceal = find(marks, function(opts, mark)
        return mark.row == row and opts.conceal == ''
      end)

      eq({ '', #block.lines[row + 1], 'UiSurface' }, {
        conceal.opts.conceal,
        conceal.opts.end_col,
        conceal.opts.line_hl_group,
      })
    end
  end)

  it('gives every row an inline virtual text', function()
    local block = fleet_block()
    local marks = run(block, live_snapshot())

    for row = 0, #block.members do
      assert.truthy(mark_on(marks, row, 'inline'))
    end
  end)

  it('summarises a live fleet by its working and needs-you counts', function()
    local marks = run(fleet_block(), live_snapshot())
    local summary = glyph.join({ '2 agents', '1 working', '1 needs you' })

    local chunk = chunk_on(marks, 0, '  ' .. summary)

    eq({ '  ' .. summary, 'UiWarn' }, { chunk[1], chunk[2] })
  end)

  it('summarises a settled fleet by its done and failed counts', function()
    local snapshot = {
      h2 = FleetMember({ key = 'h2', state = 'done', agent = 'claude', started = 1000, finished = 3000 }),
      h3 = FleetMember({ key = 'h3', state = 'failed', agent = 'codex', started = 1000, finished = 2000 }),
    }
    local marks = run(fleet_block(), snapshot)
    local summary = glyph.join({ '2 agents', glyph.STATUS.done .. '1 ' .. glyph.STATUS.failed .. '1' })

    local chunk = chunk_on(marks, 0, '  ' .. summary)

    eq({ '  ' .. summary, 'UiMuted' }, { chunk[1], chunk[2] })
  end)

  it('leaves out the working count when every live agent needs you', function()
    local snapshot = {
      h2 = FleetMember({ key = 'h2', state = 'waiting', agent = 'claude', ask = 'Bash', started = 1000 }),
      h3 = FleetMember({ key = 'h3', state = 'waiting', agent = 'codex', ask = 'Write', started = 1000 }),
    }
    local marks = run(fleet_block(), snapshot)
    local summary = glyph.join({ '2 agents', '2 needs you' })

    assert.truthy(chunk_on(marks, 0, '  ' .. summary))
  end)

  it('right-aligns the summed cost and elapsed time when the header fits', function()
    local marks = run(fleet_block(), live_snapshot())
    local tail = tail_on(marks, 0)

    eq(
      { 'right_align', '$0.006', '  4s' },
      { tail.opts.virt_text_pos, tail.opts.virt_text[1][1], tail.opts.virt_text[2][1] }
    )
  end)

  it('moves the header tail to the end of the line when the width is tiny', function()
    local marks = run(fleet_block(), live_snapshot(), 20)
    local tail = tail_on(marks, 0)

    eq({ 'eol', '  ', '$0.006' }, { tail.opts.virt_text_pos, tail.opts.virt_text[1][1], tail.opts.virt_text[2][1] })
  end)

  it('shows a working member with its key, agent, model and tool label', function()
    local marks = run(fleet_block(), live_snapshot())

    assert.truthy(virt(mark_on(marks, 1, 'inline').opts):match(BODY))
  end)

  it('shows a waiting member as a question about its pending ask', function()
    local marks = run(fleet_block(), live_snapshot())
    local chunk = chunk_on(marks, 2, 'allow edit x.lua?')

    eq({ 'allow edit x.lua?', 'UiWarn' }, { chunk[1], chunk[2] })
  end)

  it('shows a done member with its result in the added colour', function()
    local snapshot = {
      h2 = FleetMember({
        key = 'h2',
        state = 'done',
        agent = 'claude',
        result = 'Found 3 files',
        started = 1000,
        finished = 3000,
      }),
      h3 = FleetMember({ key = 'h3', state = 'waiting', agent = 'codex', ask = 'Write', started = 1000 }),
    }
    local marks = run(fleet_block(), snapshot)
    local chunk = chunk_on(marks, 1, 'Found 3 files')

    eq({ 'Found 3 files', 'UiAdded' }, { chunk[1], chunk[2] })
  end)

  it('shows a failed member with its result in the error colour', function()
    local snapshot = {
      h2 = FleetMember({
        key = 'h2',
        state = 'failed',
        agent = 'claude',
        result = 'timed out',
        started = 1000,
        finished = 3000,
      }),
      h3 = FleetMember({ key = 'h3', state = 'waiting', agent = 'codex', ask = 'Write', started = 1000 }),
    }
    local marks = run(fleet_block(), snapshot)
    local chunk = chunk_on(marks, 1, 'timed out')

    eq({ 'timed out', 'UiError' }, { chunk[1], chunk[2] })
  end)

  it('shows a missing member with its prompt, or ended when it has none', function()
    local block = fleet_block({ { key = 'h2', agent = 'claude', prompt = 'scout' }, { key = 'h3', agent = 'codex' } })
    local marks = run(block, {})

    eq({ 'scout', 'UiMuted' }, { chunk_on(marks, 1, 'scout')[1], chunk_on(marks, 1, 'scout')[2] })
    eq({ 'ended', 'UiMuted' }, { chunk_on(marks, 2, 'ended')[1], chunk_on(marks, 2, 'ended')[2] })
  end)

  it('draws a sparkline, cost and duration on a member row with activity', function()
    local marks = run(fleet_block(), live_snapshot())

    eq(' ▃▆ █▃  $0.004  4s', virt(tail_on(marks, 1).opts))
  end)

  it('omits the sparkline for a member without activity', function()
    local snapshot = {
      h2 = FleetMember({ key = 'h2', state = 'done', agent = 'claude', cost = 0.01, started = 1000, finished = 3000 }),
      h3 = FleetMember({ key = 'h3', state = 'waiting', agent = 'codex', ask = 'Write', started = 1000 }),
    }
    local marks = run(fleet_block(), snapshot)

    eq('$0.010  2s', virt(tail_on(marks, 1).opts))
  end)

  it('scrambles a member row during the tune window after it starts', function()
    local plain = virt(mark_on(run(fleet_block(), live_snapshot(1000)), 1, 'inline').opts)
    local fresh = virt(mark_on(run(fleet_block(), live_snapshot(NOW)), 1, 'inline').opts)

    assert.truthy(plain:match(BODY))
    eq(false, fresh == plain)
  end)

  it('shows a member row plainly once the tune window has passed', function()
    local started = NOW - fleet.TUNE_MS
    local marks = run(fleet_block(), live_snapshot(started))

    assert.truthy(virt(mark_on(marks, 1, 'inline').opts):match(BODY))
  end)

  it('shows a member row plainly when motion is reduced', function()
    theme.reduced = function()
      return true
    end

    local marks = run(fleet_block(), live_snapshot(NOW))

    assert.truthy(virt(mark_on(marks, 1, 'inline').opts):match(BODY))
  end)

  it('tallies live, waiting, done and failed members and sums their cost', function()
    local block = fleet_block({
      { key = 'h2', agent = 'claude' },
      { key = 'h3', agent = 'codex' },
      { key = 'h4', agent = 'gemini' },
      { key = 'h5', agent = 'claude' },
      { key = 'h6', agent = 'codex' },
      { key = 'h7', agent = 'claude' },
    })
    local snapshot = {
      h2 = FleetMember({ key = 'h2', state = 'working', cost = 0.004, started = 1000 }),
      h3 = FleetMember({ key = 'h3', state = 'waiting', cost = 0.002, started = 1000 }),
      h4 = FleetMember({ key = 'h4', state = 'done', cost = 0.01, started = 1500, finished = 3000 }),
      h5 = FleetMember({ key = 'h5', state = 'failed', started = 1200, finished = 2500 }),
      h6 = FleetMember({ key = 'h6', state = 'cancelled', cost = 0.001, started = 1100, finished = 2800 }),
    }
    local counts = fleet.tally(block, snapshot)

    eq({ 2, 1, 1, 2, 6 }, { counts.live, counts.waiting, counts.done, counts.failed, counts.total })
    eq('0.017', string.format('%.3f', counts.cost))
    eq({ 1000, 3000 }, { counts.started, counts.finished })
  end)

  it('counts a cancelled member as failed', function()
    local block = fleet_block({ { key = 'h2', agent = 'claude' } }, { '-> fleet', '   h2' })
    local counts = fleet.tally(block, {
      h2 = FleetMember({ key = 'h2', state = 'cancelled', started = 1000, finished = 2000 }),
    })

    eq({ 0, 0, 1 }, { counts.live, counts.done, counts.failed })
  end)

  it('joins the agent count with the done and failed counts for a settled fleet', function()
    eq(
      glyph.join({ '3 agents', glyph.STATUS.done .. '2 ' .. glyph.STATUS.failed .. '1' }),
      fleet.summary({
        total = 3,
        live = 0,
        waiting = 0,
        done = 2,
        failed = 1,
      })
    )
  end)

  it('can be called as the module itself', function()
    local block = fleet_block()
    local snapshot = live_snapshot()

    eq(
      #fleet.decorate(block, { now = NOW, width = 100, fleet = snapshot }),
      #fleet(block, { now = NOW, width = 100, fleet = snapshot })
    )
  end)
end)
