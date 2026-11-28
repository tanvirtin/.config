local fleet = require('harness.transcript.model.fleet')
local Block = require('harness.transcript.model.Block')

local eq = assert.are.same

describe('harness.transcript.model.fleet', function()
  local function call(verb, id, fields)
    return Block.make(
      Block.KIND.tool,
      { '-> x' },
      vim.tbl_extend('force', {
        id = id,
        name = 'nvim:session_' .. verb,
        tool = 'mcp__nvim__session_' .. verb,
        input = {},
        status = 'completed',
        started = 10,
        finished = 20,
      }, fields or {})
    )
  end

  local function spawn(id, key, fields)
    return call(
      'new',
      id,
      vim.tbl_extend('force', {
        input = { agent = 'codex', prompt = 'review it' },
        output = vim.json.encode({ session = key, state = 'starting' }),
      }, fields or {})
    )
  end

  local function read(id, key, fields)
    return call('read', id, vim.tbl_extend('force', { input = { session = key } }, fields or {}))
  end

  local function message(id)
    return Block.make(Block.KIND.message, { 'text' }, { id = id, text = 'hi' })
  end

  local function ids(list)
    return vim.tbl_map(function(block)
      return block.id
    end, list)
  end

  it('names the verb of a session tool from its tool or its name', function()
    eq('new', fleet.verb(spawn('t1', 'h3')))
    eq('prompt', fleet.verb(call('prompt', 't2', { input = { session = 'h3' } })))
    eq('read', fleet.verb(read('t3', 'h3')))
    eq('list', fleet.verb(call('list', 't4')))
    eq('cancel', fleet.verb(call('cancel', 't5', { input = { session = 'h3' } })))
    eq('close', fleet.verb(Block.make(Block.KIND.tool, { '-> x' }, { id = 't6', name = 'nvim:session_close' })))
  end)

  it('gives no verb to other tools, child calls, grouped calls and other kinds', function()
    assert.is_nil(fleet.verb(Block.make(Block.KIND.tool, { '-> x' }, { id = 't1', name = 'Bash', tool = 'Bash' })))
    assert.is_nil(fleet.verb(call('status', 't2')))
    assert.is_nil(fleet.verb(read('t3', 'h3', { parent = 'p1' })))
    assert.is_nil(fleet.verb(read('t4', 'h3', { grouped = 2 })))
    assert.is_nil(fleet.verb(Block.make(Block.KIND.message, { 'x' }, { id = 'm1', text = 'session_read' })))
  end)

  it('returns the same list when no session block resolves a key', function()
    local list = {
      call('list', 't1'),
      Block.make(Block.KIND.tool, { '-> x' }, { id = 't2', tool = 'Bash' }),
      read('t3', nil),
    }

    assert.are.equal(list, fleet.gather(list))
  end)

  it('replaces the session blocks with one fleet block at the position of the first', function()
    local first = message('m1')
    local list = { first, spawn('t2', 'h3'), message('m2'), read('t4', 'h3'), spawn('t5', 'h4') }
    local out = fleet.gather(list)

    eq({ 'm1', 'fleet:t2', 'm2' }, ids(out))
    eq(Block.KIND.fleet, out[2].kind)
    assert.are.equal(first, out[1])
  end)

  it('keeps the order of the blocks that are not absorbed', function()
    local list = {
      message('m1'),
      spawn('t2', 'h3'),
      message('m2'),
      read('t4', 'h3'),
      message('m3'),
    }

    eq({ 'm1', 'fleet:t2', 'm2', 'm3' }, ids(fleet.gather(list)))
  end)

  it('lists members in first-seen order, one row per member', function()
    local list = {
      spawn('t1', 'h3', { input = { agent = 'codex', prompt = 'review it' } }),
      spawn('t2', 'h4', { input = { agent = 'claude', prompt = 'check it' } }),
      read('t3', 'h3'),
    }
    local block = fleet.gather(list)[1]

    eq('fleet', block.kind)
    eq('fleet:t1', block.id)
    eq('fleet', block.name)
    eq({ '-> fleet', '   h3', '   h4' }, block.lines)
    eq({
      { key = 'h3', agent = 'codex', prompt = 'review it', spawned = true },
      { key = 'h4', agent = 'claude', prompt = 'check it', spawned = true },
    }, block.members)
    eq({ { 1, 2 } }, block.folds)
    eq(10, block.started)
  end)

  it('lists a member referenced by a read without spawning it', function()
    local block = fleet.gather({ read('t1', 'h3') })[1]

    eq({ { key = 'h3' } }, block.members)
    eq({ '-> fleet', '   h3' }, block.lines)
  end)

  it('marks a member spawned when a session_new for its key follows a read', function()
    local block = fleet.gather({ read('t1', 'h3'), spawn('t2', 'h3') })[1]

    eq({ { key = 'h3', spawned = true, agent = 'codex', prompt = 'review it' } }, block.members)
  end)

  it('reports the fleet block as in progress until every absorbed call settles', function()
    local running = fleet.gather({ spawn('t1', 'h3'), read('t2', 'h3', { status = 'in_progress', finished = nil }) })[1]
    local done = fleet.gather({ spawn('t1', 'h3'), read('t2', 'h3') })[1]
    local failed = fleet.gather({ spawn('t1', 'h3'), read('t2', 'h3', { status = 'failed', finished = 30 }) })[1]

    eq('in_progress', running.status)
    assert.is_nil(running.finished)
    eq('completed', done.status)
    eq(20, done.finished)
    eq('failed', failed.status)
    eq(30, failed.finished)
  end)

  it('does not absorb a session_new whose output has no session key', function()
    local not_json = spawn('t1', 'h3', { status = 'failed', output = 'boom' })
    local no_key = spawn('t2', nil, { status = 'failed', output = vim.json.encode({ error = 'nope' }) })
    local list = { not_json, no_key }

    assert.are.equal(list, fleet.gather(list))
    eq('new', fleet.verb(not_json))
  end)

  it('does not absorb session_list', function()
    eq({ 't1', 'fleet:t2' }, ids(fleet.gather({ call('list', 't1'), spawn('t2', 'h3') })))
  end)

  it('builds the digest from the snapshot, with a dash for members missing from it', function()
    local block = fleet.gather({ spawn('t1', 'h3'), read('t2', 'h4') })[1]

    eq('h3=d3;h4=-', fleet.digest(block, { h3 = { digest = 'd3' } }))
    eq('h3=-;h4=-', fleet.digest(block, nil))
    eq('h3=x;h4=y', fleet.digest(block, { h3 = { digest = 'x' }, h4 = { digest = 'y' } }))
  end)
end)
