local lazy = require('core.lazy')

return {
  color = lazy('ui.design.color'),
  glyph = lazy('ui.design.glyph'),
  layer = lazy('ui.design.layer'),
  motion = lazy('ui.design.motion'),
  static = lazy('ui.design.static'),
}
