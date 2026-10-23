local lazy = require('core.lazy')

local Object = lazy('core.Object')
local Element = lazy('ui.elements.Element')
local PlanSummary = lazy('harness.transcript.PlanSummary')

local PlanPanel = Object:extend()

PlanPanel.ZINDEX = 40

function PlanPanel:constructor()
  return { element = nil, anchor = nil, lines = nil, painted = false, pinned = false, dismissed = false }
end

function PlanPanel:is_shown()
  return self.element ~= nil and self.element:is_valid()
end

function PlanPanel:wanted(entries)
  if not entries or #entries == 0 or self.dismissed then return false end

  return self.pinned or PlanSummary.unfinished(entries)
end

function PlanPanel:_plot(window, summary)
  local width = math.min(summary.width, math.max(window:get_width() - 4, 10))

  return {
    relative = 'win',
    win = window.win_id,
    anchor = 'NE',
    row = 0,
    col = window:get_width(),
    width = width,
    height = #summary.lines,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    zindex = PlanPanel.ZINDEX,
  }
end

function PlanPanel:_mount(window, summary)
  self.element = Element({
    window_mode = 'floating',
    win_plot = self:_plot(window, summary),
    buf_options = { modifiable = false, buflisted = false, bufhidden = 'wipe' },
    win_options = { winhl = 'Normal:UiNormal,FloatBorder:UiMuted', wrap = false },
  })
  self.element:mount()
  self.anchor = window.win_id
end

function PlanPanel:_paint(summary)
  local element = self.element

  element:set_lines(summary.lines)
  element:clear_extmark_highlights()

  for _, highlight in ipairs(summary.highlights) do
    element:place_extmark_highlight({
      hl = highlight.hl,
      row = highlight.row,
      col_range = { from = highlight.from, to = highlight.to },
    })
  end

  self.lines = summary.lines
end

function PlanPanel:update(history, window)
  local entries = PlanSummary.latest(history)

  if not window or not window:is_valid() or not self:wanted(entries) then return self:hide() end

  local summary = PlanSummary.render(entries)

  if self:is_shown() and self.anchor ~= window.win_id then self:hide() end

  if self:is_shown() then
    self.element:set_config(self:_plot(window, summary))
  else
    self:_mount(window, summary)
  end

  if not vim.deep_equal(self.lines, summary.lines) or not self.painted then
    self:_paint(summary)
    self.painted = true
  end
end

function PlanPanel:hide()
  if self.element then self.element:unmount() end

  self.element, self.anchor, self.lines, self.painted = nil, nil, nil, false
end

function PlanPanel:toggle(history, window)
  if self:is_shown() then
    self.pinned, self.dismissed = false, true
    return self:hide()
  end

  self.pinned, self.dismissed = true, false
  self:update(history, window)
end

return PlanPanel
