local permission_rules = require('harness.permission_rules')

local eq = assert.are.same

local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(vim.split(text, '\n', { plain = true }), path)
end

local function read(path)
  return table.concat(vim.fn.readfile(path), '\n')
end

describe('harness.permission_rules:', function()
  local dir, agent

  before_each(function()
    dir = vim.fn.tempname()
    agent = {
      permission_rules = { format = 'claude', paths = { '.claude/settings.local.json', '.claude/missing.json' } },
    }
  end)

  it('has nothing for an agent that declares no rules, or a format it does not know', function()
    eq({ {}, {} }, { permission_rules.load({}, dir) })
    eq(false, permission_rules.supported({ permission_rules = { format = 'mystery', paths = { 'x' } } }))
    eq(true, permission_rules.supported(agent))
  end)

  it('reads each rule with its tool, scope and behaviour, from paths under the session directory', function()
    write(
      dir .. '/.claude/settings.local.json',
      '{"permissions": {"allow": ["Bash(npm test:*)", "mcp__nvim__lua"], "deny": ["Read(./.env)"]}}'
    )

    local rules = permission_rules.load(agent, dir)

    eq(
      {
        { 'allow', 'Bash', 'npm test:*' },
        { 'allow', 'mcp__nvim__lua', nil },
        { 'deny', 'Read', './.env' },
      },
      vim.tbl_map(function(rule)
        return { rule.behavior, rule.tool, rule.content }
      end, rules)
    )
    eq(vim.fs.normalize(dir .. '/.claude/settings.local.json'), rules[1].path)
  end)

  it('expands a path from home, and leaves an absolute one alone', function()
    agent.permission_rules.paths = { '~/x.json', '/etc/y.json', 'z.json' }

    eq(
      { vim.fs.normalize(vim.fn.expand('~/x.json')), '/etc/y.json', vim.fs.normalize(dir .. '/z.json') },
      permission_rules.paths(agent, dir)
    )
  end)

  it('reports a file it cannot read instead of failing', function()
    write(dir .. '/.claude/settings.local.json', '{ not json')

    local rules, problems = permission_rules.load(agent, dir)

    eq({}, rules)
    assert.truthy(problems[1]:find('not valid JSON', 1, true))
  end)

  it('removes one rule from its file and keeps everything else', function()
    local path = dir .. '/.claude/settings.local.json'
    local text =
      '{\n  "model": "opus",\n  "permissions": {\n    "allow": [\n      "Bash(npm test:*)",\n      "Grep"\n    ]\n  }\n}'

    write(path, text)

    local rule = permission_rules.load(agent, dir)[1]

    assert.is_true(permission_rules.remove(rule))
    eq('{\n  "model": "opus",\n  "permissions": {\n    "allow": [\n      "Grep"\n    ]\n  }\n}', read(path))
    eq({ nil, '"Bash(npm test:*)" is not in "permissions.allow"' }, { permission_rules.remove(rule) })
  end)
end)
