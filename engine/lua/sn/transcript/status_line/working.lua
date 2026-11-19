local compact = require('compact')
local glyph = require('ui.design.glyph')
local theme = require('sn.transcript.theme')
local keymaps = require('sn.settings.keymaps')
local settings = require('sn.settings.transcript')

local working = { id = 'working', order = 50, exclusive = true }

function working.applies(state)
  return state.running == true or theme.waning(state.owner)
end

function working.lines(state, now)
  local request = (state.waiting or {})[1]

  if request then
    local line = { { ' ' } }

    vim.list_extend(line, theme.working(now, state.started, 'wait', state.owner))
    line[#line + 1] = { ' ' }

    return {
      vim.list_extend(line, {
        { 'waiting for you: ', 'UiWarn' },
        { compact.line(request.title or request.tool or 'a tool', settings:get('request_preview')), 'UiPromptBar' },
        { ' · answer the prompt, or ', 'UiMuted' },
        { keymaps:get('transcript').interrupt, 'UiAccent' },
        { ' to interrupt', 'UiMuted' },
      }),
    }
  end

  if not state.running then
    local pixels = theme.waning_chunks(state.owner, state.failed and 'fail' or nil)

    if not pixels then return {} end

    return { vim.list_extend({ { ' ' } }, pixels) }
  end

  local elapsed = state.started and now and theme.duration(now - state.started)
  local line = { { ' ' } }

  vim.list_extend(line, theme.working(now, state.started, state.failed and 'fail' or 'work', state.owner))

  return {
    vim.list_extend(line, {
      { elapsed and glyph.SEPARATOR .. elapsed or '', 'UiMuted' },
      { glyph.SEPARATOR, 'UiMuted' },
      { keymaps:get('transcript').interrupt, 'UiAccent' },
      { ' interrupt', 'UiMuted' },
    }),
  }
end

return working
