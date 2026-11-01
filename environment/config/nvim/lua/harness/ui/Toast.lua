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

local function timings()
  local spec = settings.transcript:get('toast')

  if theme.reduced() then return 0, spec.hold_ms, 0 end

  return spec.in_ms, spec.hold_ms, spec.out_ms
end

local function open(message, icon)
  local label = ' ' .. icon .. ' ' .. message:gsub('%s+', ' ') .. ' '
  local screen = Window.screen_width()
  local buffer = Buffer():create(false, true)

  buffer:set_lines({ label })
  buffer:set_option('bufhidden', 'wipe')

  local window = Window.get_current():open(buffer, {
    relative = 'editor',
    anchor = 'NE',
    row = 1,
    col = screen - 2,
    width = math.min(text.width(label), math.max(screen - 4, 10)),
    height = 1,
    style = 'minimal',
    focusable = false,
    zindex = 250,
  })

  window:set_option('winhl', 'Normal:UiComposer')

  return window, buffer
end

function Toast.dismiss()
  if animator then animator:cancel('toast') end

  if current then
    if current.window:is_valid() then current.window:close() end
    if current.buffer:is_valid() then current.buffer:delete({ force = true }) end
  end

  current = nil
end

function Toast.visible()
  return current ~= nil
end

function Toast.show(message, opts)
  Toast.dismiss()

  local window, buffer = open(message, opts and opts.icon or '◆')
  local in_ms, hold_ms, out_ms = timings()
  local started = Timer.now()
  local fade_in = motion.Tween({ from = Toast.BLEND_HIDDEN, to = Toast.BLEND_SHOWN, ms = in_ms, started = started })
  local fade_out

  window:set_option('winblend', in_ms == 0 and Toast.BLEND_SHOWN or Toast.BLEND_HIDDEN)
  current = { window = window, buffer = buffer }

  animator = animator or Animator()
  animator:add('toast', function(now)
    if not window:is_valid() then return false end

    if not fade_out and now - started >= in_ms + hold_ms then
      fade_out = motion.Tween({ from = Toast.BLEND_SHOWN, to = Toast.BLEND_HIDDEN, ms = out_ms, started = now })
    end

    window:set_option('winblend', math.floor((fade_out or fade_in):at(now) + 0.5))

    if fade_out and fade_out:done(now) then
      Toast.dismiss()

      return false
    end

    return true
  end)

  return window
end

return Toast
