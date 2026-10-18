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

  local ok, err = pcall(function()
    while head <= tail do
      local fn = queue[head]
      queue[head] = nil
      head = head + 1
      fn()
    end
  end)

  queue = {}
  head, tail = 1, 0
  draining = false

  if not ok then error(err, 0) end
end

local Future = {}
Future.__index = Future

function Future.new()
  return setmetatable({ done = false, err = nil, result = nil, _callbacks = {} }, Future)
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
end

function Future:set_result(value)
  if self.done then return end

  self.done = true
  self.result = value

  local callbacks = self._callbacks
  self._callbacks = {}

  for _, callback in ipairs(callbacks) do
    enqueue(function()
      callback(nil, value)
    end)
  end
end

function Future:set_exception(err)
  if self.done then return end

  self.done = true
  self.err = err

  local callbacks = self._callbacks
  self._callbacks = {}

  for _, callback in ipairs(callbacks) do
    enqueue(function()
      callback(err, nil)
    end)
  end
end

function Future:wait(timeout_ms)
  drain()

  local finished = vim.wait(timeout_ms or 60000, function()
    drain()
    return self.done
  end, 5)

  if not finished then error('timed out waiting for a result', 0) end
  if self.err then error(self.err, 0) end

  return self.result
end

local Task = setmetatable({}, { __index = Future })
Task.__index = Task

local current_task

local function resume_task(task, err, res)
  if task.done then return end

  current_task = task

  local ok, yielded = coroutine.resume(task.co, err, res)

  current_task = nil

  if not ok then
    task:set_exception(yielded)
  elseif coroutine.status(task.co) == 'dead' then
    task:set_result(yielded)
  end
end

function Task.new(fn)
  local task = setmetatable(Future.new(), Task)
  task.co = coroutine.create(fn)

  enqueue(function()
    resume_task(task)
  end)

  vim.schedule(drain)

  return task
end

function async.run(fn)
  return Task.new(fn)
end

function async.await(awaitable)
  if type(awaitable) ~= 'table' or awaitable.done == nil then return awaitable end

  if awaitable.done then
    if awaitable.err then error(awaitable.err, 0) end
    return awaitable.result
  end

  local task = current_task

  assert(task, 'async.await must be called inside async.run')

  awaitable:on_complete(function(err, res)
    enqueue(function()
      resume_task(task, err, res)
    end)
  end)

  local err, res = coroutine.yield()

  if err then error(err, 0) end

  return res
end

async.Future = Future
async.Task = Task
async.drain = drain

return async
