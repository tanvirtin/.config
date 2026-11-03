local async = require('harness.async')
local composer = require('harness.ui.composer')
local commands = require('harness.ui.commands')
local ComposerView = require('harness.ui.ComposerView')
local fake_agent = require('harness.servers.acp.fake_agent')
local hub = require('harness.hub')
local jsonrpc = require('harness.servers.acp.jsonrpc')
local transcript = require('harness.ui.transcript')
local display = require('harness.ui.display')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)

local function open_composer(session, opts)
  opts = opts or {}
  opts.display = display

  return composer.open(session, opts)
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function input(session)
  local view = composer.view(session)

  return view and view:lines() or {}
end

local function marks(buf)
  local bufnr = buf or vim.api.nvim_get_current_buf()

  return vim.api.nvim_buf_get_extmarks(bufnr, ComposerView.NAMESPACE, 0, -1, { details = true })
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
    composer.register_events()
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

  describe('dressing', function()
    local function chunks(buf)
      local out = {}

      for _, mark in ipairs(marks(buf)) do
        if mark[4].virt_text then out[#out + 1] = { mark[4].virt_text[1][1], mark[4].virt_text_pos } end
      end

      return out
    end

    it('says what to type while the input is empty', function()
      open_composer(session)

      local buf = vim.api.nvim_get_current_buf()
      local placeholder

      for _, chunk in ipairs(chunks(buf)) do
        if chunk[2] == 'eol' then placeholder = chunk end
      end

      assert.is_truthy(placeholder[1]:find('ask anything', 1, true))
      eq('eol', placeholder[2])
    end)

    it('drops the placeholder once there is text', function()
      open_composer(session)

      local buf = vim.api.nvim_get_current_buf()

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello' })
      vim.wait(200, function()
        return #chunks(buf) == 0
      end)

      eq(0, #chunks(buf))
    end)

    it('counts the characters and lines written in the winbar', function()
      open_composer(session)

      local buf = vim.api.nvim_get_current_buf()

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'héllo', 'x' })
      vim.wait(100)

      local bar = composer.winbar()

      assert.is_truthy(bar:find('7c 2l', 1, true))
    end)

    it('keeps the key hints in the winbar, out of the text', function()
      open_composer(session)

      local overlays = vim.tbl_filter(function(mark)
        return mark[4].virt_text_pos == 'overlay'
      end, marks())

      eq(0, #overlays)
      eq({ '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
      assert.is_truthy(composer.winbar():find('send', 1, true))
      assert.is_truthy(composer.winbar():find('send', 1, true) < composer.winbar():find('%=', 1, true))
    end)

    it('draws its markdown like the transcript, and a reference to a file as a chip', function()
      local Renderer = require('ui.markdown.Renderer')
      local path = vim.fn.tempname() .. '.lua'

      vim.fn.writefile({ 'x' }, path)
      open_composer(session)

      local buf = vim.api.nvim_get_current_buf()

      eq('harness_composer', vim.bo[buf].filetype)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'fix **this** in @' .. path .. ' for @someone' })
      vim.wait(200, function()
        return #vim.api.nvim_buf_get_extmarks(buf, Renderer.NAMESPACE, 0, -1, {}) > 0
      end)

      local chips = vim.tbl_filter(function(mark)
        return mark[4].hl_group == 'UiChip'
      end, marks(buf))

      eq(1, #chips)
      eq(('fix **this** in '):len(), chips[1][3])
      assert.is_truthy(#vim.api.nvim_buf_get_extmarks(buf, Renderer.NAMESPACE, 0, -1, {}) > 0)
      vim.fn.delete(path)
    end)

    it('draws only what is in sight and a margin of a long draft, and the rest on scrolling', function()
      local Renderer = require('ui.markdown.Renderer')
      local draft = {}

      for i = 1, 400 do
        draft[i] = '**line ' .. i .. '**'
      end

      open_composer(session)

      local buf = vim.api.nvim_get_current_buf()

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, draft)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      composer.view(session):_decorate()

      local function drawn()
        local rows = {}

        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, Renderer.NAMESPACE, 0, -1, {})) do
          rows[mark[2]] = true
        end

        return rows
      end

      assert.is_truthy(drawn()[0])
      assert.is_nil(drawn()[300])

      vim.api.nvim_win_set_cursor(0, { 300, 0 })
      vim.cmd('normal! zt')
      composer.view(session):_decorate()
      assert.is_truthy(drawn()[300])
    end)

    it('says how to send from the mode you are in', function()
      local Window = require('core.Window')
      local real = Window.inserting

      open_composer(session)
      Window.inserting = function()
        return true
      end

      local typing = composer.view(session):hints_text()

      Window.inserting = real
      vim.cmd('stopinsert')

      assert.is_truthy(typing:find('<Esc><CR>', 1, true))
      eq(nil, typing:find('close', 1, true))

      local normal = composer.view(session):hints_text()

      eq(nil, normal:find('<Esc>', 1, true))
      assert.is_truthy(normal:find('close', 1, true))
    end)

    for _, case in ipairs({
      { 'clearing it', 'ggdG' },
      { 'deleting the empty line', 'dd' },
      { 'undoing past the start', 'ihi<Esc>uu' },
    }) do
      it('stays an empty input with its placeholder after ' .. case[1], function()
        open_composer(session)
        vim.cmd('stopinsert')
        press(case[2])
        vim.wait(100)

        eq({ '' }, input(session))
        eq({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
        assert.is_truthy(vim.tbl_filter(function(mark)
          return mark[4].virt_text_pos == 'eol'
        end, marks())[1])
      end)
    end

    it('completes a file reference after @ at the start of a word', function()
      local cwd = vim.fn.getcwd()
      local dir = vim.fn.resolve(vim.fn.tempname())

      vim.fn.mkdir(dir .. '/lua', 'p')
      vim.fn.writefile({}, dir .. '/lua/a.lua')
      vim.fn.writefile({}, dir .. '/my file.lua')
      vim.cmd.cd(dir)
      open_composer(session)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'read @lu' })
      vim.api.nvim_win_set_cursor(0, { 1, 8 })

      eq(5, composer.complete(1, ''))

      local words = vim.tbl_map(function(item)
        return item.word
      end, composer.complete(0, '@lua/').words)

      eq({ '@lua/a.lua' }, words)
      eq(
        { '@"my file.lua"' },
        vim.tbl_map(function(item)
          return item.word
        end, composer.complete(0, '@my').words)
      )

      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'me@lu' })
      vim.api.nvim_win_set_cursor(0, { 1, 5 })
      eq(-3, composer.complete(1, ''))

      vim.cmd.cd(cwd)
      vim.fn.delete(dir, 'rf')
    end)

    it('shows what is typed on the first line', function()
      open_composer(session)
      vim.cmd('stopinsert')
      press('ggihello<Esc>')
      vim.wait(100)

      eq({ 'hello' }, input(session))
      eq(0, #marks())
    end)

    it('sits on its own surface and keeps the counts after the truncation point', function()
      open_composer(session)

      local win = vim.api.nvim_get_current_win()

      assert.is_truthy(vim.wo[win].winhl:find('Normal:UiComposer', 1, true))
      assert.is_truthy(composer.winbar():find('%=%<', 1, true))
    end)

    it('leaves the session name, title and mode to the transcript it sits under', function()
      session.title = 'A session with a long name'
      open_composer(session)

      local bar = composer.view(session):winbar()

      eq(nil, bar:find(session.key, 1, true))
      eq(nil, bar:find('A session with a long name', 1, true))
    end)
  end)

  it('opens as a fileless split along the bottom', function()
    local above = vim.api.nvim_get_current_win()
    local element = open_composer(session)
    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()

    eq('', vim.api.nvim_win_get_config(win).relative)
    eq({ 'col', { { 'leaf', above }, { 'leaf', win } } }, vim.fn.winlayout())
    assert.is_true(vim.api.nvim_win_get_height(win) < require('harness.settings.composer'):get('height'))
    vim.wait(1000, function()
      return vim.api.nvim_win_get_height(win) == require('harness.settings.composer'):get('height')
    end)
    eq(require('harness.settings.composer'):get('height'), vim.api.nvim_win_get_height(win))
    eq(true, vim.wo[win].winfixheight)
    eq(composer.WINBAR, vim.wo[win].winbar)
    eq('', vim.go.winbar)
    eq('acwrite', vim.bo[buf].buftype)
    assert.is_truthy(vim.api.nvim_buf_get_name(buf):find('harness://composer', 1, true))
    eq(true, element:is_valid())
  end)

  it('stops growing when it is closed halfway, and opens at once with no ease', function()
    local settings = require('harness.settings.composer')
    open_composer(session)

    local view = composer.view()

    assert.is_true(view.animator:is_running())
    composer.close(true)
    async.drain()
    eq(0, view.animator:count())
    eq(false, view.animator:is_running())

    settings:assign({ ease_ms = 0 })
    open_composer(session)

    eq(settings:get('height'), vim.api.nvim_win_get_height(vim.api.nvim_get_current_win()))
    settings:assign({ ease_ms = 120 })
  end)

  it('leaves the global window defaults alone', function()
    local number, cursorline = vim.go.number, vim.go.cursorline

    vim.go.number, vim.go.cursorline = true, true
    open_composer(session)

    local after_number, after_cursorline = vim.go.number, vim.go.cursorline

    vim.go.number, vim.go.cursorline = number, cursorline

    eq(true, after_number)
    eq(true, after_cursorline)
  end)

  it('opens without moving a transcript that was scrolled up', function()
    local events = require('harness.types.events')

    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = transcript.view_of(session)
    local win = vim.api.nvim_get_current_win()

    view:render()
    vim.cmd('normal! 6\25')

    local top = vim.fn.line('w0', win)

    open_composer(session)
    vim.wait(100)

    eq(true, composer.is_open())
    -- a wrapped bottom line can cost a row
    assert.is_true(math.abs(vim.fn.line('w0', win) - top) <= 1)

    composer.close(true)
    vim.wait(100)

    assert.is_true(math.abs(vim.fn.line('w0', win) - top) <= 1)
  end)

  for _, hint in ipairs({ false, true }) do
    it('anchors the transcript on send, hints ' .. tostring(hint), function()
      local events = require('harness.types.events')
      local settings = require('harness.settings.transcript')
      local saved = settings:get('hints')

      settings:assign({ hints = hint })
      for i = 1, 60 do
        session:_emit(events.prompt('turn ' .. i))
        session:_emit(events.new({ kind = events.KIND.message, text = 'reply ' .. i }))
      end

      local view = transcript.view_of(session)
      local win = vim.api.nvim_get_current_win()

      view:render()
      vim.cmd('normal! G')
      vim.wait(100)
      vim.cmd('normal! 20\25')
      vim.wait(300)

      open_composer(session)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'new prompt' })
      press('<CR>')
      vim.wait(1000, function()
        return #prompts(fake) == 1
      end)
      vim.wait(300)

      for i = 1, 40 do
        session:_emit(events.new({ kind = events.KIND.message, text = 'streamed line ' .. i .. '\n\n' }))
        vim.wait(40)
      end
      vim.wait(300)

      local last = vim.api.nvim_buf_line_count(view.bufnr)
      local bottom = vim.fn.line('w$', win)

      settings:assign({ hints = saved })
      assert.is_true(last - bottom <= 1)
    end)
  end

  it('anchors a hidden transcript when sending from code', function()
    local events = require('harness.types.events')

    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
      session:_emit(events.new({ kind = events.KIND.message, text = 'reply ' .. i }))
    end

    local view = transcript.view_of(session)

    view:render()
    vim.cmd('normal! G')
    vim.cmd('normal! 20\25')
    vim.wait(300)
    vim.cmd('buffer ' .. code)

    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'new prompt' })
    press('<CR>')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)
    vim.wait(300)

    for i = 1, 40 do
      session:_emit(events.new({ kind = events.KIND.message, text = 'streamed line ' .. i .. '\n\n' }))
      vim.wait(40)
    end
    vim.wait(300)

    local win = vim.fn.bufwinid(view.bufnr)
    local last = vim.api.nvim_buf_line_count(view.bufnr)

    assert.is_true(last - vim.fn.line('w$', win) <= 1)
  end)

  it('keeps following when the composer closes over folded output', function()
    local events = require('harness.types.events')

    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
      session:_emit(events.new({ kind = events.KIND.message, text = 'reply ' .. i }))
    end

    local view = transcript.view_of(session)
    local win = vim.api.nvim_get_current_win()

    view:render()
    vim.cmd('normal! G')
    vim.wait(100)

    local function tool(i)
      session:_emit(events.new({
        kind = events.KIND.tool_call,
        id = 't' .. i,
        name = 'Bash',
        status = 'completed',
        output = table.concat(vim.tbl_map(tostring, vim.fn.range(1, 30)), '\n'),
      }))
      vim.wait(60)
    end

    tool(1)
    tool(2)
    open_composer(session)
    vim.wait(100)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'send' })
    press('<CR>')
    vim.wait(300)

    for i = 3, 6 do
      tool(i)
    end

    vim.wait(300)
    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.fn.line('w$', win))
  end)

  describe('anchoring a send', function()
    local events = require('harness.types.events')

    local function reply_lines()
      for i = 1, 60 do
        session:_emit(events.prompt('turn ' .. i))
        session:_emit(events.new({ kind = events.KIND.message, text = 'reply ' .. i }))
      end
    end

    local function stream(from, to)
      for i = from, to do
        session:_emit(events.new({ kind = events.KIND.message, text = 'streamed ' .. i .. '\n\n' }))
        vim.wait(30)
      end
    end

    local function send(text, count)
      open_composer(session)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
      press('<CR>')
      vim.wait(1000, function()
        return #prompts(fake) == count
      end)
      vim.wait(150)
    end

    local function gap(view)
      local win = vim.fn.bufwinid(view.bufnr)

      return vim.api.nvim_buf_line_count(view.bufnr) - vim.fn.line('w$', win)
    end

    local SCROLLS = {
      { 'a single row up', '1\25' },
      { 'a page up', '\21' },
      { 'to the top', 'gg' },
    }

    for _, scroll in ipairs(SCROLLS) do
      it('lands and follows after scrolling ' .. scroll[1] .. ' before the composer opened', function()
        reply_lines()

        local view = transcript.view_of(session)

        view:render()
        vim.cmd('normal! G')
        vim.wait(100)
        vim.cmd('normal! ' .. scroll[2])
        vim.wait(250)
        send('go', 1)
        stream(1, 20)
        vim.wait(250)

        assert.is_true(gap(view) <= 1)
      end)
    end

    it('lands and follows after a wheel scroll', function()
      reply_lines()

      local view = transcript.view_of(session)

      view:render()
      vim.cmd('normal! G')
      vim.wait(100)
      vim.api.nvim_input_mouse('wheel', 'up', '', 0, 3, 3)
      vim.wait(250)
      send('go', 1)
      stream(1, 20)
      vim.wait(250)

      assert.is_true(gap(view) <= 1)
    end)

    it('lands a second send made while the first reply streams, after the reader scrolled up', function()
      reply_lines()

      local view = transcript.view_of(session)
      local win = vim.api.nvim_get_current_win()

      view:render()
      vim.cmd('normal! G')
      vim.wait(100)
      send('first', 1)
      stream(1, 15)
      vim.api.nvim_win_call(win, function()
        vim.cmd('normal! 10\25')
      end)
      vim.wait(250)
      stream(16, 25)
      send('second', 2)
      stream(26, 45)
      vim.wait(250)

      assert.is_true(gap(view) <= 1)
    end)

    it('keeps following the reply when the composer closes over a wrapped, folded transcript', function()
      for i = 1, 40 do
        session:_emit(events.prompt('turn ' .. i))
        session:_emit(events.new({ kind = events.KIND.message, text = string.rep('word ', 60) }))
      end

      local view = transcript.view_of(session)

      view:render()
      vim.cmd('normal! G')
      vim.wait(100)
      send('go', 1)

      for i = 1, 6 do
        session:_emit(events.new({
          kind = events.KIND.tool_call,
          id = 'w' .. i,
          name = 'Bash',
          status = 'completed',
          output = table.concat(vim.tbl_map(tostring, vim.fn.range(1, 45)), '\n'),
        }))
        vim.wait(60)
      end

      vim.wait(250)
      assert.is_true(gap(view) <= 1)
    end)
  end)

  it('keeps focus where the composer was opened from, not on the transcript', function()
    vim.cmd('vsplit')
    vim.api.nvim_win_set_buf(0, code)

    local origin = vim.api.nvim_get_current_win()

    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'look here' })
    press('<CR>')

    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    eq(origin, vim.api.nvim_get_current_win())
    eq(code, vim.api.nvim_win_get_buf(origin))
  end)

  it('sends on <CR> in normal mode, then clears and closes', function()
    local origin = vim.api.nvim_get_current_win()

    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'rename x', 'to y' })
    press('<CR>')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    eq({ 'rename x\nto y' }, prompts(fake))
    eq(false, composer.is_open())
    eq(origin, vim.api.nvim_get_current_win())

    open_composer(session)
    eq({ '' }, input(session))
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
    end)

    it('inserts a reference token at the cursor', function()
      open_composer(session)
      eq(true, composer.attach(file, { 2, 3 }))

      assert.is_truthy(table.concat(input(session), '\n'):find('@/w/a.lua:2-3', 1, true))
    end)

    it('resolves a token from the file when the prompt is sent', function()
      local path = vim.fn.tempname() .. '.lua'

      vim.fn.writefile({ 'one', 'two', 'three' }, path)

      local buffer = vim.fn.bufadd(path)

      vim.fn.bufload(buffer)
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'one', 'two', 'three' })
      vim.bo[buffer].filetype = 'lua'

      open_composer(session)
      eq(true, composer.attach(buffer, { 2, 3 }))

      local lines = input(session)

      composer.view(session).element:set_lines({ lines[1] .. 'explain' })

      press('<Esc>')
      press('<CR>')
      vim.wait(1000, function()
        return #prompts(fake) == 1
      end)

      local sent = vim.tbl_filter(function(message)
        return message.method == 'session/prompt'
      end, fake.sent)[1].params.prompt
      local text = {}

      for _, block in ipairs(sent) do
        text[#text + 1] = block.text or (block.resource and block.resource.text) or ''
      end

      local written = table.concat(text, '\n')

      assert.is_truthy(written:find('two', 1, true))
      assert.is_truthy(written:find('three', 1, true))
      assert.is_truthy(written:find('explain', 1, true))
      local token = lines[1]:match('@%S+')

      assert.is_truthy(token:find(':2%-3$'))
      assert.is_truthy(written:find(token, 1, true) < written:find('two', 1, true))

      vim.fn.delete(path)
      vim.api.nvim_buf_delete(buffer, { force = true })
    end)

    it('drops a token that is no longer in the text', function()
      open_composer(session)
      composer.attach(file, { 1, 2 })
      composer.view(session).element:set_lines({ 'no reference' })

      press('<Esc>')
      press('<CR>')
      vim.wait(1000, function()
        return #prompts(fake) == 1
      end)

      local sent = vim.tbl_filter(function(message)
        return message.method == 'session/prompt'
      end, fake.sent)[1].params.prompt
      local text = {}

      for _, block in ipairs(sent) do
        text[#text + 1] = block.text or (block.resource and block.resource.text) or ''
      end

      assert.is_nil(table.concat(text, '\n'):find('local a = 1', 1, true))
    end)

    it('is taken from a visual selection in another window', function()
      open_composer(session)
      vim.cmd('wincmd k')
      vim.api.nvim_win_set_buf(0, file)
      press('Vj')

      eq(true, composer.attach_visual())
      assert.is_truthy(table.concat(input(session), '\n'):find('@/w/a.lua:1-2', 1, true))
    end)

    it('leaves a visual selection alone when no composer is open', function()
      vim.api.nvim_win_set_buf(0, file)
      press('Vj')

      eq(false, composer.attach_visual())
      eq('V', vim.api.nvim_get_mode().mode)
      press('<Esc>')
    end)

    it('opens the composer for the last transcript and attaches there', function()
      vim.api.nvim_win_set_buf(0, file)
      press('Vj')

      eq(true, commands.attach_visual())
      eq(true, composer.is_open())
      eq(session, composer.target())
      assert.is_truthy(table.concat(input(session), '\n'):find('@/w/a.lua:1-2', 1, true))

      press('<Esc>')
      composer.close(true)
    end)

    it('moves the session\'s running tour to the selection', function()
      local tour_store = require('harness.tour_store')
      local seen

      open_composer(session)
      tour_store.start(session.key, { title = 'Walk', steps = {} })
      tour_store.on(function(kind, _, _, update)
        if kind == 'select' then seen = update end
      end)

      composer.attach(file, { 1, 3 })

      eq({ path = '/w/a.lua', first = 1, last = 3 }, seen)

      tour_store.reset()
    end)
  end)

  it('attaches the current line in normal mode', function()
    local line_file = vim.api.nvim_create_buf(true, false)

    vim.api.nvim_buf_set_name(line_file, '/w/current.lua')
    vim.api.nvim_buf_set_lines(line_file, 0, -1, false, { 'one', 'two' })

    open_composer(session)
    vim.cmd('wincmd k')
    vim.api.nvim_win_set_buf(0, line_file)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    eq(true, commands.attach_line())
    assert.is_truthy(table.concat(input(session), '\n'):find('@/w/current.lua:2', 1, true))

    vim.api.nvim_buf_delete(line_file, { force = true })
  end)

  it('says why a transcript selection has nothing to reference', function()
    open_composer(session)
    vim.cmd('wincmd k')
    vim.api.nvim_win_set_buf(0, transcript.buffer_of(session))
    press('Vj')

    local console = require('core.console')
    local notify = console.notify_now
    local said

    console.notify_now = function(message)
      said = message
    end

    local attached = commands.attach_visual()

    console.notify_now = notify
    eq(false, attached)
    assert.is_truthy(said and said:find('select lines in a file', 1, true))
    press('<Esc>')
  end)

  it('recalls earlier prompts with <Up> and <Down> at the edges, handing the draft back', function()
    for _, text in ipairs({ 'first', 'second' }) do
      open_composer(session)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
      press('<CR>')
      vim.wait(1000, function()
        return #prompts(fake) == (text == 'first' and 1 or 2)
      end)
      vim.wait(200)
    end

    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'draft' })
    press('<Up>')
    eq({ 'second' }, input(session))
    press('<C-p>')
    eq({ 'first' }, input(session))
    press('<C-n>')
    press('<Down>')
    eq({ 'draft' }, input(session))
  end)

  it('moves by line, not by prompt, inside a multi-line draft', function()
    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a', 'b', 'c' })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    press('<Up>')
    eq(2, vim.api.nvim_win_get_cursor(0)[1])
    eq({ 'a', 'b', 'c' }, input(session))
  end)

  it('treats <CR> in insert mode as a newline', function()
    open_composer(session)
    press('ione<CR>two<Esc>')

    eq({ 'one', 'two' }, input(session))
    eq(true, composer.is_open())
    eq({}, prompts(fake))
  end)

  it('sends on :w', function()
    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hello' })
    vim.cmd('write')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    eq({ 'hello' }, prompts(fake))
    eq(false, composer.is_open())
  end)

  it('says where the user was, from the session\'s source buffer', function()
    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'what is this?' })
    press('<CR>')
    vim.wait(1000, function()
      return #prompts(fake) == 1
    end)

    local blocks = fake:sent_method('session/prompt').params.prompt

    assert.is_truthy(blocks[1].text:find('(bufnr ' .. code .. ')', 1, true))
  end)

  it('keeps a draft when closed with q, and an empty send just closes', function()
    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'half a thought' })
    press('q')

    eq(false, composer.is_open())

    open_composer(session)
    eq({ 'half a thought' }, input(session))

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '   ' })
    press('<CR>')

    eq(false, composer.is_open())
    eq({}, prompts(fake))
  end)

  describe('one per session', function()
    local other

    local function side_by_side()
      local first = vim.api.nvim_get_current_win()

      vim.cmd('vsplit')
      other = hub.start({ dir = '/w' }):wait()
      transcript.open(other)

      return first, vim.api.nvim_get_current_win()
    end

    it('focuses the open one when asked again for the same session', function()
      local first = open_composer(session)

      vim.cmd('wincmd p')
      eq(first, open_composer(session))
      eq(1, #composers())
    end)

    it('gives each visible transcript its own, under it, keeping every draft', function()
      local first_win, other_win = side_by_side()
      local Window = require('core.Window')

      vim.api.nvim_set_current_win(first_win)
      open_composer(session)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'for the first' })
      vim.wait(50)

      vim.api.nvim_set_current_win(other_win)
      open_composer(other)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'for the other' })
      vim.wait(50)

      eq(2, #composers())
      eq(true, composer.is_open(session))
      eq(true, composer.is_open(other))
      eq(true, Window(composer.view(session).element:get_window().win_id):is_below(Window(first_win)))
      eq(true, Window(composer.view(other).element:get_window().win_id):is_below(Window(other_win)))
      eq({ 'for the first' }, composer.view(session):lines())
      eq({ 'for the other' }, composer.view(other):lines())
    end)

    it('closes only the one whose transcript window closed', function()
      local first_win, other_win = side_by_side()

      vim.api.nvim_set_current_win(first_win)
      open_composer(session)
      vim.api.nvim_set_current_win(other_win)
      open_composer(other)

      vim.api.nvim_win_close(first_win, true)
      vim.wait(200, function()
        return not composer.is_open(session)
      end)

      eq(false, composer.is_open(session))
      eq(true, composer.is_open(other))
      eq(1, #composers())
    end)

    it('tells two open composers apart by buffer', function()
      local first_win, other_win = side_by_side()

      vim.api.nvim_set_current_win(first_win)
      open_composer(session)
      vim.api.nvim_set_current_win(other_win)
      open_composer(other)

      local names = vim.tbl_map(function(win)
        return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
      end, composers())

      table.sort(names)
      eq(2, #names)
      assert.are_not.equal(names[1], names[2])
    end)

    it('asks which session when the current one is out of sight and several others are showing', function()
      local surfaces = require('surfaces')
      local pick = surfaces.pick
      local asked
      local file = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_buf_set_name(file, '/w/b.lua')
      vim.api.nvim_buf_set_lines(file, 0, -1, false, { 'one', 'two', 'three' })

      local first_win, other_win = side_by_side()
      local third = hub.start({ dir = '/w' }):wait()

      transcript.open(third, { background = true })
      require('harness.ui.display').set_current(transcript.view_of(third))

      surfaces.pick = function(opts)
        asked = opts
      end

      vim.cmd('botright vsplit')
      vim.api.nvim_win_set_buf(0, file)
      press('Vj')

      eq(true, commands.attach_visual())
      surfaces.pick = pick

      assert.is_truthy(asked)
      eq(2, #asked.items)
      press('<Esc>')
      assert.is_nil(table.concat(input(session), '\n'):find('@', 1, true))

      local chosen = vim.tbl_filter(function(item)
        return item.view.session == other
      end, asked.items)[1]

      asked.on_select(chosen)
      vim.wait(300, function()
        return table.concat(input(other), '\n'):find('@/w/b.lua:1-2', 1, true) ~= nil
      end)

      assert.is_truthy(table.concat(input(other), '\n'):find('@/w/b.lua:1-2', 1, true))
      assert.is_nil(table.concat(input(session), '\n'):find('@', 1, true))
      eq(other, composer.target())
      assert.is_true(vim.api.nvim_win_is_valid(first_win) and vim.api.nvim_win_is_valid(other_win))
    end)

    it('takes a selection for the session the tab is working with, as it moves between them', function()
      local file = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_buf_set_name(file, '/w/c.lua')
      vim.api.nvim_buf_set_lines(file, 0, -1, false, { 'one', 'two', 'three' })

      local first_win, other_win = side_by_side()

      vim.api.nvim_set_current_win(first_win)
      open_composer(session)
      vim.api.nvim_set_current_win(other_win)
      open_composer(other)

      vim.cmd('botright vsplit')
      vim.api.nvim_win_set_buf(0, file)
      press('Vj')
      eq(true, commands.attach_visual())
      assert.is_truthy(table.concat(input(other), '\n'):find('@/w/c.lua:1-2', 1, true))
      assert.is_nil(table.concat(input(session), '\n'):find('@', 1, true))
      press('<Esc>')

      vim.api.nvim_set_current_win(first_win)
      vim.cmd('botright vsplit')
      vim.api.nvim_win_set_buf(0, file)
      press('Vj')
      eq(true, commands.attach_visual())
      assert.is_truthy(table.concat(input(session), '\n'):find('@/w/c.lua:1-2', 1, true))
      press('<Esc>')
    end)
  end)

  it('stays open when focus leaves, keeping the draft, so a selection can be attached', function()
    open_composer(session)

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'later' })
    vim.cmd('wincmd p')

    local moved = vim.api.nvim_get_current_win()

    vim.wait(300)

    eq(true, composer.is_open())
    eq(1, #composers())
    eq(moved, vim.api.nvim_get_current_win())

    composer.view():focus()
    eq({ 'later' }, input(session))
  end)

  it('keeps its window when the transcript is opened while it has focus', function()
    open_composer(session)

    local composer_win = vim.api.nvim_get_current_win()
    local view = transcript.view_of(session)

    display.open(session)
    vim.wait(100)

    eq(true, composer.is_open())
    eq(composer_win, vim.api.nvim_get_current_win())
    eq(2, #vim.api.nvim_list_wins())

    local showing = vim.tbl_filter(function(win)
      return vim.api.nvim_win_get_buf(win) == view.bufnr
    end, vim.api.nvim_list_wins())

    eq(1, #showing)
  end)

  it('closes its split when another buffer takes the window', function()
    open_composer(session)

    vim.cmd('bnext')
    vim.wait(200)

    eq(false, composer.is_open())
    eq(1, #vim.api.nvim_list_wins())
  end)

  it('closes the split when its buffer was wiped first', function()
    local element = open_composer(session)

    vim.api.nvim_buf_delete(element:get_buffer().bufnr, { force = true })
    composer.close()

    eq(false, composer.is_open())
    eq(1, #vim.api.nvim_list_wins())
  end)

  it('keeps the draft when its window is closed some other way', function()
    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'closed with <C-w>c' })
    vim.wait(50)
    vim.cmd('wincmd p')
    vim.cmd('only')

    eq(false, composer.is_open())
    eq(0, #composers())

    open_composer(session)
    eq({ 'closed with <C-w>c' }, input(session))
  end)

  describe('attached to its transcript', function()
    local function layout()
      local transcript_win = vim.api.nvim_get_current_win()

      vim.cmd('vertical aboveleft new')

      local code_win = vim.api.nvim_get_current_win()

      vim.api.nvim_set_current_win(transcript_win)

      return transcript_win, code_win
    end

    local function composer_win()
      return composers()[1]
    end

    it('opens under the transcript, as wide as it, leaving the code beside it alone', function()
      local transcript_win, code_win = layout()
      local code_width = vim.api.nvim_win_get_width(code_win)

      open_composer(session)

      local win = composer_win()

      eq(vim.api.nvim_win_get_width(transcript_win), vim.api.nvim_win_get_width(win))
      eq(vim.api.nvim_win_get_position(transcript_win)[2], vim.api.nvim_win_get_position(win)[2])
      eq(code_width, vim.api.nvim_win_get_width(code_win))
      eq(true, require('core.Window')(win):is_below(require('core.Window')(transcript_win)))
    end)

    it('closes with its transcript window and keeps the draft', function()
      local transcript_win = layout()

      open_composer(session)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'kept for later' })
      vim.wait(50)
      vim.api.nvim_win_close(transcript_win, true)
      vim.wait(200, function()
        return not composer.is_open()
      end)

      eq(false, composer.is_open())
      eq(0, #composers())

      transcript.open(session)
      open_composer(session)
      eq({ 'kept for later' }, input(session))
    end)

    it('closes when another buffer takes the transcript window, leaving focus there', function()
      local transcript_win = layout()

      open_composer(session)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'not lost' })
      vim.wait(50)
      vim.api.nvim_set_current_win(transcript_win)
      vim.cmd('enew')
      vim.wait(200, function()
        return not composer.is_open()
      end)

      eq(false, composer.is_open())
      eq(transcript_win, vim.api.nvim_get_current_win())

      transcript.open(session)
      open_composer(session)
      eq({ 'not lost' }, input(session))
    end)

    it('follows its transcript when the window is moved', function()
      local transcript_win = layout()
      local Window = require('core.Window')

      open_composer(session)
      vim.wait(300)

      local height = vim.api.nvim_win_get_height(composer_win())

      vim.api.nvim_exec_autocmds('WinResized', {})
      vim.wait(50)
      vim.api.nvim_set_current_win(transcript_win)
      vim.cmd('wincmd H')
      vim.api.nvim_exec_autocmds('WinResized', {})
      vim.wait(300, function()
        return Window(composer_win()):is_below(Window(transcript_win))
      end)

      eq(true, Window(composer_win()):is_below(Window(transcript_win)))
      eq(height, vim.api.nvim_win_get_height(composer_win()))
    end)

    it('opens along the bottom when its transcript is not in sight', function()
      vim.cmd('enew')
      session.title = 'A session'
      open_composer(session)

      eq(vim.o.columns, vim.api.nvim_win_get_width(composer_win()))

      local bar = composer.view(session):winbar()

      assert.is_truthy(bar:find(session.key, 1, true))
      assert.is_truthy(bar:find('A session', 1, true))
    end)
  end)

  it('stays unmodified while answering, so :wall never submits the answer', function()
    local prompt = {
      is_open = function()
        return true
      end,
      writing = function()
        return true
      end,
      writing_label = function()
        return 'Name'
      end,
      stop_writing = function() end,
    }

    open_composer(session, { answer = prompt })

    local buf = vim.api.nvim_get_current_buf()

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Ada' })
    vim.wait(100)

    eq(false, vim.bo[buf].modified)
  end)

  it('sends the reply to the window it came from when that is still open', function()
    local origin = vim.api.nvim_get_current_win()

    vim.cmd('enew')
    open_composer(session)
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
    open_composer(session)
    press('ccwritten then quit<Esc>')
    vim.cmd('quit')
    vim.wait(200, function()
      return not composer.is_open()
    end)

    eq(false, composer.is_open())

    open_composer(session)
    eq({ 'written then quit' }, input(session))
  end)

  it('quits with :q even with text in it, and sends with :wq', function()
    open_composer(session)
    press('ccunsent<Esc>')

    vim.cmd('quit')
    eq(false, composer.is_open())

    open_composer(session)
    eq({ 'unsent' }, input(session))

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

    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'anyone there?' })
    session.state = 'closed'
    press('<CR>')
    vim.wait(200, function()
      return warned ~= nil
    end)
    vim.notify = notify

    eq(true, composer.is_open())
    eq({ 'anyone there?' }, input(session))
    assert.is_truthy(warned:find('ended; your text is kept', 1, true))
    eq({}, prompts(fake))
  end)

  it('closes and drops the draft when the session is deleted', function()
    open_composer(session)
    press('ccto be dropped<Esc>')
    composer.forget(session)

    eq(false, composer.is_open())

    session.state = 'idle'
    open_composer(session)
    eq({ '' }, input(session))
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
      open_composer(session)

      assert.is_truthy(composer.view():hints_text():find('queue', 1, true))
      assert.is_truthy(composer.view():hints_text():find('<C-c>', 1, true))

      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'next question' })
      press('<CR>')

      eq(false, composer.is_open())
      eq({ 'next question' }, session:queued())

      local buf = transcript.buffer_of(session)
      local Document = require('harness.ui.Document')

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

      open_composer(session)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'my draft' })
      press('<C-c>')
      vim.wait(200)
      vim.notify = notify

      eq('s1', fake:sent_method('session/cancel').params.sessionId)
      eq({ 'queued one', '', 'my draft' }, input(session))
      eq({}, session:queued())
      eq(1, #prompt_ids)
    end)

    it('only leaves insert mode on <C-c> while a turn runs, without cancelling it', function()
      open_composer(session)
      press('i<C-c>')
      vim.wait(100)

      eq('n', vim.api.nvim_get_mode().mode)
      assert.is_nil(fake:sent_method('session/cancel'))
      eq(true, session:running())
    end)

    it('takes back queued messages however the turn is interrupted, even from the agent\'s session_cancel', function()
      local notify = vim.notify
      vim.notify = function() end

      session:enqueue('from the queue')
      session:cancel()
      vim.notify = notify

      open_composer(session)

      eq({ 'from the queue' }, input(session))
    end)

    it('says why queued messages came back: an interrupt, or a failed turn', function()
      local said = {}
      local console = require('core.console')
      local original = console.notify_now

      console.notify_now = function(message)
        said[#said + 1] = message
      end

      composer.on_returned(session, { 'a' }, 'failed')
      composer.on_returned(session, { 'b', 'c' }, 'interrupted')
      console.notify_now = original

      eq({
        'Harness: the turn failed; 1 queued message moved back to the composer',
        'Harness: interrupted; 2 queued messages moved back to the composer',
      }, said)
    end)

    it('steers with <C-s>, falling back to the queue when the agent cannot steer', function()
      open_composer(session)

      local view = composer.view()

      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'change course' })
      press('<C-s>')

      eq({ 'change course' }, session:queued())
      eq(nil, view:hints_text():find('steer', 1, true))
    end)
  end)

  it('completes the agent\'s slash commands at the start of the message', function()
    session.commands = {
      { name = 'review', description = 'review changes', hint = 'branch' },
      { name = 'compact', description = 'summarize' },
    }
    open_composer(session)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '/re' })
    vim.api.nvim_win_set_cursor(0, { 1, 3 })

    eq(0, composer.complete(1, ''))
    eq({ { word = '/review ', abbr = '/review branch', menu = 'review changes' } }, composer.complete(0, '/re'))
    assert.is_truthy(composer.view():hints_text():find('commands', 1, true))

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'not /a command' })
    vim.api.nvim_win_set_cursor(0, { 1, 8 })
    eq(-3, composer.complete(1, ''))
  end)

  it('keeps / and @ in the order they were typed, however fast', function()
    open_composer(session)
    vim.cmd('stopinsert')
    press('ia/b @lua/core and x@y/z<Esc>')

    eq({ 'a/b @lua/core and x@y/z' }, input(session))
  end)

  it('takes the completion with <CR> and <Tab>, going into a folder', function()
    local Window = require('core.Window')
    local real = Window.completion

    Window.completion = function()
      return nil
    end
    eq('<CR>', composer.accept('<CR>'))
    eq('<Tab>', composer.next_item('<Tab>'))

    Window.completion = function()
      return { items = {} }
    end
    eq('<C-e><CR>', composer.accept('<CR>'))
    eq('<C-n>', composer.next_item('<Tab>'))

    Window.completion = function()
      return { items = { { word = '@lua/a.lua' } } }
    end
    eq('<C-n><C-y>', composer.accept('<CR>'))

    Window.completion = function()
      return { selected = { word = '@lua/' }, items = {} }
    end
    eq('<C-y><C-x><C-o>', composer.accept('<CR>'))

    Window.completion = function()
      return { selected = { word = '@lua/a.lua' }, items = {} }
    end
    eq('<C-y>', composer.accept('<CR>'))

    Window.completion = real
  end)

  it('opens from the session buffer\'s i', function()
    press('i')

    eq(true, composer.is_open())
    eq(session, composer.target())
  end)
end)
