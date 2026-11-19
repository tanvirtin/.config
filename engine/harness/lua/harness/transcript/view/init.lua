local lazy = require('core.lazy')

local asks = lazy('harness.asks')
local core_text = lazy('core.text')
local Fold = lazy('core.editor.Fold')
local glyph = lazy('ui.design.glyph')
local display = lazy('harness.ui.display')
local Permission = lazy('harness.asks.Permission')
local Elicitation = lazy('harness.asks.Elicitation')
local winbar = lazy('harness.transcript.view.winbar')
local TranscriptView = lazy('harness.transcript.view.TranscriptView')

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
transcript.asks_of = asks.asks_of
transcript.ask = Permission.ask
transcript.answer = asks.answer
transcript.elicit = Elicitation.ask
transcript.report = TranscriptView.report

function transcript.render(history, title)
  return require('harness.transcript.model.text_renderer').render(history, title)
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

  return {
    { '  ', 'UiMuted' },
    { glyph.STATUS.more .. ' ' .. core_text.plural(last - first + 1, 'more line'), 'UiMuted' },
  }
end

return transcript
