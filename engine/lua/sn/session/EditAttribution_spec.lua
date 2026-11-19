local Connection = require('sn.servers.acp.Connection')
local Session = require('sn.session.Session')
local events = require('sn.types.events')
local fake_agent = require('sn.servers.acp.fake_agent')

local eq = assert.are.same

describe('sn.session.EditAttribution:', function()
  it('does not count an edit twice when the session dir is behind a symlink', function()
    local made = vim.fn.tempname()

    vim.fn.mkdir(made, 'p')

    local real = vim.uv.fs_realpath(made)
    local link = vim.fn.tempname()

    assert.is_true(vim.uv.fs_symlink(real, link))

    local session = Session({
      key = 'h1',
      id = 's1',
      dir = link,
      connection = Connection(fake_agent.new()),
    }):attach()

    session:_to('running')
    session:_emit(events.new({ kind = events.KIND.prompt, text = 'go' }))
    session:_emit(events.new({
      kind = events.KIND.tool_call,
      id = 't1',
      name = 'buffer_edit',
      status = 'in_progress',
      diffs = { { path = 'a.lua', old = 'a', new = 'b' } },
    }))

    eq(false, session:record_edit({ path = real .. '/a.lua', old = 'a', new = 'b' }))
    eq(1, #session.log:turn_tools()[1].diffs)
  end)
end)
