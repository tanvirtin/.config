local lazy = require('core.lazy')
local settings = require('core.settings')

local event = lazy('core.event')
local hls_setting = settings.get('hls')

local highlight = {}

function highlight.get_hl_by_name(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

function highlight.set(group, spec)
  vim.api.nvim_set_hl(0, group, spec)

  return highlight
end

function highlight.terminal_color(n)
  return vim.g['terminal_color_' .. n]
end

function highlight.on_colorscheme(name, callback)
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup(name, { clear = true }),
    callback = callback,
  })

  return highlight
end

function highlight.define(group, color, force)
  if type(color) == 'string' then
    vim.api.nvim_exec2(string.format('highlight default link %s %s', group, color), {})

    return highlight
  end

  if type(color) == 'function' then color = color() end

  local gui = color.gui and 'gui = ' .. color.gui or 'gui = NONE'
  local fg = color.fg and 'guifg = ' .. color.fg or 'guifg = NONE'
  local bg = color.bg and 'guibg = ' .. color.bg or 'guibg = NONE'
  local sp = color.sp and 'guisp = ' .. color.sp or ''

  local default = (not force and color.override == false) and 'default ' or ''
  vim.api.nvim_exec2('highlight ' .. default .. group .. ' ' .. gui .. ' ' .. fg .. ' ' .. bg .. ' ' .. sp, {})

  return highlight
end

function highlight.register_module(dependency)
  hls_setting:for_each(function(hl, color)
    highlight.define(hl, color)
  end)

  if dependency then dependency() end

  return highlight
end

function highlight.register_events()
  event.on('ColorScheme', function()
    hls_setting:for_each(function(hl, color)
      highlight.define(hl, color)
    end)
  end)
end

return highlight
