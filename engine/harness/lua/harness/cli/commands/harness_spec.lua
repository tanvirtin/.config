local harness = require('harness')
local command = require('harness.cli.commands.harness').command

local eq = assert.are.same

describe('harness.cli.commands.harness:', function()
  local called, saved

  local function run(text, extra)
    command.execute(vim.tbl_extend('force', { args = text, range = 0 }, extra or {}))
  end

  before_each(function()
    called, saved = {}, {}

    local function record(owner, name)
      saved[#saved + 1] = { owner, name, owner[name] }
      owner[name] = function(...)
        called[#called + 1] = { name, ... }
      end
    end

    for _, name in ipairs(harness.VERBS) do
      record(harness, name)
    end
  end)

  after_each(function()
    for _, entry in ipairs(saved) do
      entry[1][entry[2]] = entry[3]
    end
  end)

  it('opens the sessions selector when it is run bare, as the one thing worth a bare command', function()
    run('')

    eq({ { 'switch' } }, called)
  end)

  it('asks with the rest of the line, and with the lines of a range', function()
    run('ask what is wrong here?')
    run('ask explain this', { range = 2, line1 = 4, line2 = 9 })

    eq({ 'ask', 'what is wrong here?', { range = nil } }, called[1])
    eq({ 'ask', 'explain this', { range = { 4, 9 } } }, called[2])
  end)

  it('does not take a prompt for a command just because its first word is one', function()
    run('new feature please')

    eq({ 'new', { agent = 'feature please' } }, called[1])
  end)

  it('passes a scope to revert and quickfix, and an agent to new', function()
    run('revert turn')
    run('quickfix')
    run('new opencode')

    eq({ { 'revert', 'turn' }, { 'quickfix', '' }, { 'new', { agent = 'opencode' } } }, called)
  end)

  it('says which commands there are when the first word is none of them', function()
    local notice = require('harness.ui.notice')
    local warn, said = notice.warn, nil

    notice.warn = function(message)
      said = message
    end
    run('frobnicate')
    notice.warn = warn

    assert.truthy(said:find('no Harness command "frobnicate"', 1, true))
    assert.truthy(said:find('permissions', 1, true))
    eq({}, called)
  end)

  it('completes the commands, then the words each one takes', function()
    eq(command.names(), command.complete('', 'Harness '))
    eq({ 'waiting' }, command.complete('wa', 'Harness wa'))
    eq({ 'edit', 'session', 'turn' }, command.complete('', 'Harness revert '))
  end)

  it('names every public verb as a command, and every command as a verb', function()
    local names = command.names()

    for _, verb in ipairs(harness.VERBS) do
      if verb ~= 'attach' then assert.truthy(vim.tbl_contains(names, verb), verb .. ' has no :Harness command') end
    end

    for _, name in ipairs(names) do
      assert.truthy(vim.tbl_contains(harness.VERBS, name), name .. ' is not a verb')
    end
  end)
end)
