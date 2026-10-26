local Config = require('core.Config')

return Config({
  json = {
    property = 'UiPath',
  },
  csv = {
    header = 'UiToolName',
    cell = 'UiToolOutput',
    separator = ' │ ',
    max_columns = 12,
  },
  markdown = {
    table_cell = 'UiPath',
  },
})
