local Session = require('harness.Session')
local surfaces = require('surfaces')
local console = require('core.console')
local permission = require('harness.types.permission')
local Connection = require('harness.servers.acp.Connection')
local fake_agent = require('harness.servers.acp.fake_agent')
local PermissionsView = require('harness.ui.PermissionsView')

local eq = assert.are.same

local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(vim.split(text, '\n', { plain = true }), path)
end

local function first_rule(session)
  return require('harness.permission_rules').load(session.agent, session.dir)[1]
end

local function text(lines)
  return table.concat(lines, '\n')
end

describe('harness.ui.PermissionsView:', function()
  local dir, session

  before_each(function()
    vim.cmd('silent! only!')
    dir = vim.fn.tempname()
    write(
      dir .. '/.claude/settings.local.json',
      '{\n  "permissions": {\n    "allow": [\n      "Bash(npm test:*)"\n    ],\n    "deny": [\n      "Read(./.env)"\n    ]\n  }\n}'
    )
    session = Session({
      key = 'hp' .. math.random(1e6),
      id = 's1',
      dir = dir,
      agent = { permission_rules = { format = 'claude', paths = { '.claude/settings.local.json' } } },
      connection = Connection(fake_agent.new()),
    })
    session.permissions.state:grant('mcp__nvim__lua')
    session.permissions.state:record({
      tool = 'Bash',
      kind = 'allow_always',
      title = 'npm test',
      label = 'Yes, and don\'t ask again',
    })
    session.permissions.state:record({ tool = 'Edit', kind = 'reject_once', title = 'Edit a.lua', label = 'No' })
  end)

  after_each(function()
    surfaces.close_all()
  end)

  it('shows the grants, the saved rules and the decisions, newest first', function()
    local lines = PermissionsView.render(PermissionsView.model(session))
    local shown = text(lines)

    assert.truthy(shown:find('Mode: the agent has none', 1, true))
    assert.truthy(shown:find('Allowed for this session (1)\n  ✓ mcp__nvim__lua', 1, true))
    assert.truthy(shown:find('Saved by the agent (2)\n  allow Bash(npm test:*)', 1, true))
    assert.truthy(shown:find('  deny  Read(./.env)', 1, true))
    assert.truthy(shown:find('Decisions (2)\n  refused   Edit a.lua  No', 1, true))
    assert.truthy(shown:find('  always    npm test  Yes, and don\'t ask again', 1, true))
  end)

  it('says when an agent does not say where it saves its rules', function()
    session.agent = {}

    local shown = text(PermissionsView.render(PermissionsView.model(session)))

    assert.truthy(shown:find('Saved by the agent (0)\n  this agent does not say where it saves its rules', 1, true))
  end)

  it('revokes the grant under the cursor with d', function()
    local view = surfaces.add(PermissionsView(session)):open()
    local lines = view:refresh()

    for lnum, line in ipairs(lines) do
      if line:find('mcp__nvim__lua', 1, true) then view._body:set_lnum(lnum) end
    end

    vim.api.nvim_feedkeys('d', 'x', false)

    eq({}, session.permissions:grants())
    assert.truthy(text(view:refresh()):find('Allowed for this session (0)', 1, true))
  end)

  it('deletes the saved rule under the cursor once confirmed, from its file', function()
    local original = console.select
    local asked

    console.select = function(items, opts, on_choice)
      asked = opts.prompt
      on_choice(items[1])
    end

    local view = surfaces.add(PermissionsView(session)):open()

    for lnum, line in ipairs(view:refresh()) do
      if line:find('Bash(npm test:*)', 1, true) then view._body:set_lnum(lnum) end
    end

    local ok, err = pcall(vim.api.nvim_feedkeys, 'd', 'x', false)

    console.select = original

    assert(ok, err)
    assert.truthy(asked:find('Delete allow "Bash(npm test:*)"', 1, true))
    eq(
      { allow = {}, deny = { 'Read(./.env)' } },
      vim.json.decode(table.concat(vim.fn.readfile(dir .. '/.claude/settings.local.json'), '\n')).permissions
    )
    assert.truthy(text(view:refresh()):find('Saved by the agent (1)', 1, true))
  end)

  it('keeps the rule when the deletion is not confirmed', function()
    local original = console.select

    console.select = function(items, _, on_choice)
      on_choice(items[2])
    end

    local view = PermissionsView(session)

    view:delete(first_rule(session))
    console.select = original

    eq(2, #require('harness.permission_rules').load(session.agent, dir))
  end)

  it('follows the session as decisions arrive', function()
    local view = surfaces.add(PermissionsView(session)):open()

    session.permissions.state:grant('mcp__nvim__ex')
    session:_notify({ kind = require('harness.types.events').NOTICE.permissions })

    local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')

    assert.truthy(shown:find('Allowed for this session (2)', 1, true))
    view:close()
    assert.is_false(view:is_open())
  end)

  it('lets an agent read it and revoke, but say when there is nothing to revoke', function()
    local view = surfaces.add(PermissionsView(session)):open()

    assert.truthy(view:snapshot():find('mcp__nvim__lua', 1, true))
    view:command('revoke', { tool = 'mcp__nvim__lua' })
    eq({}, session.permissions:grants())
    eq(
      { false, 'mcp__nvim__lua is not allowed for this session' },
      { pcall(view.command, view, 'revoke', { tool = 'mcp__nvim__lua' }) }
    )
  end)
end)
