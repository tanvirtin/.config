local hl = {}

hl.GROUPS = {
  UiNormal = 'NormalFloat',
  UiBorder = 'FloatBorder',
  UiTitle = 'Title',
  UiSelected = 'CursorLine',
  UiMuted = 'Comment',
  UiAccent = 'Special',
  UiPath = 'Directory',
  UiLineNr = 'LineNr',
  UiMatch = 'Search',
  UiAdded = 'Added',
  UiChanged = 'Changed',
  UiRemoved = 'Removed',
  UiError = 'DiagnosticError',
  UiWarn = 'DiagnosticWarn',
  UiInfo = 'DiagnosticInfo',
  UiHint = 'DiagnosticHint',
}

function hl.define()
  for group, link in pairs(hl.GROUPS) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

hl.define()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('ui.hl', { clear = true }),
  callback = hl.define,
})

return hl
