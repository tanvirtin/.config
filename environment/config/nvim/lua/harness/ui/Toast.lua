local text = require('core.text')
local motion = require('ui.motion')
local Timer = require('core.Timer')
local Object = require('core.Object')
local Tile = require('ui.pixel.Tile')
local roles = require('ui.pixel.roles')
local glyph = require('ui.design.glyph')
local settings = require('harness.settings')
local Buffer = require('core.editor.Buffer')
local Window = require('core.editor.Window')
local Animation = require('ui.pixel.Animation')
local theme = require('harness.transcript.theme')
local Animator = require('harness.transcript.effects.Animator')

local Toast = Object:extend()

Toast.BLEND_SHOWN = 12
Toast.BLEND_HIDDEN = 100
Toast.RING_COLS = 2

local RING_THICKNESS = 3

local animator, current

function Toast:_timings()
  local spec = settings.transcript:get('toast')

  if theme.reduced() then return 0, spec.hold_ms, 0 end

  return spec.in_ms, spec.hold_ms, spec.out_ms
end

function Toast:_open(message, icon, padding)
  local label = ' ' .. icon .. ' ' .. message:gsub('%s+', ' ') .. ' ' .. (padding or '')
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

  return window, buffer, label
end

local function ring(bitmap, remaining, opacity)
  local cx, cy = bitmap.width / 2, bitmap.height / 2
  local radius = bitmap.height / 2 - RING_THICKNESS / 2 - 3

  bitmap:ring(cx, cy, radius, RING_THICKNESS, roles.rgb('muted'), 0.3 * opacity)
  bitmap:arc(cx, cy, radius, RING_THICKNESS, 0, remaining, roles.rgb('accent'), opacity)
end

function Toast.dismiss()
  if animator then animator:cancel('toast') end

  if current then
    if current.animation then current.animation:stop() end
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

  local in_ms, hold_ms, out_ms = Toast:_timings()
  local pixels = not theme.reduced() and Tile.available()
  local padding = pixels and string.rep(' ', Toast.RING_COLS + 1) or nil
  local window, buffer, label = Toast:_open(message, opts and opts.icon or glyph.STATUS.attention, padding)
  local started = Timer.now()
  local fade_in = motion.Tween({ from = Toast.BLEND_HIDDEN, to = Toast.BLEND_SHOWN, ms = in_ms, started = started })
  local fade_out

  local function blend_at(now)
    if not fade_out and now - started >= in_ms + hold_ms then
      fade_out = motion.Tween({ from = Toast.BLEND_SHOWN, to = Toast.BLEND_HIDDEN, ms = out_ms, started = now })
    end

    return math.floor((fade_out or fade_in):at(now) + 0.5)
  end

  local function remaining_at(now)
    local held = now - started - in_ms

    if held < 0 then return 1 end
    if hold_ms <= 0 then return 0 end

    return 1 - motion.clamp(held / hold_ms)
  end

  local animation

  if pixels then
    animation = Animation({
      cols = Toast.RING_COLS,
      duration_ms = in_ms + hold_ms + out_ms,
      started = started,
      linger_ms = 0,
      draw = function(bitmap, now)
        local opacity = 1 - (blend_at(now) - Toast.BLEND_SHOWN) / (Toast.BLEND_HIDDEN - Toast.BLEND_SHOWN)

        ring(bitmap, remaining_at(now), opacity)
      end,
    })
  end

  window:set_option('winblend', in_ms == 0 and Toast.BLEND_SHOWN or Toast.BLEND_HIDDEN)
  current = { window = window, buffer = buffer, animation = animation }

  local texts = animation and animation:chunks()

  if texts then buffer:place_extmark_text({ texts = texts, row = 0, col = #label - Toast.RING_COLS - 1 }) end

  animator = animator or Animator()
  animator:add('toast', function(now)
    if not window:is_valid() then return false end

    window:set_option('winblend', blend_at(now))

    if fade_out and fade_out:done(now) then
      Toast.dismiss()

      return false
    end

    return true
  end)

  return window
end

return Toast
