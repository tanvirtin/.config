local Window = require('core.Window')
local Camera = require('ui.anim.Camera')
local Curtain = require('ui.anim.Curtain')
local Layer = require('ui.anim.Layer')
local Particles = require('ui.anim.Particles')
local Shape = require('ui.anim.Shape')
local Sprite = require('ui.anim.Sprite')
local Stage = require('ui.anim.Stage')
local TextFx = require('ui.anim.TextFx')
local Track = require('ui.anim.Track')
local presets = require('ui.anim.presets')

local spec = {}

spec.MAX_ACTORS = 24
spec.TYPES = { 'sprite', 'emitter', 'shape', 'text', 'camera', 'curtain' }

local function fail(index, message)
  error(string.format('actor %d: %s', index, message), 0)
end

local function axis(name)
  if name == 'y' then return Window.screen_height() - 1 end

  return Window.screen_width()
end

local function resolve(value, name)
  if type(value) == 'number' then return value end

  local percent = type(value) == 'string' and value:match('^(%-?%d+%.?%d*)%%$')

  if percent then return math.floor(axis(name) * tonumber(percent) / 100 + 0.5) end

  error(string.format('%s is not a number or a percentage like "50%%"', vim.inspect(value)), 0)
end

local function point(value, what)
  if type(value) ~= 'table' or #value ~= 2 then error(what .. ' must be [x, y]', 0) end

  return { resolve(value[1], 'x'), resolve(value[2], 'y') }
end

local function keys(raw, name)
  return vim.tbl_map(function(key)
    if type(key) ~= 'table' then error('a keyframe is [ms, value] or [ms, value, ease]', 0) end

    return { key[1], resolve(key[2], name), key[3] }
  end, raw)
end

local function sprite_tracks(actor, at)
  local tracks = {}

  for _, name in ipairs({ 'x', 'y' }) do
    if actor[name] then tracks[name] = Track.new(keys(actor[name], name)) end
  end

  if actor.to then
    local to = point(actor.to, 'to')
    local from_ms, ms = actor.from_ms or 0, actor.ms or 800
    local ease = actor.ease or 'in_out'

    tracks.x = tracks.x or Track.new({ { from_ms, at[1] }, { from_ms + ms, to[1], ease } })
    tracks.y = tracks.y or Track.new({ { from_ms, at[2] }, { from_ms + ms, to[2], ease } })
  end

  if type(actor.blend) == 'table' then tracks.blend = Track.new(actor.blend) end

  if actor.fade then
    local fade_ms = actor.fade_ms or 400
    local last = actor.ms and (actor.from_ms or 0) + actor.ms or actor.life_ms or 1500
    local frames

    if actor.fade == 'in' or actor.fade == 'inout' then
      frames = { { 0, 100 }, { fade_ms, 0 } }
    else
      frames = { { 0, 0 } }
    end

    if actor.fade == 'out' or actor.fade == 'inout' then
      vim.list_extend(frames, { { math.max(last - fade_ms, fade_ms), 0 }, { last, 100 } })
    end

    tracks.blend = Track.new(frames)
  end

  return tracks
end

local BUILD = {}

function BUILD.sprite(actor)
  if not actor.lines and not actor.frames then error('a sprite needs lines or frames', 0) end

  local at = point(actor.at or { '50%', '50%' }, 'at')
  local copy = vim.tbl_extend('force', actor, { at = at, blend = type(actor.blend) == 'number' and actor.blend or nil })

  return Sprite.new(copy, sprite_tracks(actor, at))
end

function BUILD.shape(actor, _, layer)
  if not layer then error('shapes need a terminal that speaks the kitty graphics protocol, outside tmux', 0) end

  local at = point(actor.at or { '50%', '50%' }, 'at')
  local copy = vim.tbl_extend('force', actor, { at = at })
  local tracks = sprite_tracks(vim.tbl_extend('force', actor, { blend = false, fade = false }), at)

  if actor['end'] then
    local last = point(actor['end'], 'end')

    copy.x2, copy.y2 = copy.x2 or last[1], copy.y2 or last[2]
  end

  for _, name in ipairs({ 'x2', 'y2' }) do
    if type(copy[name]) == 'table' then copy[name] = keys(copy[name], name:sub(1, 1)) end
  end

  return Shape.new(copy, tracks, layer)
end

function BUILD.emitter(actor, scene_ms, layer)
  local copy = vim.tbl_extend('force', actor, { at = point(actor.at or { '50%', '50%' }, 'at') })

  if copy.spread then copy.spread = resolve(copy.spread, 'x') end
  if copy.rate and copy.rate > 0 and not copy.stop_ms then copy.stop_ms = scene_ms end

  return Particles.new(copy, layer)
end

function BUILD.text(actor)
  if not vim.tbl_contains(TextFx.EFFECTS, actor.effect) then
    error(string.format('unknown text effect %s (%s)', tostring(actor.effect), table.concat(TextFx.EFFECTS, ', ')), 0)
  end

  return TextFx.new(actor, Window.get_current())
end

function BUILD.camera(actor)
  return Camera.new(actor, Window.get_current())
end

function BUILD.curtain(actor)
  local blend = actor.blend

  if type(blend) == 'number' then blend = { { 0, blend } } end
  if not blend then error('a curtain needs blend: [[ms, 0-100], ...] (100 is invisible)', 0) end

  return Curtain.new(actor, Track.new(blend))
end

function spec.expand(scene)
  if type(scene) ~= 'table' then error('a scene is an object: { preset } or { actors: [...] }', 0) end

  if not scene.preset then return scene end

  local base = presets[scene.preset]

  if type(base) ~= 'table' then
    error(string.format('unknown preset %s (%s)', tostring(scene.preset), table.concat(presets.names(), ', ')), 0)
  end

  local expanded = vim.deepcopy(base)

  for key, value in pairs(scene) do
    if key ~= 'preset' and key ~= 'actors' then expanded[key] = value end
  end

  for _, extra in ipairs(scene.actors or {}) do
    expanded.actors[#expanded.actors + 1] = extra
  end

  if scene.at then
    for _, actor in ipairs(expanded.actors) do
      if actor.type == 'emitter' or actor.type == 'shape' then actor.at = scene.at end
    end
  end

  return expanded
end

function spec.build(scene, opts)
  scene = spec.expand(scene)

  local list = scene.actors

  if type(list) ~= 'table' or #list == 0 then error('a scene needs actors: [...] or a preset', 0) end
  if #list > spec.MAX_ACTORS then error(string.format('at most %d actors', spec.MAX_ACTORS), 0) end

  local scene_ms = scene.duration_ms or 2000
  local actors = {}
  local layer = scene.pixels ~= false and Layer.available() and Layer.new({ front = scene.front }) or nil

  local ok, err = pcall(function()
    for index, actor in ipairs(list) do
      local build = BUILD[actor.type]

      if not build then
        fail(index, string.format('unknown type %s (%s)', tostring(actor.type), table.concat(spec.TYPES, ', ')))
      end

      local made, problem = pcall(build, actor, scene_ms, layer)

      if not made then fail(index, tostring(problem)) end

      actors[#actors + 1] = problem
    end
  end)

  if not ok then
    for _, actor in ipairs(actors) do
      pcall(actor.destroy, actor)
    end

    error(err, 0)
  end

  return Stage.new(actors, {
    fps = scene.fps,
    duration_ms = scene.duration_ms,
    loop = scene.loop,
    layer = layer,
    on_done = opts and opts.on_done,
  })
end

return spec
