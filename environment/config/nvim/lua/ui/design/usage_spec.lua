local eq = assert.are.same

local ROOTS = { 'lua/ui', 'lua/harness', 'lua/surfaces', 'lua/nvim_mcp', 'lua/sources' }

local RULES = {
  { pattern = '[Pp][Rr][Ii][Oo][Rr][Ii][Tt][Yy]%s*=%s*%d', says = 'a raw extmark priority; use ui.design.layer' },
  { pattern = 'DENSITY%s*=%s*0?%.%d', says = 'a raw static density; use a ui.design.static preset' },
  { pattern = 'glitch%.%a+%([^,]+,%s*[%d.]+%s*[,)]', says = 'a raw density passed to glitch; use a preset' },
  { pattern = 'scramble%([^,]+,%s*[%d.]+%s*[*,)]', says = 'a raw density passed to glitch; use a preset' },
  { pattern = '\' · \'', says = 'a raw separator; use ui.design.glyph.SEPARATOR or glyph.join' },
}

local GLYPHS =
  { '✓', '✗', '○', '◆', '◐', '◉', '⋯', '❯', '▎', '━', '┄', '┈', '╭', '╮', '╰', '╯' }

local function raw_glyph(line)
  for literal in line:gmatch('\'([^\']*)\'') do
    for _, glyph in ipairs(GLYPHS) do
      if literal:find(glyph, 1, true) then return true end
    end
  end

  return false
end

local ALLOWED = {
  ['lua/harness/transcript/model/content/builtin.lua'] = 'orders content handlers, not extmarks',
  ['lua/harness/transcript/model/output_style.lua'] = 'matches glyphs that tools print, it does not draw them',
  ['lua/ui/anim/presets.lua'] = 'is particle art for ui_animate',
  ['lua/ui/pixel/components/ring.lua'] = 'draws its own fill frames as a text fallback',
}

local function offences(path)
  local found = {}

  for number, line in ipairs(vim.fn.readfile(path)) do
    for _, rule in ipairs(RULES) do
      if line:find(rule.pattern) then
        found[#found + 1] = string.format('%s:%d %s', path, number, rule.says)
        break
      end
    end

    if raw_glyph(line) then
      found[#found + 1] = string.format('%s:%d a raw glyph; use ui.design.glyph', path, number)
    end
  end

  return found
end

describe('ui.design usage:', function()
  it('draws every priority and static density from the design tokens', function()
    local found = {}

    for _, root in ipairs(ROOTS) do
      for _, path in ipairs(vim.fn.globpath(root, '**/*.lua', false, true)) do
        local exempt = path:match('_spec%.lua$') or path:find('^lua/ui/design/') or ALLOWED[path]

        if not exempt then vim.list_extend(found, offences(path)) end
      end
    end

    eq({}, found)
  end)

  it('names only files that exist in its allow list', function()
    for path in pairs(ALLOWED) do
      eq(1, vim.fn.filereadable(path), path)
    end
  end)
end)
