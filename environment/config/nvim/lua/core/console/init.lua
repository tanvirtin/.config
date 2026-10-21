local lazy = require('core.lazy')

local event = lazy('core.event')
local LogFormatter = lazy('core.console.LogFormatter')

local console = {}

console.debug = lazy('core.console.debug_logger')

function console.format(msg)
  return LogFormatter(msg, { timestamp = false }):format():value()
end

console.error = event.async(function(msg)
  event.await()
  msg = console.format(msg)
  vim.notify(msg, vim.log.levels.ERROR)

  return console
end)

console.warn = event.async(function(msg)
  event.await()
  msg = console.format(msg)
  vim.notify(msg, vim.log.levels.WARN)

  return console
end)

console.clear = event.async(function()
  event.await()
  vim.cmd('echo ""')

  return console
end)

console.info = event.async(function(msg)
  event.await()
  msg = console.format(msg)
  vim.notify(msg, vim.log.levels.INFO)

  return console
end)

console.input = function(prompt)
  local ok, result = pcall(vim.fn.input, prompt)
  console.clear()

  if not ok then return nil end

  return result
end

console.cleanup = event.async(function()
  console.debug.cleanup()
  return console
end)

console.LEVEL = { info = vim.log.levels.INFO, warn = vim.log.levels.WARN, error = vim.log.levels.ERROR }

function console.notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, console.LEVEL[level or 'info'])
  end)
end

function console.notify_now(msg, level)
  vim.notify(msg, console.LEVEL[level or 'info'])
end

function console.select(items, opts, on_choice)
  return vim.ui.select(items, opts, on_choice)
end

function console.open_url(url)
  return vim.ui.open(url)
end

return console
