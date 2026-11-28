local lazy = require('core.lazy')

local Object = require('core.Object')
local Toast = lazy('harness.ui.Toast')
local display = lazy('harness.ui.display')
local Window = require('core.editor.Window')
local theme = lazy('harness.transcript.theme')
local ASK = require('harness.types.events').ASK
local presenter = lazy('harness.asks.presenter')

local WaitingNotice = Object:extend()

function WaitingNotice:constructor(session, bufnr)
  return { session = session, bufnr = bufnr }
end

function WaitingNotice:shown()
  local buffers = { [self.bufnr] = true }

  for _, holder in ipairs(presenter.holders(self.session)) do
    local bufnr = display.buffer_of(holder)

    if bufnr then buffers[bufnr] = true end
  end

  for _, window in ipairs(Window.list_tab()) do
    if buffers[window:get_buffer().bufnr] then return true end
  end

  return false
end

function WaitingNotice:announce()
  local waiting = self.session:waiting()

  if #waiting == 0 or self:shown() then return end

  local what = waiting[1].title or waiting[1].tool or 'a tool'
  local why = waiting[1].kind == ASK.elicitation and 'waiting for your answer' or 'waiting for permission'

  Toast.show(
    string.format('Harness %s: %s: %s', self.session.key, why, what),
    { icon = theme.WAITING_ICON[1]:gsub('%s+$', '') }
  )
end

return WaitingNotice
