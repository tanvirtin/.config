local Stage = require('ui.anim.Stage')

local eq = assert.are.same

local function actor(duration, log, breaks_at)
  return {
    duration = function()
      return duration
    end,
    update = function(_, ms)
      if breaks_at and ms >= breaks_at then error('boom', 0) end

      log[#log + 1] = ms
    end,
    destroy = function()
      log.destroyed = (log.destroyed or 0) + 1
    end,
  }
end

describe('ui.anim.Stage:', function()
  it('lasts as long as its longest actor, plus a tail, unless told otherwise', function()
    eq(400 + Stage.TAIL_MS, Stage.new({ actor(100, {}), actor(400, {}) }).duration)
    eq(900, Stage.new({ actor(100, {}) }, { duration_ms = 900 }).duration)
    eq(Stage.MAX_MS, Stage.new({ actor(100, {}) }, { duration_ms = 10 * Stage.MAX_MS }).duration)
  end)

  it('updates every actor, then stops and destroys them once its time is up', function()
    local log, done = {}, 0
    local stage = Stage.new({ actor(100, log) }, {
      duration_ms = 100,
      on_done = function()
        done = done + 1
      end,
    })

    stage:update(0)
    stage:update(50)
    eq(true, stage:is_running())
    stage:update(100)
    stage:update(150)

    eq({ 0, 50, 100, destroyed = 1 }, log)
    eq(false, stage:is_running())
    eq(1, done)
  end)

  it('wraps time around when it loops', function()
    local log = {}
    local stage = Stage.new({ actor(100, log) }, { duration_ms = 100, loop = true })

    stage:update(250)

    eq({ 50 }, log)
    eq(true, stage:is_running())
    stage:stop()
  end)

  it('stops with the error when an actor breaks', function()
    local problem
    local stage = Stage.new({ actor(100, {}, 50) }, {
      on_done = function(err)
        problem = err
      end,
    })

    stage:update(60)

    eq('boom', problem)
    eq(false, stage:is_running())
  end)

  it('clears its pixel layer before the actors draw, sends it after, and destroys it at the end', function()
    local calls = {}
    local layer = {
      begin = function()
        calls[#calls + 1] = 'begin'
      end,
      flush = function()
        calls[#calls + 1] = 'flush'
      end,
      destroy = function()
        calls[#calls + 1] = 'destroy'
      end,
    }
    local stage = Stage.new({
      {
        duration = function()
          return 100
        end,
        update = function()
          calls[#calls + 1] = 'actor'
        end,
        destroy = function() end,
      },
    }, { layer = layer })

    stage:update(0)
    stage:stop()

    eq({ 'begin', 'actor', 'flush', 'destroy' }, calls)
  end)

  it('runs on a clock until it is done', function()
    local log = {}
    local stage = Stage.new({ actor(30, log) }, { duration_ms = 30, fps = 60 }):start()

    vim.wait(1000, function()
      return not stage:is_running()
    end, 5)

    eq(false, stage:is_running())
    eq(1, log.destroyed)
    assert.is_true(#log >= 2)
  end)
end)
