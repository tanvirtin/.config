local Connection = require('harness.acp.connection')
local Session = require('harness.session')
local TranscriptView = require('harness.ui.TranscriptView')
local events = require('harness.events')
local fake_agent = require('harness.fake_agent')

local eq = assert.are.same

describe('harness.ui.TranscriptView:', function()
  local session

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    session = Session({ key = 'h' .. math.random(1e6), id = 's1', connection = Connection(fake_agent.new()) })
  end)

  it('names the buffer after the session and labels the agent', function()
    eq('harness://h1 untitled', TranscriptView.buffer_name({ key = 'h1' }))
    eq('Claude', TranscriptView.agent_label({ agent = { name = 'claude' } }))
    eq('Agent', TranscriptView.agent_label({}))
  end)

  it('creates a listed, unmodifiable harness buffer that renders on mount', function()
    session:_emit(events.prompt('hi'))

    local view = TranscriptView(session):mount()

    eq(TranscriptView.FILETYPE, vim.bo[view.bufnr].filetype)
    eq(false, vim.bo[view.bufnr].modifiable)
    eq('> hi', vim.api.nvim_buf_get_lines(view.bufnr, 2, 3, false)[1])
    view:dispose()
  end)

  it('styles each window it is shown in, with folds driven by the document', function()
    local view = TranscriptView(session):mount()

    vim.api.nvim_win_set_buf(0, view.bufnr)

    local win = vim.api.nvim_get_current_win()

    eq('expr', vim.wo[win].foldmethod)
    eq(2, vim.wo[win].conceallevel)
    assert.truthy(vim.wo[win].winbar:find('write to this session', 1, true))
    eq(true, view:is_visible())
    view:dispose()
  end)

  it('lands at the bottom when shown, decorating only around where the window lands', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()

    view:show_in(require('core.Window').get_current())

    local win = vim.api.nvim_get_current_win()
    local document = require('harness.ui.document')

    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    eq({}, vim.api.nvim_buf_get_extmarks(view.bufnr, document.NAMESPACE, 0, { 3, 0 }, {}))
    assert.is_true(
      #vim.api.nvim_buf_get_extmarks(
          view.bufnr,
          document.NAMESPACE,
          { view.document.blocks[#view.document.blocks].start, 0 },
          -1,
          {}
        ) > 0
    )
    view:dispose()
  end)

  it('lets go of the session, its timer and its autocmds when disposed', function()
    local view = TranscriptView(session):mount()
    local group = view.group.id

    view:dispose()
    view:dispose()

    eq({}, session._listeners)
    eq(false, view.timer:is_active())
    eq(false, pcall(vim.api.nvim_get_autocmds, { group = group }))
  end)

  it('collapses old turns until expanded, then shows them all', function()
    local settings = require('harness.settings.transcript')
    local saved = settings:get('live_turns')

    settings:set('live_turns', 2)

    for i = 1, 5 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()

    eq('collapsed', view.document.blocks[2].kind)
    assert.is_true(view:expand())
    assert.is_false(view:expand())
    eq('> turn 1', vim.api.nvim_buf_get_lines(view.bufnr, 2, 3, false)[1])

    settings:set('live_turns', saved)
    view:dispose()
  end)

  it('lists the tool calls whose sub-agents are still running', function()
    local active = TranscriptView.active_subagents({
      children = {
        c1 = { tool = 'A', state = 'running' },
        c2 = { tool = 'B', state = 'idle' },
        c3 = { state = 'running' },
      },
    })

    eq({ A = true }, active)
    eq({}, TranscriptView.active_subagents({}))
  end)
end)
