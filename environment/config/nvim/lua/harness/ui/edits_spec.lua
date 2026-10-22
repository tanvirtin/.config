local Connection = require('harness.acp.connection')
local Session = require('harness.session')
local edits = require('harness.ui.edits')
local events = require('harness.events')
local fake_agent = require('harness.fake_agent')
local transcript = require('harness.ui.transcript')

local eq = assert.are.same

describe('harness.ui.edits:', function()
  local vgit, saved_show, shown, keymaps, a_path, b_path, session, buf

  local function edit(id, path, old, new)
    session:_emit({
      kind = 'tool_call',
      id = id,
      name = 'Edit',
      category = 'edit',
      status = 'completed',
      locations = { { path = path } },
      diffs = { { path = path, old = old, new = new } },
    })
  end

  local function cursor_on_diff(id)
    for _, block in ipairs(transcript.view().document.blocks) do
      if block.kind == 'diff' and block.id == id then vim.api.nvim_win_set_cursor(0, { block.start + 3, 0 }) end
    end
  end

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    vgit = require('harness.vgit')
    saved_show = vgit.show
    shown, keymaps = nil, nil
    vgit.show = function(files, opts)
      shown, keymaps = files, opts and opts.keymaps
      return true
    end

    a_path, b_path = vim.fn.tempname() .. '.lua', vim.fn.tempname() .. '.lua'
    vim.fn.writefile({ 'local x = 3', 'local keep = true' }, a_path)
    vim.fn.writefile({ 'local y = 2' }, b_path)

    session = Session({ key = 'h' .. math.random(1e6), id = 's1', connection = Connection(fake_agent.new()) })
    session:_emit(events.prompt('first'))
    edit('e1', a_path, 'local x = 1', 'local x = 2')
    session:_emit(events.stop('end_turn'))
    session:_emit(events.prompt('second'))
    edit('e2', a_path, 'local x = 2', 'local x = 3')
    edit('e3', b_path, 'local y = 1', 'local y = 2')
    session:_emit(events.stop('end_turn'))
    buf = transcript.open(session)
  end)

  after_each(function()
    vgit.show = saved_show
    for _, path in ipairs({ a_path, b_path }) do
      local bufnr = vim.fn.bufnr(path)
      if bufnr ~= -1 then vim.api.nvim_buf_delete(bufnr, { force = true }) end
      os.remove(path)
    end
  end)

  it('previews reverting the edit under the cursor, and applies it from the preview', function()
    cursor_on_diff('e2')

    assert.is_true(edits.revert(transcript.view()))
    eq(
      {
        {
          filename = a_path,
          old_lines = { 'local x = 3', 'local keep = true' },
          new_lines = { 'local x = 2', 'local keep = true' },
        },
      },
      shown
    )

    local destroyed = false

    keymaps[1].handler({
      destroy = function()
        destroyed = true
      end,
    })

    eq({ 'local x = 2', 'local keep = true' }, vim.fn.readfile(a_path))
    eq(true, destroyed)
  end)

  it('reverts every edit of the turn under the cursor, newest first', function()
    vim.api.nvim_win_set_cursor(0, { #vim.api.nvim_buf_get_lines(buf, 0, -1, false), 0 })

    assert.is_true(edits.revert(transcript.view(), edits.SCOPE.turn))
    keymaps[1].handler({ destroy = function() end })

    eq({ 'local x = 2', 'local keep = true' }, vim.fn.readfile(a_path))
    eq({ 'local y = 1' }, vim.fn.readfile(b_path))
  end)

  it('reverts the whole session, and skips an edit changed since', function()
    vim.fn.writefile({ 'local y = 9' }, b_path)

    assert.is_true(edits.revert(transcript.view(), edits.SCOPE.session))
    eq(
      { a_path },
      vim.tbl_map(function(file)
        return file.filename
      end, shown)
    )
    eq({ 'local x = 1', 'local keep = true' }, shown[1].new_lines)
  end)

  it('says why when there is nothing to revert here', function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    eq({ false, 'no turn edits to revert here' }, { edits.revert(transcript.view()) })
  end)
end)
