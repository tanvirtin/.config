local motion = require('ui.motion')
local Timer = require('core.Timer')
local Tile = require('ui.pixel.Tile')
local roles = require('ui.pixel.roles')
local static = require('ui.pixel.static')
local tokens = require('ui.design.motion')
local Animation = require('ui.pixel.Animation')

local mascot = {}

mascot.COLS = 3
mascot.BLOCK = 2
mascot.FORM_MS = tokens.DURATION.slow
mascot.GRACE_MS = tokens.DURATION.slow
mascot.WANE_MS = tokens.DURATION.deliberate
mascot.HOLD_MS = tokens.DURATION.fast
mascot.BODY = 'muted'
mascot.EYES = { work = 'accent', wait = 'warn', fail = 'error' }
mascot.ACTS = { 'drift', 'glitch', 'jump', 'roll', 'scan' }
mascot.REST_STEPS = 20
mascot.ACT_STEPS = 40
mascot.LOOP_STEPS = (mascot.REST_STEPS + mascot.ACT_STEPS) * #mascot.ACTS
mascot.FORM_RUNGS = 6
mascot.WANE_RUNGS = 6
mascot.STILL_STEPS = 5

mascot.ART = {
  '.....sSSSSs.....',
  '...sSSSSSSSSs...',
  '..SSSs....sSSS..',
  '.SSs........sSS.',
  '.SS..eeeeee..SS.',
  '.SS..eeeeee..SS.',
  '.SS..........SS.',
  '.SSs........sSS.',
  '..SSs.S..S.sSS..',
  '..sSsS.SS.SsSs..',
  '..f.f..f..f..f..',
  '.f...f...f..f...',
}

local GRID = { 24, 16 }
local ORIGIN = { 4, 2 }
local EYE_ROWS = { 5, 6 }
local BOB_STEPS, BLINK_EVERY, BLINK_STEPS = 6, 34, 2
local LOOK_EVERY, LOOK_FROM, LOOK_STEPS = 60, 40, 10
local FORM_SEED, WANE_SEED = 21, 23

local mood = 'work'
local fed_by

local function put(bitmap, x, y, rgb, alpha)
  static.block(bitmap, x, y, rgb, alpha, mascot.BLOCK)
end

local function place(bitmap, pose, x, y, rgb, alpha)
  local gx = x + pose.dx + (pose.tear and pose.tear(y) or 0)
  local gy = y + pose.dy

  if pose.wrap then gy = gy % GRID[2] end
  if gx < 0 or gx >= GRID[1] or gy < 0 or gy >= GRID[2] then return end

  put(bitmap, gx, gy, rgb, alpha)
end

local function present(x, y, form, wane)
  return static.hash(x, y, FORM_SEED) < form * 100 and static.hash(x, y, WANE_SEED) >= wane * 100
end

local function shuffled(epoch)
  local order = {}

  for i = 1, #mascot.ACTS do
    order[i] = i
  end

  for i = #order, 2, -1 do
    local j = static.hash(epoch, i, 43) % i + 1

    order[i], order[j] = order[j], order[i]
  end

  return order
end

function mascot.act(step)
  local length = mascot.REST_STEPS + mascot.ACT_STEPS
  local cycle = math.floor(step / length)
  local at = step % length - mascot.REST_STEPS

  if at < 0 then return nil end

  local count = #mascot.ACTS
  local epoch = math.floor(cycle / count)
  local order = shuffled(epoch)

  if epoch > 0 and shuffled(epoch - 1)[count] == order[1] then
    order[1], order[2] = order[2], order[1]
  end

  return mascot.ACTS[order[cycle % count + 1]], at / mascot.ACT_STEPS, cycle
end

local function round(value)
  return math.floor(value + 0.5)
end

local ACT = {}

function ACT.drift(pose, p)
  local swing = math.cos(2 * math.pi * p)

  pose.dx = round(3 * math.sin(2 * math.pi * p))
  pose.look = { swing > 0.3 and 1 or swing < -0.3 and -1 or 0, 0 }
end

function ACT.glitch(pose, p, step)
  if p >= 0.9 or static.hash(step, 3, 47) >= 35 then return end

  pose.storm = 25
  pose.tear = function(y)
    if static.hash(math.floor(y / 3), step, 53) >= 40 then return 0 end

    return static.hash(y, step, 59) % 5 - 2
  end
  pose.look = { static.hash(step, 4, 61) % 3 - 1, static.hash(step, 5, 67) % 3 - 1 }
end

function ACT.jump(pose, p, _, cycle)
  local side = static.hash(cycle, 6, 71) % 2 == 0 and -4 or 4
  local phases = {
    { 0.25, 0, 'wane' },
    { 0.4, side, 'form' },
    { 0.6, side },
    { 0.75, side, 'wane' },
    { 0.9, 0, 'form' },
  }
  local from = 0

  for _, phase in ipairs(phases) do
    if p < phase[1] then
      local t = (p - from) / (phase[1] - from)

      pose.dx = phase[2]
      if phase[3] == 'wane' then pose.wane = t end
      if phase[3] == 'form' then pose.form = t end
      if phase[3] then pose.storm = 12 end

      return
    end

    from = phase[1]
  end
end

