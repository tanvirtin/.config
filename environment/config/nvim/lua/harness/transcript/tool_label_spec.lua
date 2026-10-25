local tool_label = require('harness.transcript.tool_label')

local eq = assert.are.same

describe('harness.transcript.tool_label:', function()
  local function label(state, dir)
    state.input = state.input or {}
    return { tool_label.label(state, 'id1', dir) }
  end

  it('names a tool and its main argument from the input', function()
    eq({ 'Bash', 'make test' }, label({ name = 'Bash', input = { command = 'make test' } }))
    eq({ 'Read', 'a.lua' }, label({ name = 'Read', input = { file_path = '/repo/a.lua' } }, '/repo'))
    eq({ 'Run', 'ls -la' }, label({ title = 'Run ls -la', input = { command = { 'ls', '-la' } } }))
  end)

  it('shortens MCP tool names and falls back to locations, then the title', function()
    eq(
      { 'nvim:buffer_read', 'a.lua' },
      label({ name = 'mcp__nvim__buffer_read', input = { path = '/repo/a.lua' } }, '/repo')
    )
    eq({ 'Reading', 'x.lua' }, label({ title = 'Reading', locations = { { path = '/repo/x.lua' } } }, '/repo'))
    eq({ 'Searching', 'for foo' }, label({ title = 'Searching for foo' }))
  end)

  it('keeps a shell command whole, and shortens other arguments', function()
    local long = string.rep('x', 200)

    eq(long, label({ name = 'Bash', category = 'execute', input = { command = long } })[2])
    eq(string.rep('x', 119) .. '…', label({ name = 'Read', category = 'read', input = { file_path = long } })[2])
  end)

  it('shows paths relative to the directory', function()
    eq('lua/a.lua', tool_label.relative('/repo/lua/a.lua', '/repo'))
    eq('.', tool_label.relative('/repo', '/repo'))
    eq(nil, tool_label.relative(nil, '/repo'))
  end)
end)
