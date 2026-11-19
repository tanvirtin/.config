local lazy = require('core.lazy')

local Toast = lazy('sn.ui.Toast')
local Object = require('core.Object')
local theme = lazy('sn.transcript.theme')
local ASK = require('sn.types.events').ASK
local Window = require('core.editor.Window')

local WaitingNotice = Object:extend()

function WaitingNotice:constructor(session, bufnr)
  return { session = session, bufnr = bufnr }
end

function WaitingNotice:shown()
  for _, window in ipairs(Window.list_tab()) do
    if window:get_buffer().bufnr == self.bufnr then return true end
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
