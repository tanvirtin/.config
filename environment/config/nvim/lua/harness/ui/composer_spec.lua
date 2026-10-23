local async = require('harness.async')
local composer = require('harness.ui.composer')
local fake_agent = require('harness.servers.acp.fake_agent')
local hub = require('harness.hub')
local jsonrpc = require('harness.servers.acp.jsonrpc')
local transcript = require('harness.ui.transcript')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function composers()
  return vim.tbl_filter(function(win)
    return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):find('harness://composer', 1, true) ~= nil
  end, vim.api.nvim_list_wins())
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

  it('opens as a fileless split along the bottom, naming its session', function()
    local above = vim.api.nvim_get_current_win()
    local element = composer.open(session)
    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()

    eq('', vim.api.nvim_win_get_config(win).relative)
    eq({ 'col', { { 'leaf', above }, { 'leaf', win } } }, vim.fn.winlayout())
    eq(require('harness.settings.composer'):get('height'), vim.api.nvim_win_get_height(win))
    eq(true, vim.wo[win].winfixheight)
    eq(composer.WINBAR, vim.wo[win].winbar)
    assert.is_truthy(composer.winbar():find(session.key, 1, true))
    eq('', vim.go.winbar)
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

  describe('a selection', function()
    local file

    before_each(function()
      file = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(file, '/w/a.lua')
      vim.api.nvim_buf_set_lines(file, 0, -1, false, { 'local a = 1', 'local b = 2', 'local c = 3' })
      vim.bo[file].filetype = 'lua'
    end)

    after_each(function()
      vim.api.nvim_buf_delete(file, { force = true })
    end)

    it('is not taken when no composer is open', function()
      eq(false, composer.attach(file, { 1, 2 }))
      eq({}, composer.attached(session))
    end)

    it('rides along with the next message, named in the winbar until sent', function()
      composer.open(session)
      eq(true, composer.attach(file, { 2, 3 }))
      eq(true, composer.attach(file, { 1, 1 }))
      assert.is_truthy(composer.winbar():find('+ /w/a.lua:2-3', 1, true))
      assert.is_truthy(composer.winbar():find('+ /w/a.lua:1 ', 1, true))

      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'explain' })
      press('<CR>')
      vim.wait(1000, function()
        return #prompts(fake) == 1
      end)

      local sent = vim.tbl_filter(function(message)
        return message.method == 'session/prompt'
      end, fake.sent)[1].params.prompt
      local texts = vim.tbl_map(function(block)
        return block.text or block.resource.text
      end, sent)

      assert.is_truthy(vim.tbl_contains(texts, 'local b = 2\nlocal c = 3') or texts[2]:find('local b = 2', 1, true))
      eq('explain', texts[#texts])
      eq(4, #sent)
      eq({}, composer.attached(session))
    end)

    it('is dropped last first, and with a discarded draft', function()
      composer.open(session)
      composer.attach(file, { 1, 1 })
      composer.attach(file, { 2, 2 })
      press('<C-x>')

      eq(
        { { 1, 1 } },
        vim.tbl_map(function(selection)
          return selection.range
        end, composer.attached(session))
      )

      composer.close(true)
      eq({}, composer.attached(session))
    end)

    it('is taken from a visual selection in another window', function()
      composer.open(session)
      vim.cmd('wincmd k')
      vim.api.nvim_win_set_buf(0, file)
      press('Vj')

      eq(true, composer.attach_visual())
      eq({ 1, 2 }, composer.attached(session)[1].range)
    end)

    it('leaves a visual selection alone when no composer is open', function()
      vim.api.nvim_win_set_buf(0, file)
      press('Vj')

      eq(false, composer.attach_visual())
      eq('V', vim.api.nvim_get_mode().mode)
      press('<Esc>')
    end)
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
    eq(1, #composers())

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'for the first' })

    local other = hub.start({ dir = '/w' }):wait()

    composer.open(other)
    eq(other, composer.target())
    eq({ '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

    composer.open(session)
    eq({ 'for the first' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('stays open when the user leaves it, like any window', function()
    local element = composer.open(session)

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'later' })
    vim.cmd('wincmd p')
    vim.wait(50)

    eq(true, composer.is_open())
    eq(element, composer.open(session))
    eq({ 'later' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('keeps the draft when its window is closed some other way', function()
    composer.open(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'closed with <C-w>c' })
    vim.wait(50)
    vim.cmd('wincmd p')
    vim.cmd('only')

    eq(false, composer.is_open())
    eq(0, #composers())

    composer.open(session)
    eq({ 'closed with <C-w>c' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('stays when the session buffer is closed, and sending shows it in a window of its own', function()
    local session_buf = vim.api.nvim_get_current_buf()

    composer.open(session)
    vim.cmd('bwipeout! ' .. session_buf)

    eq(true, composer.is_open())

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'still here?' })
    press('<CR>')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    local win = vim.api.nvim_get_current_win()

    eq({ 'still here?' }, prompts(fake))
    eq({ win }, vim.api.nvim_list_wins())
    eq(session, transcript.view().session)
    eq(false, vim.wo[win].winfixheight)
    eq(1, vim.wo[win].winbar:find(require('harness.ui.winbar').hints(), 1, true))
    assert.is_truthy(fake:sent_method('session/prompt').params.prompt[1].text:find('(bufnr ' .. code .. ')', 1, true))
  end)

  it('sends the reply to the window it came from when that is still open', function()
    local origin = vim.api.nvim_get_current_win()

    vim.cmd('enew')
    composer.open(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'over here' })
    press('<CR>')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    eq(origin, vim.api.nvim_get_current_win())
    eq(session, transcript.view().session)
    eq({ origin }, vim.api.nvim_list_wins())
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

  describe('while the agent works', function()
    local prompt_ids

    before_each(function()
      prompt_ids = {}
      hub.config.spawn = function()
        fake = fake_agent.new({
          ['session/prompt'] = function(message)
            prompt_ids[#prompt_ids + 1] = message.id
            return {}
          end,
          ['session/cancel'] = function()
            return { jsonrpc.result(prompt_ids[#prompt_ids], { stopReason = 'cancelled' }) }
          end,
        })
        return fake
      end
      hub.shutdown()
      session = hub.start({ dir = '/w' }):wait()
      transcript.open(session, { source_win = vim.api.nvim_get_current_win(), source_buf = code })
      hub.prompt(session, 'long running')
      vim.wait(500, function()
        return #prompt_ids == 1
      end)
    end)

    it('queues what you send, shows it, and sends it when the turn ends', function()
      composer.open(session)

      assert.is_truthy(composer.winbar():find('queue', 1, true))
      assert.is_truthy(composer.winbar():find('<C-c>', 1, true))

      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'next question' })
      press('<CR>')

      eq(false, composer.is_open())
      eq({ 'next question' }, session:queued())

      local buf = transcript.buffer_of(session)
      local Document = require('harness.ui.document')

      local function shown()
        local text = {}

        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, Document.STATUS_NAMESPACE, 0, -1, { details = true })) do
          for _, line in ipairs(mark[4].virt_lines or {}) do
            for _, chunk in ipairs(line) do
              text[#text + 1] = chunk[1]
            end
            text[#text + 1] = '\n'
          end
        end

        return table.concat(text)
      end

      vim.wait(500, function()
        return shown():find('queued next question', 1, true) ~= nil
      end)

      assert.is_truthy(shown():find('queued next question', 1, true))

      fake:push(jsonrpc.result(prompt_ids[1], { stopReason = 'end_turn' }))
      vim.wait(1000, function()
        return #prompt_ids == 2
      end)

      eq({ 'long running', 'next question' }, prompts(fake))
      eq({}, session:queued())
    end)

    it('interrupts on <C-c>, moving queued messages back into the composer', function()
      session:enqueue('queued one')

      local notify = vim.notify
      vim.notify = function() end

      composer.open(session)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'my draft' })
      press('<C-c>')
      vim.wait(200)
      vim.notify = notify

      eq('s1', fake:sent_method('session/cancel').params.sessionId)
      eq({ 'queued one', '', 'my draft' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
      eq({}, session:queued())
      eq(1, #prompt_ids)
    end)

    it('takes back queued messages however the turn is interrupted, even from the agent\'s session_cancel', function()
      local notify = vim.notify
      vim.notify = function() end

      session:enqueue('from the queue')
      session:cancel()
      vim.notify = notify

      composer.open(session)

      eq({ 'from the queue' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it('steers with <C-s>, falling back to the queue when the agent cannot steer', function()
      composer.open(session)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'change course' })
      press('<C-s>')

      eq({ 'change course' }, session:queued())
      eq(nil, composer.winbar(session):find('steer', 1, true))
    end)
  end)

  it('completes the agent\'s slash commands at the start of the message', function()
    session.commands = {
      { name = 'review', description = 'review changes', hint = 'branch' },
      { name = 'compact', description = 'summarize' },
    }
    composer.open(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '/re' })
    vim.api.nvim_win_set_cursor(0, { 1, 3 })

    eq(0, composer.complete(1, ''))
    eq({ { word = '/review ', abbr = '/review branch', menu = 'review changes' } }, composer.complete(0, '/re'))
    assert.is_truthy(composer.winbar():find('commands', 1, true))

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'not /a command' })
    vim.api.nvim_win_set_cursor(0, { 1, 8 })
    eq(-3, composer.complete(1, ''))
  end)

  it('opens from the session buffer\'s i', function()
    press('i')

    eq(true, composer.is_open())
    eq(session, composer.target())
  end)
end)
