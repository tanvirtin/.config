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
  UiMarkdownHeading = 'CursorLine',
  UiMarkdownHeading1 = '@markup.heading.1.markdown',
  UiMarkdownHeading2 = '@markup.heading.2.markdown',
  UiMarkdownHeading3 = '@markup.heading.3.markdown',
  UiMarkdownHeading4 = '@markup.heading.4.markdown',
  UiMarkdownHeading5 = '@markup.heading.5.markdown',
  UiMarkdownHeading6 = '@markup.heading.6.markdown',
  UiMarkdownCode = 'ColorColumn',
  UiMarkdownBullet = 'Special',
  UiMarkdownQuote = 'Comment',
  UiMarkdownRule = 'WinSeparator',
  UiMarkdownLink = 'Underlined',
  UiMarkdownChecked = 'DiagnosticOk',
  UiMarkdownUnchecked = 'Comment',
  UiTurnSeparator = 'WinSeparator',
  UiExternalChange = 'DiffChange',
  UiToolName = 'Function',
  UiDiffAdd = 'DiffAdd',
  UiDiffDelete = 'DiffDelete',
  UiDiffLineNr = 'LineNr',
  UiToolPending = 'DiagnosticInfo',
  UiToolDone = 'DiagnosticOk',
  UiToolFailed = 'DiagnosticError',
}

local function color(group, key)
  local ok, spec = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })

  return ok and spec[key] or nil
end

function hl.blend(fg, bg, alpha)
  local function channel(value, shift)
    return math.floor(value / 2 ^ shift) % 256
  end

  local out = 0

  for _, shift in ipairs({ 16, 8, 0 }) do
    local mixed = math.floor(channel(fg, shift) * alpha + channel(bg, shift) * (1 - alpha) + 0.5)
    out = out + mixed * 2 ^ shift
  end

  return out
end

hl.COMPUTED = {
  UiPrompt = function()
    local accent, background = color('UiAccent', 'fg'), color('Normal', 'bg')

    if not accent or not background then return { link = 'CursorLine' } end

    return { bg = hl.blend(accent, background, 0.1) }
  end,
  UiPromptBar = function()
    return { fg = color('UiAccent', 'fg'), bold = true }
  end,
  UiSpeakerUser = function()
    return { fg = color('UiAccent', 'fg'), bold = true }
  end,
  UiSpeakerAgent = function()
    return { fg = color('Function', 'fg'), bold = true }
  end,
}

function hl.define()
  for group, link in pairs(hl.GROUPS) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end

  for group, compute in pairs(hl.COMPUTED) do
    vim.api.nvim_set_hl(0, group, compute())
  end
end

hl.define()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('ui.hl', { clear = true }),
  callback = hl.define,
})

return hl
