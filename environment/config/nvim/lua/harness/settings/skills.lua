local Config = require('core.Config')

return Config({
  command = { 'tin', 'artifact', 'export' },
  artifacts = '~/.config/tin/artifacts',
})
