local settings = require('harness.settings.content')

local eq = assert.are.same

describe('harness.settings.content:', function()
  it('should expose per-content defaults', function()
    eq('UiPath', settings:get('json').property)
    eq('UiToolName', settings:get('csv').header)
    eq('UiToolOutput', settings:get('csv').cell)
    eq(' │ ', settings:get('csv').separator)
    eq(12, settings:get('csv').max_columns)
    eq('UiPath', settings:get('markdown').table_cell)
  end)
end)
