local hub = require('harness.hub')
local async = require('harness.async')
local display = require('harness.ui.display')
local composer = require('harness.ui.composer')
local SideChats = require('harness.ui.SideChats')
local fake_agent = require('harness.servers.acp.fake_agent')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)

describe('harness.ui.SideChats:', function()
  local dir, spawned, chats, kept, shared

  local function walkthrough()
    return {
      title = 'Login',
      summary = 'How a login is checked.',
      steps = {
        { title = 'Entry', path = dir .. '/a.lua', line = 1, end_line = 2, note = 'Starts here.' },
        { title = 'Check', path = dir .. '/a.lua', line = 3, end_line = 3, note = '' },
      },
    }
  end

  local function wait_for(fn)
    vim.wait(3000, function()
      async.drain()
      return fn()
    end, 10)
  end

  before_each(function()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    dir = vim.uv.fs_realpath(vim.fn.tempname()) or vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    dir = vim.uv.fs_realpath(dir)
    vim.fn.writefile({ 'local function login()', '  return check()', 'end' }, dir .. '/a.lua')
    spawned, kept, shared = {}, {}, {}
    hub.config.spawn = function()
      local fake = fake_agent.new({ ['session/prompt'] = fake_agent.replying('Because it caches.') })

      spawned[#spawned + 1] = fake

      return fake
    end
    chats = SideChats(walkthrough(), {
      dir = dir,
      agent = 'claude',
      on_keep = function(step, text)
        kept[#kept + 1] = { step.title, text }
      end,
      on_share = function(step, text)
        shared[#shared + 1] = { step.title, text }
      end,
    })
  end)

  after_each(function()
    chats:close()
    composer.close(true)
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    vim.fn.delete(dir, 'rf')
  end)

  it('briefs a side chat with the plan, the step\'s code and its note, in its system prompt', function()
    local context = chats:context(1)

    assert.truthy(context:find(SideChats.SYSTEM, 1, true))
    assert.truthy(context:find('1. Entry\n2. Check', 1, true))
    assert.truthy(context:find('Step 1/2: Entry', 1, true))
    assert.truthy(context:find('local function login()\n  return check()', 1, true))
    assert.truthy(context:find('The note beside the code:\nStarts here.', 1, true))
  end)

  it('opens a hidden session in a transcript of its own, with the composer ready, one per step', function()
    assert.is_true(chats:open(1))

    local chat

    wait_for(function()
      chat = chats.chats[chats.walkthrough.steps[1]]
      return chat and chat.session and display.view_of(chat.session) ~= nil
    end)

    local session = chat.session
    local new = spawned[1]:sent_method('session/new').params

    eq({}, hub.sessions(dir))
    eq('Step 1: Entry', session.title)
    eq({}, new.mcpServers)
    assert.truthy(new.systemPrompt.content[1].text:find('Step 1/2: Entry', 1, true))
    assert.is_true(display.view_of(session):is_visible())
    assert.is_true(composer.is_open(session))

    chats:open(1)
    eq(1, spawned[1].sessions)
  end)

  it('keeps or shares the answer under the cursor, and forgets its transcripts when closed', function()
    chats:open(2)

    local chat

    wait_for(function()
      chat = chats.chats[chats.walkthrough.steps[2]]
      return chat and chat.session ~= nil and display.view_of(chat.session) ~= nil
    end)

    hub.send(chat.session, 'Why?')

    local view = display.view_of(chat.session)

    wait_for(function()
      return SideChats.answer_at(view, 0) ~= nil or SideChats.answer_at(view, 999) ~= nil
    end)

    eq('Because it caches.', SideChats.answer_at(view, 999))

    chats:keep(chat, view)
    chats:share(chat, view)

    eq({ { 'Check', 'Because it caches.' } }, kept)
    eq({ { 'Check', 'Because it caches.' } }, shared)

    chats:close()
    wait_for(function()
      return spawned[1]:sent_method('session/delete') ~= nil
    end)

    assert.is_nil(display.view_of(chat.session))
    assert.truthy(spawned[1]:sent_method('session/delete'))
  end)
end)
