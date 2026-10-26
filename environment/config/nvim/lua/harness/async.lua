local Timer = require('core.Timer')
local Object = require('core.Object')
local console = require('core.console')

local async = {}

local queue = {}
local head, tail = 1, 0
local draining = false

local function enqueue(fn)
  tail = tail + 1
  queue[tail] = fn
end

local function drain()
  if draining then return end

  draining = true

  while head <= tail do
    local fn = queue[head]
    queue[head] = nil
    head = head + 1

    local ok, err = pcall(fn)

    if not ok then pcall(console.notify, 'Harness: async callback failed: ' .. tostring(err), 'error') end
  end

  queue = {}
  head, tail = 1, 0
  draining = false
end

local Future = Object:extend()

Future.TIMEOUT_MS = 60000

function Future:constructor()
  return { done = false, err = nil, result = nil, _callbacks = {} }
end

function Future.new()
  return Future()
end

function Future:on_complete(callback)
  if self.done then
    local err, res = self.err, self.result
    enqueue(function()
      callback(err, res)
    end)
  else
    self._callbacks[#self._callbacks + 1] = callback
  end

  return self
end

function Future:_settle(value, err)
  if self.done then return self end

  self.done = true
  self.result = value
  self.err = err

  local callbacks = self._callbacks
  self._callbacks = {}

  for _, callback in ipairs(callbacks) do
    enqueue(function()
      callback(err, value)
    end)
  end

  return self
end

function Future:set_result(value)
  return self:_settle(value, nil)
end

function Future:set_exception(err)
  return self:_settle(nil, err)
end

function Future:wait(timeout_ms)
  drain()

  local finished = Timer.wait(timeout_ms or Future.TIMEOUT_MS, function()
    drain()
    return self.done
  end, 5)

  if not finished then return nil, 'timed out waiting for a result' end

  return self.result, self.err
end

local Task = Future:extend()

local current_task

function Task:constructor(fn)
  local task = Future.constructor(self)

  task.co = coroutine.create(fn)

  return task
end

function Task:_resume(err, res)
  if self.done then return self end

  current_task = self

  local ok, value, failure = coroutine.resume(self.co, err, res)

  current_task = nil

  if not ok then return self:set_exception(value) end
  if coroutine.status(self.co) ~= 'dead' then return self end
  if failure ~= nil then return self:set_exception(failure) end

  return self:set_result(value)
end

function Task:start()
  enqueue(function()
    self:_resume()
  end)

  Timer.schedule(drain)

  return self
end

function Task.new(fn)
  return Task(fn):start()
end

function async.run(fn)
  return Task.new(fn)
end

function async.await(awaitable)
  if type(awaitable) ~= 'table' or awaitable.done == nil then return awaitable end
  if awaitable.done then return awaitable.result, awaitable.err end

  local task = current_task

  assert(task, 'async.await must be called inside async.run')

  awaitable:on_complete(function(err, res)
    enqueue(function()
      task:_resume(err, res)
    end)
  end)

  local err, res = coroutine.yield()

  return res, err
end

async.Future = Future
async.Task = Task
async.drain = drain

return async
