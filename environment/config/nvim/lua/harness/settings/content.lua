local Config = require('core.Config')

return Config({
  json = {
    property = 'UiPath',
  },
  csv = {
    header = 'UiToolName',
    cell = 'auto',
    separator = ' │ ',
    max_columns = 12,
  },
})
