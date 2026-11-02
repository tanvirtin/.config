local function map(mode, key, action, opts)
  opts = opts or {}
  opts.noremap = true
  opts.silent = true
  vim.keymap.set(mode, key, action, opts)
end

-- prefixes

map('n', '<Space>', '<NOP>')
map('n', ',', '<NOP>')

-- editing

map('v', '<', '<gv', { desc = 'Indent, keeping the selection' })
map('v', '>', '>gv', { desc = 'Outdent, keeping the selection' })

map('x', 'K', ':move \'<-2<CR>gv-gv', { desc = 'Move the selection up' })
map('x', 'J', ':move \'>+1<CR>gv-gv', { desc = 'Move the selection down' })

map('n', 'n', 'nzzzv', { desc = 'Next match, centred' })
map('n', 'N', 'Nzzzv', { desc = 'Previous match, centred' })

map('n', '<leader>d', '"_d', { desc = 'Delete to the void register' })
map('v', '<leader>d', '"_d', { desc = 'Delete to the void register' })

map('n', '<leader>c', '<Cmd>noh<CR>', { desc = 'Clear search highlight' })

map('n', '<leader>f', function()
  require('conform').format({ async = true, lsp_fallback = true })
end, { desc = 'Format the buffer' })

map('n', '<leader><leader>', '<Cmd>w<CR>', { desc = 'Write the buffer' })

map('n', '<leader><ESC>', '<Cmd>q<CR>', { desc = 'Quit' })
map('v', '<leader><ESC>', '<Cmd>q<CR>', { desc = 'Quit' })

-- windows and buffers

map('n', '\\', '<Cmd>winc w<CR>', { desc = 'Next window' })

map('n', '<leader>q', '<Cmd>bp | sp | bn | bd<CR>', { desc = 'Close the buffer, keeping the window' })

map('n', '<C-h>', '<Cmd>bp<CR>', { desc = 'Previous buffer' })
map('n', '<C-l>', '<Cmd>bn<CR>', { desc = 'Next buffer' })

map('n', '<C-w>', '<Cmd>cp<CR>', { desc = 'Previous quickfix entry' })
map('n', '<C-s>', '<Cmd>cn<CR>', { desc = 'Next quickfix entry' })

-- pickers

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

map('n', '<C-p>', pick('Files', 'files'), { desc = 'Find files' })
map('n', '<leader>/', pick('Grep', 'grep'), { desc = 'Search the project' })
map('n', '<leader>b', pick('Buffers', 'buffers'), { desc = 'Switch buffer' })

map('n', '<leader><space>', function()
  local pickers = require('snacks').picker.get({ source = 'explorer' })

  if #pickers > 0 then
    pickers[1]:close()
  else
    require('snacks').explorer()
  end
end, { desc = 'Toggle the explorer' })

-- lsp

map('n', '<leader>ld', pick('Definitions', 'lsp', at_cursor('definition')), { desc = 'Definitions' })
map('n', '<leader>lr', pick('References', 'lsp', at_cursor('references')), { desc = 'References' })
map('n', '<leader>lt', pick('Type definitions', 'lsp', at_cursor('type_definition')), { desc = 'Type definitions' })
map('n', '<leader>li', pick('Implementations', 'lsp', at_cursor('implementation')), { desc = 'Implementations' })
map('n', '<leader>lj', function()
  vim.diagnostic.goto_next({ wrap = true, float = true })
end, { desc = 'Next diagnostic' })
map('n', '<leader>lk', function()
  vim.diagnostic.goto_prev({ wrap = true, float = true })
end, { desc = 'Previous diagnostic' })
map('n', '<leader>ls', function()
  vim.lsp.buf.hover()
end, { desc = 'Hover' })
map('n', '<leader>ln', function()
  vim.lsp.buf.rename()
end, { desc = 'Rename' })
map('n', '<leader>le', function()
  vim.diagnostic.open_float()
end, { desc = 'Diagnostic under the cursor' })
map('n', '<leader>lq', function()
  vim.diagnostic.setqflist()
end, { desc = 'Diagnostics to quickfix' })
map('n', '<leader>lD', pick('Diagnostics', 'diagnostics'), { desc = 'Diagnostics picker' })

-- git

map('n', '<leader>gs', '<Cmd>VGit buffer_hunk_stage<CR>', { desc = 'Stage hunk' })
map('n', '<leader>gr', '<Cmd>VGit buffer_hunk_reset<CR>', { desc = 'Reset hunk' })
map('n', '<leader>gp', '<Cmd>VGit hunk<CR>', { desc = 'Preview hunk' })

map('n', '<leader>gS', '<Cmd>VGit buffer_stage<CR>', { desc = 'Stage buffer' })
map('n', '<leader>gU', '<Cmd>VGit buffer_unstage<CR>', { desc = 'Unstage buffer' })
map('n', '<leader>gu', '<Cmd>VGit buffer_reset<CR>', { desc = 'Reset buffer' })

map('n', '<leader>gb', '<Cmd>VGit blame<CR>', { desc = 'Blame' })
map('n', '<leader>gf', '<Cmd>VGit diff --buffer<CR>', { desc = 'Diff buffer' })
map('n', '<leader>gh', '<Cmd>VGit log<CR>', { desc = 'Log' })
map('n', '<leader>gd', '<Cmd>VGit status<CR>', { desc = 'Status' })
map('n', '<leader>gls', '<Cmd>VGit diff --staged<CR>', { desc = 'Diff staged' })
map('n', '<leader>gt', '<Cmd>VGit status<CR>', { desc = 'Status' })

map('n', '<leader>gg', '<Cmd>VGit toggle_live_blame<CR>', { desc = 'Toggle live blame' })
map('n', '<leader>gG', '<Cmd>VGit toggle_live_gutter<CR>', { desc = 'Toggle live gutter' })
map('n', '<leader>gx', '<Cmd>VGit toggle_diff_preference<CR>', { desc = 'Toggle diff preference' })

map('n', '<leader>gcc', '<Cmd>VGit buffer_conflict_accept_current<CR>', { desc = 'Conflict: accept current' })
map('n', '<leader>gci', '<Cmd>VGit buffer_conflict_accept_incoming<CR>', { desc = 'Conflict: accept incoming' })
map('n', '<leader>gcb', '<Cmd>VGit buffer_conflict_accept_both<CR>', { desc = 'Conflict: accept both' })

-- selection

map(
  'v',
  '<leader>sy',
  '<Esc><Cmd>lua require("core.selection").yank()<CR>',
  { desc = 'Yank the selection for the agent' }
)
map(
  'v',
  '<leader>sa',
  '<Esc><Cmd>lua require("core.selection").add()<CR>',
  { desc = 'Add the selection for the agent' }
)
map('n', '<leader>sf', '<Cmd>lua require("core.selection").flush()<CR>', { desc = 'Flush the selection' })
map('n', '<leader>sc', '<Cmd>lua require("core.selection").clear()<CR>', { desc = 'Clear the selection' })

-- agent: enter a session and housekeeping; the transcript carries the rest

map('n', '<leader>.', '<Cmd>HarnessSessions<CR>', { desc = 'Sessions' })

map('n', '<leader>aw', function()
  require('harness.ui.status').to_waiting()
end, { desc = 'Go to the waiting request' })

map('v', '<leader>aa', function()
  require('harness.ui.commands').attach_visual()
end, { desc = 'Attach the selection' })
