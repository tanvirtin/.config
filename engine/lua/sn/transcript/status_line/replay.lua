local glitch = require('ui.glitch')
local motion = require('ui.motion')
local glyph = require('ui.design.glyph')
local theme = require('sn.transcript.theme')

local loading = { id = 'loading', order = 30, exclusive = true }

loading.SNOW_ROWS = 6
loading.SNOW_WIDTH = 72

function loading.applies(state)
  return state.loading == true and not state.running
end

function loading.lines(state, now)
  local rows = {
    vim.list_extend({ theme.loader('loading', now) }, {
      { 'loading', 'UiAccent' },
      { glyph.SEPARATOR .. 'the agent is replaying this session', 'UiMuted' },
    }),
  }

  if theme.reduced() then return rows end

  local width = math.max(8, math.min(state.width or loading.SNOW_WIDTH, loading.SNOW_WIDTH) - 2)
  local seed = motion.step(now)

  for row = 1, loading.SNOW_ROWS do
    rows[#rows + 1] = { { ' ' .. glitch.snow(width, seed, row), 'UiMuted' } }
  end

  return rows
end

return loading
