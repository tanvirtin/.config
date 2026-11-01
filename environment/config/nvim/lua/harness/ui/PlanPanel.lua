local lazy = require('core.lazy')

local hl = lazy('ui.hl')
local Timer = lazy('core.Timer')
local motion = lazy('ui.motion')
local Object = lazy('core.Object')
local settings = lazy('harness.settings')
local Element = lazy('ui.elements.Element')
local Block = lazy('harness.transcript.Block')
local theme = lazy('harness.transcript.theme')
local plan_summary = lazy('harness.transcript.plan_summary')

local PlanPanel = Object:extend()

PlanPanel.ZINDEX = 40

function PlanPanel:constructor(animator)
  return {
    element = nil,
    anchor = nil,
    lines = nil,
    painted = false,
    pinned = false,
    dismissed = false,
    animator = animator,
    statuses = nil,
    flashes = {},
    summary = nil,
  }
end

function PlanPanel:is_shown()
  return self.element ~= nil and self.element:is_valid()
end

function PlanPanel:wanted(entries)
  if not entries or #entries == 0 or self.dismissed then return false end

  return self.pinned or plan_summary.unfinished(entries)
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
  self.summary = summary
end

function PlanPanel:_watch(entries)
  local previous = self.statuses

  self.statuses = {}

  for i, entry in ipairs(entries) do
    self.statuses[i] = entry.status
  end

  if not previous or not self.animator or theme.reduced() then return end

  local now = Timer.now()

  for i, status in ipairs(self.statuses) do
    if status == Block.STATUS.completed and previous[i] and previous[i] ~= status then self.flashes[i] = now end
  end

  if next(self.flashes) then self.animator:add('plan_flash', function(at)
    return self:_step(at)
  end) end
end

function PlanPanel:_step(now)
  if not self:is_shown() or not self.summary then
    self.flashes = {}

    return false
  end

  local ms = settings.transcript:get('flash_ms')
  local alive = {}

  self:_paint(self.summary)

  for index, started in pairs(self.flashes) do
    local progress = (now - started) / ms

    if progress < 1 then
      local line = self.summary.lines[index + 1] or ''

      self.element:place_extmark_highlight({
        hl = 'UiFlashAccent' .. motion.steps(hl.FLASH_STEPS, motion.ease.out_cubic(progress)),
        row = index,
        col_range = { from = 0, to = #line },
      })
      alive[index] = started
    end
  end

  self.flashes = alive

  return next(alive) ~= nil
end

function PlanPanel:update(history, window)
  local entries = plan_summary.latest(history)

  if not window or not window:is_valid() or not self:wanted(entries) then return self:hide() end

  local summary = plan_summary.render(entries)

  self:_watch(entries)

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

  self.element, self.anchor, self.lines, self.painted, self.summary = nil, nil, nil, false, nil
  self.statuses, self.flashes = nil, {}
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
