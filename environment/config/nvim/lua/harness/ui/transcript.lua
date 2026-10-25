local lazy = require('core.lazy')

local Fold = lazy('core.Fold')
local core_text = lazy('core.text')
local winbar = lazy('harness.ui.winbar')
local display = lazy('harness.ui.display')
local TranscriptView = lazy('harness.ui.TranscriptView')
local permission_prompt = lazy('harness.ui.permission_prompt')

local transcript = {}

transcript.FILETYPE = TranscriptView.FILETYPE

transcript.view = display.view
transcript.view_of = display.view_of
transcript.buffer_of = display.buffer_of
transcript.last = display.last
transcript.window = display.window
transcript.open = display.open
transcript.forget = display.forget
transcript.winbar = winbar.transcript
transcript.asks_of = permission_prompt.asks_of
transcript.ask = permission_prompt.ask
transcript.answer = permission_prompt.answer
transcript.report = TranscriptView.report

function transcript.render(history, title)
  return require('harness.transcript.text_renderer').render(history, title)
end

function transcript.announce_waiting(session)
  local view = display.view_of(session)

  if view then view:announce_waiting() end
end

function transcript.foldexpr()
  local view = display.view()

  return view and view.document:fold_level(Fold.lnum() - 1) or '0'
end

function transcript.foldtext()
  local first, last = Fold.range()
  local view = display.view()

  if view then return view:fold_text(first, last) end

  return { { '  ', 'UiMuted' }, { '⋯ ' .. core_text.plural(last - first + 1, 'more line'), 'UiMuted' } }
end

return transcript
