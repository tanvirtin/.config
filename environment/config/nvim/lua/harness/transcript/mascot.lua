local motion = require('ui.motion')
local Timer = require('core.Timer')
local roles = require('ui.pixel.roles')
local static = require('ui.pixel.static')
local Animation = require('ui.pixel.Animation')

local mascot = {}

mascot.COLS = 3
mascot.BLOCK = 2
mascot.FORM_MS = 600
mascot.GRACE_MS = 600
mascot.WANE_MS = 800
mascot.HOLD_MS = 200
mascot.BODY = 'muted'
mascot.EYES = { work = 'accent', wait = 'warn', fail = 'error' }

mascot.ART = {
  '....ssSSSSss....',
  '..sSSSssssSSSs..',
  '.sSSs......sSSs.',
  '.SSs........sSS.',
  'sSs.ee....ee.sSs',
  'sSs.ee....ee.sSs',
  'sSs.ee....ee.sSs',
  'sSs..........sSs',
  '.SSs........sSS.',
  '.sSSs......sSSs.',
  '..sSSSssssSSSs..',
  '....ssSSSSss....',
}

local GRID = { 24, 16 }
local ORIGIN = { 4, 2 }
local EYE_ROWS = { 5, 7 }
local BOB_STEPS, BLINK_EVERY, BLINK_STEPS = 6, 34, 2
local LOOK_EVERY, LOOK_FROM, LOOK_STEPS = 60, 40, 10
local FORM_SEED, WANE_SEED = 21, 23

local mood = 'work'
local fed_by

local function put(bitmap, x, y, rgb, alpha)
  static.block(bitmap, x, y, rgb, alpha, mascot.BLOCK)
end

local function present(x, y, form, wane)
  return static.hash(x, y, FORM_SEED) < form * 100 and static.hash(x, y, WANE_SEED) >= wane * 100
end

function mascot.specks(bitmap, step, rgb, form, wane)
  local density = 3 + (1 - form) * 22 + wane * (1 - wane) * 60
  local at = math.floor(step / 2)

  for y = 0, GRID[2] - 1 do
    for x = 0, GRID[1] - 1 do
      if static.hash(x, y, at) < density then put(bitmap, x, y, rgb, 0.3) end
    end
  end
end

function mascot.body(bitmap, step, rgb, form, wane, lift)
  for row, line in ipairs(mascot.ART) do
    for col = 1, #line do
      local cell = line:sub(col, col)
      local x, y = ORIGIN[1] + col - 1, ORIGIN[2] + row - 1 + lift

      if (cell == 'S' or cell == 's') and present(x, y, form, wane) then
        local h = static.hash(x, y, step)

        if cell == 'S' then
          put(bitmap, x, y, rgb, 0.4 + h / 170)
        elseif h < 60 then
          put(bitmap, x, y, rgb, 0.2 + h / 200)
        end
      end
    end
  end
end

function mascot.eyes(bitmap, step, kind, form, wane, lift)
  if form < 1 or wane > 0.5 then return end

  local rgb = roles.rgb(mascot.EYES[kind] or mascot.EYES.work)
  local steady = kind ~= 'work'
  local shut = kind == 'fail' or (step % BLINK_EVERY < BLINK_STEPS)
  local look = not steady and step % LOOK_EVERY >= LOOK_FROM and step % LOOK_EVERY < LOOK_FROM + LOOK_STEPS
  local middle = (EYE_ROWS[1] + EYE_ROWS[2]) / 2

  for row = EYE_ROWS[1], EYE_ROWS[2] do
    local line = mascot.ART[row]

    for col = 1, #line do
      if line:sub(col, col) == 'e' and (not shut or row == middle) then
        put(bitmap, ORIGIN[1] + col - 1 + (look and 1 or 0), ORIGIN[2] + row - 1 + lift, rgb, 1)
      end
    end
  end
end

function mascot.draw(bitmap, step, kind, form, wane)
  local body = roles.rgb(mascot.BODY)
  local lift = (kind == 'work' and wane == 0) and math.floor(step / BOB_STEPS) % 2 or 0

  mascot.specks(bitmap, step, body, form, wane)
  mascot.body(bitmap, step, body, form, wane, lift)
  mascot.eyes(bitmap, step, kind, form, wane, lift)
end

local animation = Animation({
  cols = mascot.COLS,
  draw = function(bitmap, at, anim)
    local form = motion.clamp(anim:elapsed(at) / mascot.FORM_MS)
    local wane = motion.clamp((at - (anim.last_wanted or at) - mascot.GRACE_MS) / mascot.WANE_MS)

    mascot.draw(bitmap, motion.step(at), mood, form, wane)
  end,
})

local function tint(kind)
  if kind then mood = kind end
end

function mascot.chunks(kind, owner)
  tint(kind)
  if owner ~= nil then fed_by = owner end
  animation.linger_ms = mascot.GRACE_MS + mascot.WANE_MS + mascot.HOLD_MS

  return animation:chunks()
end

function mascot.waning(owner)
  if owner == nil or owner ~= fed_by then return false end
  if animation.tile == nil or animation.last_wanted == nil then return false end

  return Timer.now() - animation.last_wanted <= mascot.GRACE_MS + mascot.WANE_MS
end

function mascot.idle_chunks(owner, kind)
  if owner == nil or owner ~= fed_by or animation.tile == nil then return nil end

  tint(kind)

  return animation.tile:chunks(1)
end

function mascot.stop()
  animation:stop()
  fed_by = nil
end

mascot.tint = tint

return mascot