function ACT.roll(pose, p, step)
  if p < 0.1 or p >= 0.7 then return end

  local height = GRID[2]
  local dy = math.floor((p - 0.1) / 0.6 * 2 * height) % height

  pose.dy, pose.wrap, pose.storm = dy, true, 8
  pose.tear = function(y)
    local seam = (y + dy) % height

    if seam > 1 and seam < height - 2 then return 0 end

    return static.hash(y, step, 73) % 3 - 1
  end
end

function ACT.scan(pose, p)
  local row = ORIGIN[2] + math.floor(p * 2 * #mascot.ART) % #mascot.ART
  local sway = math.sin(4 * math.pi * p)

  pose.scan = row
  pose.look = {
    sway > 0.5 and 1 or sway < -0.5 and -1 or 0,
    row < ORIGIN[2] + EYE_ROWS[1] - 1 and -1 or row > ORIGIN[2] + EYE_ROWS[2] - 1 and 1 or 0,
  }
end

function mascot.pose(step, kind, form, wane)
  local lift = (kind == 'work' and wane == 0) and math.floor(step / BOB_STEPS) % 2 or 0
  local pose = { dx = 0, dy = lift, form = form, wane = wane, storm = 0 }

  if kind ~= 'work' or form < 1 or wane > 0 then return pose end

  local name, p, cycle = mascot.act(step)

  if name then
    pose.act = name
    ACT[name](pose, p, step, cycle)
  end

  return pose
end

function mascot.specks(bitmap, step, rgb, form, wane, storm)
  local density = 3 + (1 - form) * 22 + wane * (1 - wane) * 60 + (storm or 0)
  local at = math.floor(step / 2)

  for y = 0, GRID[2] - 1 do
    for x = 0, GRID[1] - 1 do
      if static.hash(x, y, at) < density then put(bitmap, x, y, rgb, 0.3) end
    end
  end
end

function mascot.body(bitmap, step, rgb, pose)
  for row, line in ipairs(mascot.ART) do
    for col = 1, #line do
      local cell = line:sub(col, col)
      local x, y = ORIGIN[1] + col - 1, ORIGIN[2] + row - 1

      if (cell == 'S' or cell == 's') and present(x, y, pose.form, pose.wane) then
        local h = static.hash(x, y, step)

        if pose.scan == y then
          place(bitmap, pose, x, y, rgb, 1)
        elseif cell == 'S' then
          place(bitmap, pose, x, y, rgb, 0.4 + h / 170)
        elseif h < 60 then
          place(bitmap, pose, x, y, rgb, 0.2 + h / 200)
        end
      elseif cell == 'f' and present(x, y, pose.form, pose.wane) then
        local h = static.hash(x, y, step)

        if h < 40 then place(bitmap, pose, x, y + static.hash(x, math.floor(step / 3), 79) % 2, rgb, 0.15 + h / 200) end
      end
    end
  end
end

function mascot.eyes(bitmap, step, kind, pose)
  if pose.form < 1 or pose.wane > 0.5 then return end

  local rgb = roles.rgb(mascot.EYES[kind] or mascot.EYES.work)
  local steady = kind ~= 'work'
  local shut = kind == 'fail' or (step % BLINK_EVERY < BLINK_STEPS)
  local glance = not steady and step % LOOK_EVERY >= LOOK_FROM and step % LOOK_EVERY < LOOK_FROM + LOOK_STEPS
  local look = pose.look or { glance and 1 or 0, 0 }

  for row = EYE_ROWS[1], EYE_ROWS[2] do
    local line = mascot.ART[row]

    for col = 1, #line do
      if line:sub(col, col) == 'e' and (not shut or row == EYE_ROWS[2]) then
        local y = ORIGIN[2] + row - 1

        place(bitmap, pose, ORIGIN[1] + col - 1 + look[1], y + look[2], rgb, 1)
      end
    end
  end
end

function mascot.draw(bitmap, step, kind, form, wane)
  local body = roles.rgb(mascot.BODY)
  local pose = mascot.pose(step, kind, form, wane)

  mascot.specks(bitmap, step, body, pose.form, pose.wane, pose.storm)
  mascot.body(bitmap, step, body, pose)
  mascot.eyes(bitmap, step, kind, pose)
end

local function rung(value, steps)
  return math.min(steps, math.ceil(motion.clamp(value) * steps)) / steps
end

local animation = Animation({
  cols = mascot.COLS,
  draw = function(bitmap, at, anim)
    local elapsed = anim:elapsed(at)
    local form = motion.clamp(elapsed / mascot.FORM_MS)
    local wane = motion.clamp((at - (anim.last_wanted or at) - mascot.GRACE_MS) / mascot.WANE_MS)

    if form >= 1 and wane <= 0 then
      mascot.draw(bitmap, motion.loop(elapsed, mascot.LOOP_STEPS), mood, 1, 0)
    else
      mascot.draw(bitmap, mascot.STILL_STEPS, mood, rung(form, mascot.FORM_RUNGS), rung(wane, mascot.WANE_RUNGS))
    end
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

local portrait

function mascot.still()
  if not Tile.available() then return nil end

  portrait = portrait or Tile.new(mascot.COLS, 1)
  portrait:paint(function(bitmap)
    mascot.draw(bitmap, mascot.STILL_STEPS, 'work', 1, 0)
  end)

  return portrait:chunks(1)
end

function mascot.stop()
  animation:stop()
  fed_by = nil
end

mascot.tint = tint

return mascot
