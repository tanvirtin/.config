local Buffer = require('core.editor.Buffer')
local TuneIn = require('harness.transcript.effects.TuneIn')

local eq = assert.are.same

describe('harness.transcript.effects.TuneIn:', function()
  local buffer, window, view

  before_each(function()
    buffer = Buffer():create(false, true)
    buffer:set_lines({ 'the first line of a loaded session', 'and a second one', 'third' })
    vim.api.nvim_win_set_buf(0, buffer.bufnr)
    window = require('core.editor.Window').get_current()
    view = {
      buffer = buffer,
      document = { state = { loading = true } },
      windows = function()
        return { window }
      end,
    }
  end)

  after_each(function()
    vim.cmd('enew!')
    vim.api.nvim_buf_delete(buffer.bufnr, { force = true })
  end)

  local function static()
    return buffer:get_extmarks(TuneIn.NAMESPACE, 0, -1, { details = true })
  end

  it('starts once a session finishes loading, and not while it loads or for a plain write', function()
    local tune = TuneIn(view)

    eq(false, tune:before({ loading = true }))
    eq(true, tune:before({ loading = false }))

    view.document.state.loading = false
    eq(false, TuneIn(view):before({ loading = false }))
  end)

  it('starts when a view first opens a session that already has history, and only that once', function()
    view.document.state.loading = false
    view.session = { history = { { kind = 'prompt' } } }

    local tune = TuneIn(view)

    eq(true, tune:before({ loading = false }))
    tune.started = nil
    eq(false, tune:before({ loading = false }))

    view.session = { history = {} }
    eq(false, TuneIn(view):before({ loading = false }))
  end)

  it('covers the visible text in static that clears as it tunes in, then leaves it clean', function()
    local tune = TuneIn(view)

    tune:before({ loading = false })

    local started = tune.started

    eq(true, tune:step(started))

    local early = #static()

    assert.is_true(early > 0)
    eq('overlay', static()[1][4].virt_text_pos)

    tune:step(started + TuneIn.MS * 0.8)
    assert.is_true(#static() < early)

    eq(false, tune:step(started + TuneIn.MS))
    eq({}, static())
  end)

  it('stays still while motion is reduced', function()
    local settings = require('harness.settings.theme')
    local motion = settings:get('motion')

    settings:assign({ motion = vim.tbl_extend('force', motion, { reduced = true }) })

    local began = TuneIn(view):before({ loading = false })

    settings:assign({ motion = motion })

    eq(false, began)
  end)
end)
