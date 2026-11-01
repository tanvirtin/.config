local Fades = require('harness.ui.Fades')
local Flashes = require('harness.ui.Flashes')
local Collapse = require('harness.ui.Collapse')

local transcript_motion = {}

local effects = {}

function transcript_motion.unregister(id)
  for index, existing in ipairs(effects) do
    if existing.id == id then
      table.remove(effects, index)
      break
    end
  end

  return transcript_motion
end

function transcript_motion.register(effect)
  transcript_motion.unregister(effect.id)
  effects[#effects + 1] = effect

  return transcript_motion
end

function transcript_motion.effects()
  return vim.list_slice(effects)
end

local function run(view, id)
  view.animator:add(id, function(now)
    return view.buffer:is_valid() and view.effects[id]:step(now)
  end)
end

function transcript_motion.attach(view)
  view.effects = {}

  for _, effect in ipairs(effects) do
    view.effects[effect.id] = effect.create(view)
  end

  return view
end

function transcript_motion.before(view, state)
  for _, effect in ipairs(effects) do
    local instance = view.effects[effect.id]

    if instance.before and instance:before(state) then run(view, effect.id) end
  end
end

function transcript_motion.settle(view)
  for _, effect in ipairs(effects) do
    local instance = view.effects[effect.id]

    if instance.observe and instance:observe() then run(view, effect.id) end
  end
end

function transcript_motion.reveal(view, row)
  if view.effects.fade:reveal(row) then run(view, 'fade') end
end

for _, effect in ipairs({
  {
    id = 'collapse',
    create = function(view)
      return Collapse(view)
    end,
  },
  {
    id = 'fade',
    create = function(view)
      return Fades(view.buffer, view)
    end,
  },
  {
    id = 'flash',
    create = function(view)
      return Flashes(view.buffer, view)
    end,
  },
}) do
  transcript_motion.register(effect)
end

return transcript_motion
