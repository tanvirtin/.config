local text = require('core.text')
local motion = require('ui.motion')
local Timer = require('core.Timer')
local Object = require('core.Object')
local Buffer = require('core.Buffer')
local Window = require('core.Window')
local settings = require('harness.settings')
local Animator = require('harness.ui.Animator')
local theme = require('harness.transcript.theme')

local Toast = Object:extend()

Toast.BLEND_SHOWN = 12
Toast.BLEND_HIDDEN = 100

local animator, current

local function dismiss()
  if animator then animator:cancel('toast') end

  if current then
    if current.window:is_valid() then current.window:close() end
    if current.buffer:is_valid() then current.buffer:delete({ force = true }) end
  end

  current = nil
end

function Toast.dismiss()
  dismiss()
end

function Toast.visible()
  return current ~= nil
end

function Toast.show(message, opts)
  opts = opts or {}
  dismiss()

  local spec = vim.tbl_extend('force', settings.transcript:get('toast'), {})

  if theme.reduced() then
    spec.in_ms, spec.out_ms = 0, 0
  end

  local label = ' ' .. (opts.icon or '◆') .. ' ' .. message:gsub('%s+', ' ') .. ' '
  local width = math.min(text.width(label), math.max(Window.screen_width() - 4, 10))
  local buffer = Buffer():create(false, true)

  buffer:set_lines({ label })
  buffer:set_option('bufhidden', 'wipe')

  local window = Window.get_current():open(buffer, {
    relative = 'editor',
    anchor = 'NE',
    row = 1,
    col = Window.screen_width() - 2,
    width = width,
    height = 1,
    style = 'minimal',
    focusable = false,
    zindex = 250,
  })

  window:set_option('winhl', 'Normal:UiComposer')
  window:set_option('winblend', theme.reduced() and Toast.BLEND_SHOWN or Toast.BLEND_HIDDEN)

  local started = Timer.now()
  local fade_in =
    motion.Tween({ from = Toast.BLEND_HIDDEN, to = Toast.BLEND_SHOWN, ms = spec.in_ms, started = started })
  local fade_out

  current = { window = window, buffer = buffer }

  animator = animator or Animator()
  animator:add('toast', function(now)
    if not window:is_valid() then return false end

    if not fade_out and now - started >= spec.in_ms + spec.hold_ms then
      fade_out = motion.Tween({ from = Toast.BLEND_SHOWN, to = Toast.BLEND_HIDDEN, ms = spec.out_ms, started = now })
    end

    local tween = fade_out or fade_in

    window:set_option('winblend', math.floor(tween:at(now) + 0.5))

    if fade_out and fade_out:done(now) then
      dismiss()

      return false
    end

    return true
  end)

  return window
end

return Toast
