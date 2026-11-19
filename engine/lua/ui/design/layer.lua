local layer = {}

layer.ORDER = {
  'gutter',
  'decoration',
  'surface',
  'body',
  'highlight',
  'output',
  'link',
  'syntax',
  'line',
  'mark',
  'emphasis',
  'effect',
  'animation',
}

layer.PRIORITY = {
  gutter = 10,
  decoration = 20,
  surface = 50,
  body = 90,
  highlight = 100,
  output = 120,
  link = 190,
  syntax = 200,
  line = 250,
  mark = 300,
  emphasis = 350,
  effect = 400,
  animation = 4000,
}

function layer.of(name)
  local priority = layer.PRIORITY[name]

  if not priority then
    error(string.format('unknown layer %s (%s)', tostring(name), table.concat(layer.ORDER, ', ')), 2)
  end

  return priority
end

function layer.above(name, steps)
  return layer.of(name) + (steps or 1)
end

return layer
