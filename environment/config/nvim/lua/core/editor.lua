local Window = require('core.Window')

local editor = {}

function editor.mode()
  return vim.api.nvim_get_mode().mode
end

function editor.tab_number()
  return vim.fn.tabpagenr()
end

function editor.tab_count()
  return vim.fn.tabpagenr('$')
end

function editor.tabs()
  local tabs = {}

  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    tabs[#tabs + 1] = {
      number = vim.api.nvim_tabpage_get_number(tab),
      windows = vim.tbl_map(Window, vim.api.nvim_tabpage_list_wins(tab)),
    }
  end

  return tabs
end

function editor.command_exists(name)
  return vim.fn.exists(':' .. name) == 2
end

function editor.run(command, args)
  return pcall(vim.api.nvim_cmd, { cmd = command, args = args or {} }, {})
end

function editor.exec(command)
  return vim.api.nvim_exec2(command, { output = true }).output
end

function editor.press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'mx', false)
end

return editor
