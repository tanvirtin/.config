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

  describe('tour_update', function()
    local function start()
      tour_store.start({ title = 'Config', steps = { { title = 'one' } } })
    end

    it('passes parsed steps to whoever follows the tour', function()
      local seen

      start()
      tour_store.on(function(kind, _, update)
        if kind == 'update' then seen = update end
      end)

      local result = tools.run('tour_update', {
        mode = 'insert',
        steps = { { path = 'init.lua', line = 2, note = 'More.' } },
      })

      eq('insert', seen.mode)
      eq(1, #seen.steps)
      eq(2, seen.steps[1].line)
      eq({ title = 'Config', steps = 1 }, result)
    end)

    it('rewrites a note without needing steps', function()
      local seen

      start()
      tour_store.on(function(kind, _, update)
        if kind == 'update' then seen = update end
      end)
      tools.run('tour_update', { mode = 'note', note = 'Clearer.' })

      eq({ 'note', 'Clearer.' }, { seen.mode, seen.note })
    end)

    it('says what is missing, and that there is no tour to change', function()
      local function message(args)
        return tostring(select(2, pcall(tools.run, 'tour_update', args)))
      end

      assert.truthy(message({ mode = 'note', note = 'x' }):find('no tour is running', 1, true))

      start()

      assert.truthy(message({ mode = 'insert' }):find('needs steps', 1, true))
      assert.truthy(message({ mode = 'note' }):find('needs a note', 1, true))
      assert.truthy(
        message({ mode = 'insert', steps = { { path = 'nope.lua', line = 1 } } }):find('step 1: no file', 1, true)
      )
    end)
  end)
end)
