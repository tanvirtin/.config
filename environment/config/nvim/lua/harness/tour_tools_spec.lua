local tools = require('nvim_mcp.tools')
local tour_store = require('harness.tour_store')
local tour_tools = require('harness.tour_tools')

local eq = assert.are.same

describe('harness.tour_tools:', function()
  before_each(function()
    tour_store.reset()
    tour_tools.register()
  end)

  after_each(function()
    tour_store.reset()
    tools.unregister('tour')
  end)

  it('registers a tour_start tool the agent can read about', function()
    local definition = vim.tbl_filter(function(entry)
      return entry.name == 'tour_start'
    end, tools.definitions())[1]

    assert.truthy(definition)
    assert.truthy(definition.summary:find('Walk the user through', 1, true))
  end)

  it('hands a valid tour to the store and says how many steps it holds', function()
    local seen

    tour_store.on(function(kind, tour)
      seen = { kind, tour.title, #tour.steps }
    end)

    local result = tools.run('tour_start', {
      title = 'Config',
      steps = { { path = 'init.lua', line = 1, note = 'Start here.' } },
    })

    eq({ 'start', 'Config', 1 }, seen)
    eq({ title = 'Config', steps = 1 }, result)
  end)

  it('tells the agent which step has a path that does not exist', function()
    local ok, err = pcall(tools.run, 'tour_start', {
      title = 'Bad',
      steps = { { path = 'init.lua', line = 1 }, { path = 'no/such/file.lua', line = 3 } },
    })

    eq(false, ok)
    assert.truthy(tostring(err):find('step 2: no file no/such/file.lua', 1, true))
    eq(nil, tour_store.current())
  end)
end)
