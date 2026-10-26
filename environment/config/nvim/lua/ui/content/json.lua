local hit_test = require('harness.ui.hit_test')
local Renderer = require('ui.markdown.Renderer')

hit_test.bind('json', function(block, row, col)
  local line = block.lines and block.lines[row - block.start + 1]

  if not line or line == '' then return nil end

  for _, span in ipairs(Renderer.syntax(line, 'json')) do
    if col >= span[1] and col < span[2] then return { text = line:sub(span[1] + 1, span[2]), group = span[3] } end
  end
end)
