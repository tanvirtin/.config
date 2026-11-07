local hub = require('harness.hub')
local async = require('harness.async')
local jsonrpc = require('harness.servers.acp.jsonrpc')
local fake_agent = require('harness.servers.acp.fake_agent')
local WalkthroughReader = require('harness.WalkthroughReader')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)

describe('harness.WalkthroughReader:', function()
  local spawned, prompts

  local function walkthrough()
    return {
      title = 'Login',
      summary = 'How a login is checked.',
      root = '/w',
      steps = {
        { title = 'Entry', path = '/w/a.lua', line = 2, end_line = 3, note = '' },
        { title = 'Check', path = '/w/b.lua', line = 1, end_line = 1, note = '' },
        { title = 'Given', path = '/w/b.lua', line = 1, end_line = 1, note = 'Already written.' },
      },
    }
  end

  before_each(function()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
    spawned, prompts = {}, {}
    hub.config.spawn = function()
      local fake = fake_agent.new({
        ['session/prompt'] = function(message)
          local text = message.params.prompt[#message.params.prompt].text

          prompts[#prompts + 1] = text

          return {
            fake_agent.chunk(message.params.sessionId, 'Note for ' .. text:match('Step (%d+)')),
            jsonrpc.result(message.id, { stopReason = 'end_turn' }),
          }
        end,
      })

      spawned[#spawned + 1] = fake

      return fake
    end
  end)

  after_each(function()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
  end)

  describe('the prompt', function()
    local function read(path)
      return path == '/w/a.lua' and { 'one', 'two', 'three', 'four' } or { 'b' }
    end

    it('briefs the reader once with the plan, then gives the step and its code', function()
      local text = WalkthroughReader.prompt(walkthrough(), 1, read, { brief = true })

      eq({
        'Walkthrough: Login',
        'How a login is checked.',
        'Steps:',
        '1. Entry',
        '2. Check',
        '3. Given',
        '',
        'Step 1/3: Entry',
        'a.lua:2-3',
        '```lua',
        'two',
        'three',
        '```',
      }, vim.split(text, '\n', { plain = true }))
      assert.falsy(WalkthroughReader.prompt(walkthrough(), 2, read):find('Steps:', 1, true))
    end)

    it('gives a step of a review as its diff', function()
      local data = walkthrough()

      data.scope = {
        files = {
          {
            path = 'a.lua',
            absolute = '/w/a.lua',
            hunks = { { id = 'h1', path = 'a.lua', first = 2, last = 2, lines = { '-old', '+new' } } },
          },
        },
      }

      local text = WalkthroughReader.prompt(data, 1, read)

      assert.truthy(text:find('a.lua:2-2\n```diff\n-old\n+new\n```', 1, true))
    end)
  end)

  it('writes a note on a hidden session with the reader prompt, and keeps it on the step', function()
    local data = walkthrough()
    local reader = WalkthroughReader(data, { dir = '/w', agent = 'claude' })
    local got

    reader:note(1, function(note)
      got = note
    end)

    vim.wait(2000, function()
      return got ~= nil
    end)

    eq('Note for 1', got)
    eq('Note for 1', data.steps[1].note)
    eq({}, hub.sessions('/w'))
    eq(WalkthroughReader.SYSTEM, spawned[1]:sent_method('session/new').params.systemPrompt.content[1].text)
    eq('claude-haiku-5-5', spawned[1]:sent_method('session/set_config_option').params.value)

    reader:close()
  end)

  it('writes the step the user is on before the ones it fetches ahead, and never a note it was given', function()
    local data = walkthrough()
    local reader = WalkthroughReader(data, { dir = '/w', agent = 'claude' })
    local given

    reader:note(2)
    reader:note(1, function() end)
    reader:note(3, function(note)
      given = note
    end)

    vim.wait(2000, function()
      return data.steps[2].note ~= ''
    end)

    eq('Already written.', given)
    eq({ 'Note for 1', 'Note for 2' }, { data.steps[1].note, data.steps[2].note })
    eq(2, #prompts)
    assert.truthy(prompts[1]:find('Step 1/3', 1, true))

    reader:close()
  end)

  it('deletes its session when the walkthrough ends', function()
    local data = walkthrough()
    local reader = WalkthroughReader(data, { dir = '/w', agent = 'claude' })

    reader:note(1, function() end)

    vim.wait(2000, function()
      return data.steps[1].note ~= ''
    end)

    reader:close()
    async.drain()

    vim.wait(1000, function()
      return spawned[1]:sent_method('session/delete') ~= nil
    end)

    assert.truthy(spawned[1]:sent_method('session/delete'))
  end)
end)
