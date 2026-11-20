local color = {}

color.ROLE = {
  ['text'] = 'Normal',
  ['text.muted'] = 'Comment',
  ['text.accent'] = 'Special',
  ['text.title'] = 'Title',
  ['text.path'] = 'Directory',
  ['text.link'] = 'Underlined',
  ['text.function'] = 'Function',
  ['surface.background'] = 'NormalFloat',
  ['element.selected'] = 'CursorLine',
  ['border'] = 'FloatBorder',
  ['line_number'] = 'LineNr',
  ['success'] = 'DiagnosticOk',
  ['error'] = 'DiagnosticError',
  ['warning'] = 'DiagnosticWarn',
  ['info'] = 'DiagnosticInfo',
  ['hint'] = 'DiagnosticHint',
  ['created'] = 'Added',
  ['deleted'] = 'Removed',
}

color.MIX = {
  surface = 0.05,
  elevated = 0.09,
  tint = 0.1,
  code = 0.12,
  border = 0.16,
  flash = 0.24,
  rule = 0.3,
  fade = 0.45,
  glint = 0.6,
  thought = 0.62,
  thought_stream = 0.18,
}

color.THOUGHT_FADE = { 0.65, 0.35 }

color.CONTRAST = 3

function color.source(role)
  local group = color.ROLE[role]

  if not group then error(string.format('unknown colour role %s', tostring(role)), 2) end

  return group
end

return color
