local config = require('config')

return {
  {
    'williamboman/mason.nvim',
    cmd = 'Mason',
    build = ':MasonUpdate',
    opts = {},
  },
  {
    'williamboman/mason-lspconfig.nvim',
    dependencies = { 'williamboman/mason.nvim' },
    lazy = true,
    opts = {
      ensure_installed = config.lsp_servers,
      automatic_installation = true,
      automatic_enable = false,
    },
  },
  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    dependencies = { 'williamboman/mason.nvim' },
    event = 'VeryLazy',
    opts = {
      ensure_installed = config.mason_tools,
      auto_update = false,
      run_on_start = true,
    },
    config = function(_, opts)
      local installer = require('mason-tool-installer')

      installer.setup(opts)
      installer.run_on_start()
    end,
  },
}
