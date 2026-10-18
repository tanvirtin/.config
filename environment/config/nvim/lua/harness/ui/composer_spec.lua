local async = require('harness.async')
local composer = require('harness.ui.composer')
local fake_agent = require('harness.fake_agent')
local hub = require('harness.hub')
local jsonrpc = require('harness.acp.jsonrpc')
local transcript = require('harness.ui.transcript')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function float_of(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then return win, vim.api.nvim_win_get_config(win) end
  end
end

local function prompts(fake)
  return vim.tbl_map(
    function(message)
      return message.params.prompt[#message.params.prompt].text
    end,
    vim.tbl_filter(function(message)
      return message.method == 'session/prompt'
    end, fake.sent)
  )
end

describe('harness.ui.composer:', function()
  local fake, session, code

  before_each(function()
    composer.close(true)
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
    hub.config.spawn = function()
      fake = fake_agent.new()
      return fake
    end
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    code = vim.api.nvim_get_current_buf()
    session = hub.start({ dir = '/w' }):wait()
    transcript.open(session, { source_win = vim.api.nvim_get_current_win(), source_buf = code })
  end)

  after_each(function()
    composer.close(true)
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
  end)

  it('opens as a fileless float along the bottom, naming its session', function()
    local element = composer.open(session)
    local buf = vim.api.nvim_get_current_buf()
    local _, config = float_of(buf)

    eq('editor', config.relative)
    assert.is_true(config.row + config.height >= vim.o.lines - 6)
    assert.is_truthy(config.title[1][1]:find(session.key, 1, true))
    eq('acwrite', vim.bo[buf].buftype)
    assert.is_truthy(vim.api.nvim_buf_get_name(buf):find('harness://composer', 1, true))
    eq(true, element:is_valid())
  end)

  it('sends on <CR> in normal mode, then clears and closes', function()
    local origin = vim.api.nvim_get_current_win()

    composer.open(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'rename x', 'to y' })
    press('<CR>')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    eq({ 'rename x\nto y' }, prompts(fake))
    eq(false, composer.is_open())
    eq(origin, vim.api.nvim_get_current_win())

    composer.open(session)
    eq({ '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('treats <CR> in insert mode as a newline', function()
    composer.open(session)
    press('ione<CR>two<Esc>')

    eq({ 'one', 'two' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    eq(true, composer.is_open())
    eq({}, prompts(fake))
  end)

  it('sends on :w', function()
    composer.open(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello' })
    vim.cmd('write')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    eq({ 'hello' }, prompts(fake))
    eq(false, composer.is_open())
  end)

  it('says where the user was, from the session\'s source buffer', function()
    composer.open(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'what is this?' })
    press('<CR>')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    local blocks = fake:sent_method('session/prompt').params.prompt

    assert.is_truthy(blocks[1].text:find('(bufnr ' .. code .. ')', 1, true))
  end)

  it('keeps a draft when closed with q, and an empty send just closes', function()
    composer.open(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'half a thought' })
    press('q')

    eq(false, composer.is_open())

    composer.open(session)
    eq({ 'half a thought' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '   ' })
    press('<CR>')

    eq(false, composer.is_open())
    eq({}, prompts(fake))
  end)

  it('is only ever one: opening again focuses it, another session moves it', function()
    local first = composer.open(session)

    vim.cmd('wincmd p')
    eq(first, composer.open(session))
    eq(1, #vim.tbl_filter(function(win)
      return vim.api.nvim_win_get_config(win).relative ~= ''
    end, vim.api.nvim_list_wins()))

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'for the first' })

    local other = hub.start({ dir = '/w' }):wait()

    composer.open(other)
    eq(other, composer.target())
    eq({ '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

    composer.open(session)
    eq({ 'for the first' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('closes when the user leaves it, keeping the draft', function()
    composer.open(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'later' })
    vim.cmd('wincmd p')
    vim.wait(200, function()
      return not composer.is_open()
    end)

    eq(false, composer.is_open())

    composer.open(session)
    eq({ 'later' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('stays when the session buffer is closed, and sending shows the buffer again', function()
    local origin = vim.api.nvim_get_current_win()
    local session_buf = vim.api.nvim_get_current_buf()

    composer.open(session)
    vim.cmd('bwipeout! ' .. session_buf)

    eq(true, composer.is_open())

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'still here?' })
    press('<CR>')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    eq({ 'still here?' }, prompts(fake))
    eq(origin, vim.api.nvim_get_current_win())
    eq(session, transcript.view().session)
    assert.is_truthy(fake:sent_method('session/prompt').params.prompt[1].text:find('(bufnr ' .. code .. ')', 1, true))
  end)

  it('keeps the draft when quit with :q', function()
    composer.open(session)
    press('ccwritten then quit<Esc>')
    vim.cmd('quit')
    vim.wait(200, function()
      return not composer.is_open()
    end)

    eq(false, composer.is_open())

    composer.open(session)
    eq({ 'written then quit' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('quits with :q even with text in it, and sends with :wq', function()
    composer.open(session)
    press('ccunsent<Esc>')

    vim.cmd('quit')
    eq(false, composer.is_open())

    composer.open(session)
    eq({ 'unsent' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

    vim.cmd('wq')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    eq({ 'unsent' }, prompts(fake))
    eq(false, composer.is_open())
  end)

  it('keeps the text and says so when the session has ended', function()
    local notify = vim.notify
    local warned

    vim.notify = function(message)
      warned = message
    end

    composer.open(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'anyone there?' })
    session.state = 'closed'
    press('<CR>')
    vim.wait(200, function()
      return warned ~= nil
    end)
    vim.notify = notify

    eq(true, composer.is_open())
    eq({ 'anyone there?' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    assert.is_truthy(warned:find('ended; your text is kept', 1, true))
    eq({}, prompts(fake))
  end)

  it('closes and drops the draft when the session is deleted', function()
    composer.open(session)
    press('ccto be dropped<Esc>')
    composer.forget(session)

    eq(false, composer.is_open())

    session.state = 'idle'
    composer.open(session)
    eq({ '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('keeps the text when the session cannot take it yet', function()
    hub.config.spawn = function()
      fake = fake_agent.new({
        ['session/prompt'] = function()
          return {}
        end,
      })
      return fake
    end
    hub.shutdown()
    session = hub.start({ dir = '/w' }):wait()
    hub.prompt(session, 'long running')

    local notify = vim.notify
    local warned

    vim.notify = function(message)
      warned = message
    end

    composer.open(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'next question' })
    press('<CR>')
    vim.wait(200, function()
      return warned ~= nil
    end)
    vim.notify = notify

    eq(true, composer.is_open())
    eq({ 'next question' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    assert.is_truthy(warned:find('already running', 1, true))
  end)

  it('opens from the session buffer\'s i', function()
    press('i')

    eq(true, composer.is_open())
    eq(session, composer.target())
  end)
end)
