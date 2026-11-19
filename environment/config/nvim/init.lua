if vim.async == nil then error('tin neovim is outdated') end

vim.g.tin_engine = vim.fs.normalize(vim.fn.resolve(vim.fn.stdpath('config')) .. '/../../../engine')
vim.opt.rtp:prepend(vim.g.tin_engine)

require('config.options')
require('config.lazy')
require('config.keymaps')
require('config.autocmds')
require('config.diagnostics')
require('surfaces.select').setup()
require('sn').setup()
