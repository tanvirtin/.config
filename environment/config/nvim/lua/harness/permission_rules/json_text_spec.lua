local json_text = require('harness.permission_rules.json_text')

local eq = assert.are.same

local SETTINGS = table.concat({
  '{',
  '  "model": "opus",',
  '  "permissions": {',
  '    "allow": [',
  '      "Bash(npm test:*)",',
  '      "WebFetch(domain:example.com)",',
  '      "mcp__nvim__lua"',
  '    ],',
  '    "deny": ["Read(./.env)"]',
  '  },',
  '  "hooks": { "note": "a \\"quoted\\" ] bracket" }',
  '}',
}, '\n')

describe('harness.permission_rules.json_text:', function()
  it('removes the first element, keeping the rest of the file as it was', function()
    local out = json_text.remove(SETTINGS, { 'permissions', 'allow' }, 'Bash(npm test:*)')

    eq(SETTINGS:gsub('      "Bash%(npm test:%*%)",\n', ''), out)
  end)

  it('removes a middle element', function()
    local out = json_text.remove(SETTINGS, { 'permissions', 'allow' }, 'WebFetch(domain:example.com)')

    eq(SETTINGS:gsub('      "WebFetch%(domain:example.com%)",\n', ''), out)
  end)

  it('removes the last element, taking the comma before it', function()
    local out = json_text.remove(SETTINGS, { 'permissions', 'allow' }, 'mcp__nvim__lua')

    assert.truthy(out:find('"WebFetch(domain:example.com)"\n    ],', 1, true))
    eq(SETTINGS:gsub(',\n      "mcp__nvim__lua"', ''), out)
  end)

  it('leaves an empty list when it removes the only element', function()
    local out = json_text.remove(SETTINGS, { 'permissions', 'deny' }, 'Read(./.env)')

    assert.truthy(out:find('"deny": []', 1, true))
    eq(vim.json.decode(SETTINGS).hooks, vim.json.decode(out).hooks)
  end)

  it('keeps strings with brackets and escaped quotes intact around it', function()
    local out = json_text.remove(SETTINGS, { 'permissions', 'allow' }, 'mcp__nvim__lua')

    eq('a "quoted" ] bracket', vim.json.decode(out).hooks.note)
  end)

  it('says what is missing rather than guessing', function()
    eq(
      { nil, '"Grep" is not in "permissions.allow"' },
      { json_text.remove(SETTINGS, { 'permissions', 'allow' }, 'Grep') }
    )
    eq({ nil, 'the file has no "permissions.ask"' }, { json_text.remove(SETTINGS, { 'permissions', 'ask' }, 'x') })
    eq({ nil, '"model" is not a list' }, { json_text.remove(SETTINGS, { 'model' }, 'x') })
    eq({ nil, 'the file is not a JSON object' }, { json_text.remove('[1]', { 'a' }, 'x') })
  end)
end)
