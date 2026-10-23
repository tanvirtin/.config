local function map(mode, key, action, opts)
  opts = opts or {}
  opts.noremap = true
  opts.silent = true
  vim.keymap.set(mode, key, action, opts)
end

map('n', '<Space>', '<NOP>')
map('n', ',', '<NOP>')

map('v', '<', '<gv')
map('v', '>', '>gv')

map('x', 'K', ':move \'<-2<CR>gv-gv')
map('x', 'J', ':move \'>+1<CR>gv-gv')

map('n', 'n', 'nzzzv')
map('n', 'N', 'Nzzzv')

map('n', '\\', '<Cmd>winc w<CR>')

map('n', '<leader>q', '<Cmd>bp | sp | bn | bd<CR>')

map('v', '<leader><ESC>', '<Cmd>q<CR>')
map('n', '<leader><ESC>', '<Cmd>q<CR>')

map('v', '<leader>d', '"_d')
map('n', '<leader>d', '"_d')

map('n', '<leader>c', '<Cmd>noh<CR>')

map('n', '<leader>f', function()
  require('conform').format({ async = true, lsp_fallback = true })
end)

map('n', '<leader><leader>', '<Cmd>w<CR>')

map('n', '<C-w>', '<Cmd>cp<CR>')
map('n', '<C-s>', '<Cmd>cn<CR>')

map('n', '<C-h>', '<Cmd>bp<CR>')
map('n', '<C-l>', '<Cmd>bn<CR>')

map('n', '<leader><space>', function()
  local pickers = require('snacks').picker.get({ source = 'explorer' })

  if #pickers > 0 then
    pickers[1]:close()
  else
    require('snacks').explorer()
  end
end)

local function pick(title, source, source_opts)
  return function()
    require('surfaces').pick({ title = title, source = source, source_opts = source_opts and source_opts() })
  end
end

local function at_cursor(method)
  return function()
    local cursor = vim.api.nvim_win_get_cursor(0)

    return { method = method, buf = vim.api.nvim_get_current_buf(), line = cursor[1], col = cursor[2] + 1 }
  end
end

map('n', '<C-p>', pick('Files', 'files'))
map('n', '<leader>/', pick('Grep', 'grep'))

map('n', '<leader>ld', pick('Definitions', 'lsp', at_cursor('definition')))
map('n', '<leader>lr', pick('References', 'lsp', at_cursor('references')))
map('n', '<leader>lt', pick('Type definitions', 'lsp', at_cursor('type_definition')))
map('n', '<leader>li', pick('Implementations', 'lsp', at_cursor('implementation')))
map('n', '<leader>lj', function()
  vim.diagnostic.goto_next({ wrap = true, float = true })
end)
map('n', '<leader>lk', function()
  vim.diagnostic.goto_prev({ wrap = true, float = true })
end)
map('n', '<leader>ls', function()
  vim.lsp.buf.hover()
end)
map('n', '<leader>ln', function()
  vim.lsp.buf.rename()
end)
map('n', '<leader>le', function()
  vim.diagnostic.open_float()
end)
map('n', '<leader>lq', function()
  vim.diagnostic.setqflist()
end)
map('n', '<leader>lD', pick('Diagnostics', 'diagnostics'))
map('n', '<leader>b', pick('Buffers', 'buffers'))

map('n', '<leader>.', function()
  require('harness.ui.commands').sessions()
end)
map('n', '<leader>aa', function()
  require('harness.ui.commands').sessions()
end)
map('n', '<leader>an', function()
  require('harness.ui.commands').new()
end)
map('v', '<leader>aa', function()
  require('harness.ui.composer').attach_visual()
end)

map('n', '<leader>gs', '<Cmd>VGit buffer_hunk_stage<CR>')
map('n', '<leader>gr', '<Cmd>VGit buffer_hunk_reset<CR>')
map('n', '<leader>gp', '<Cmd>VGit hunk<CR>')

map('n', '<leader>gS', '<Cmd>VGit buffer_stage<CR>')
map('n', '<leader>gU', '<Cmd>VGit buffer_unstage<CR>')
map('n', '<leader>gu', '<Cmd>VGit buffer_reset<CR>')

map('n', '<leader>gb', '<Cmd>VGit blame<CR>')
map('n', '<leader>gf', '<Cmd>VGit diff --buffer<CR>')
map('n', '<leader>gh', '<Cmd>VGit log<CR>')
map('n', '<leader>gd', '<Cmd>VGit status<CR>')
map('n', '<leader>gls', '<Cmd>VGit diff --staged<CR>')
map('n', '<leader>gt', '<Cmd>VGit status<CR>')

map('n', '<leader>gg', '<Cmd>VGit toggle_live_blame<CR>')
map('n', '<leader>gG', '<Cmd>VGit toggle_live_gutter<CR>')
map('n', '<leader>gx', '<Cmd>VGit toggle_diff_preference<CR>')

map('n', '<leader>gcc', '<Cmd>VGit buffer_conflict_accept_current<CR>')
map('n', '<leader>gci', '<Cmd>VGit buffer_conflict_accept_incoming<CR>')
map('n', '<leader>gcb', '<Cmd>VGit buffer_conflict_accept_both<CR>')

map('v', '<leader>sy', '<Esc><Cmd>lua require("core.selection").yank()<CR>')
map('v', '<leader>sa', '<Esc><Cmd>lua require("core.selection").add()<CR>')
map('n', '<leader>sf', '<Cmd>lua require("core.selection").flush()<CR>')
map('n', '<leader>sc', '<Cmd>lua require("core.selection").clear()<CR>')
