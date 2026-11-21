local guides = require('ui.guides')
local panes = require('core.editor.panes')
local scene = require('harness.scene')
local Window = require('core.editor.Window')

local eq = assert.are.same

local function joined(notes)
  return table.concat(notes, ' ')
end

describe('harness.scene:', function()
  local session, path, anchor

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    session = { key = 's1' }
    path = vim.fn.tempname() .. '.lua'
    vim.fn.writefile({ 'a', 'b', 'c' }, path)
    anchor = Window.get_current()
  end)

  after_each(function()
    guides.clear('s1')
    panes.close('s1')
    vim.fn.delete(path)
  end)

  it('says the chat is off screen when no transcript shows the session', function()
    assert.is_truthy(joined(scene.notes(session)):find('chat is not on screen', 1, true))
  end)

  it('lists the panes the agent left open, with where they are', function()
    panes.show('s1', anchor, 'code', path, { line = 2 })

    local text = joined(scene.notes(session))

    assert.is_truthy(text:find('Panes you opened: code ', 1, true))
    assert.is_truthy(text:find('%.lua:2%.'))
  end)

  it('keeps another session\'s panes out', function()
    panes.show('s2', anchor, 'code', path)

    assert.is_nil(joined(scene.notes(session)):find('Panes you opened', 1, true))

    panes.close('s2')
  end)

  it('says when the user is in one of the agent\'s panes', function()
    local pane = panes.show('s1', anchor, 'peek', path)

    assert.is_truthy(joined(scene.notes(session, { win = pane.win_id })):find('in the "peek" pane you opened', 1, true))
    assert.is_nil(joined(scene.notes(session, { win = anchor.win_id })):find('pane you opened', 1, true))
  end)

  it('warns that the prompt clears the agent\'s notes', function()
    local buffer = Window.get_current():get_buffer()

    buffer:set_lines({ 'x', 'y' })
    guides.mark('s1', buffer, { from = 1, step = 1 })
    guides.mark('s1', buffer, { from = 2, step = 2 })

    assert.is_truthy(joined(scene.notes(session)):find('clears the 2 notes from your last show', 1, true))
  end)

  it('says a prompt was moved from another session', function()
    assert.is_truthy(
      joined(scene.notes(session, { from = 'h2' })):find('drafted for session h2 and moved here', 1, true)
    )
  end)

  it('has nothing to add beyond the chat note when nothing was left open', function()
    eq(1, #scene.notes(session))
  end)
end)
