local MarkSpec = require('harness.transcript.MarkSpec')

return function(block)
  local out = {}

  if not block.error then return out end

  for row = block.start, block.start + #block.lines - 1 do
    MarkSpec.add(out, row, 0, { end_row = row + 1, hl_group = 'UiError', hl_eol = false })
  end

  return out
end
