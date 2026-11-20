local glyph = {}

glyph.SEPARATOR = ' · '
glyph.DOT = '·'
glyph.PROMPT = '❯'
glyph.FILE = '󰈔'

glyph.STATUS = {
  done = '✓',
  failed = '✗',
  pending = '○',
  partial = '◐',
  running = '⠶',
  attention = '◆',
  selected = '◉',
  current = '●',
  more = '⋯',
  info = 'ℹ',
  hint = '◇',
  warning = '!',
}

glyph.BULLETS = { '•', '◦', '▪', '▫' }

glyph.ACTION = {
  add = '+',
  back = '←',
}

glyph.TREE = {
  gutter = '│',
  branch = '├',
  branch_end = '└',
}

glyph.LINE = {
  rule = '─',
  heavy = '━',
  dashed = '┄',
  dotted = '┈',
  rail = '▎',
  bar = '│',
}

glyph.BOX = {
  top_left = '╭',
  top_right = '╮',
  bottom_left = '╰',
  bottom_right = '╯',
  horizontal = '─',
  vertical = '│',
}

glyph.GRID = {
  top = { '┌', '┬', '┐' },
  middle = { '├', '┼', '┤' },
  bottom = { '└', '┴', '┘' },
  vertical = '│',
  horizontal = '─',
}

function glyph.join(parts)
  return table.concat(parts, glyph.SEPARATOR)
end

return glyph
