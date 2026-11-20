local script = {}

local DEFAULT_TIMEOUT_MS = 10000

local scratch, created, errors

local function render(values, count)
  local out = {}

  for i = 1, count do
    out[i] = type(values[i]) == 'string' and values[i] or vim.inspect(values[i])
  end

  return table.concat(out, '\n')
end

local function pack(...)
  return select('#', ...), { ... }
end

local function report(what, err)
  local message = string.format('%s failed and was disabled: %s', what, tostring(err))

  errors[#errors + 1] = message
  vim.schedule(function()
    vim.notify('Harness script: ' .. message, vim.log.levels.WARN)
  end)
end

local function guard(what, fn, disable, on_fail)
  if type(fn) ~= 'function' then return fn end

  local dead = false

  return function(...)
    if dead then return on_fail end

    local count, results = pack(pcall(fn, ...))

    if results[1] then return unpack(results, 2, count) end

    dead = true
    report(what, results[2])

    if disable then pcall(disable) end

    return on_fail
  end
end

local function record(kind, value)
  created[#created + 1] = { kind = kind, value = value }

  return value
end

local function overlay(base, overrides)
  return setmetatable(overrides, { __index = base })
end

local function guarded_timer(timer)
  record('timer', timer)

  return setmetatable({}, {
    __index = function(_, key)
      if key == 'start' then
        return function(_, timeout, rep, callback)
          return timer:start(
            timeout,
            rep,
            vim.schedule_wrap(guard('a timer', callback, function()
              timer:stop()
            end))
          )
        end
      end

      local value = timer[key]

      if type(value) ~= 'function' then return value end

      return function(_, ...)
        return value(timer, ...)
      end
    end,
  })
end

local api = overlay(vim.api, {
  nvim_create_autocmd = function(event, opts)
    local id

    opts = vim.deepcopy(opts or {})
    opts.callback = guard('an autocmd (' .. vim.inspect(event) .. ')', opts.callback, function()
      vim.api.nvim_del_autocmd(id)
    end)
    id = vim.api.nvim_create_autocmd(event, opts)

    return record('autocmd', id)
  end,

  nvim_create_augroup = function(name, opts)
    return record('augroup', vim.api.nvim_create_augroup(name, opts))
  end,

  nvim_create_namespace = function(name)
    return record('namespace', vim.api.nvim_create_namespace(name))
  end,

  nvim_set_decoration_provider = function(ns, callbacks)
    local wrapped = {}

    for key, fn in pairs(callbacks) do
      wrapped[key] = guard('a decoration provider (' .. key .. ')', fn, function()
        vim.api.nvim_set_decoration_provider(ns, {})
      end, false)
    end

    record('decoration', ns)

    return vim.api.nvim_set_decoration_provider(ns, wrapped)
  end,

  nvim_buf_attach = function(buf, send_buffer, callbacks)
    local wrapped = {}

    for key, fn in pairs(callbacks or {}) do
      wrapped[key] = guard('a buffer attachment (' .. key .. ')', fn, nil, true)
    end

    return vim.api.nvim_buf_attach(buf, send_buffer, wrapped)
  end,

  nvim_open_win = function(buf, enter, config)
    return record('window', vim.api.nvim_open_win(buf, enter, config))
  end,

  nvim_create_user_command = function(name, command, opts)
    record('command', name)

    return vim.api.nvim_create_user_command(name, guard('the :' .. name .. ' command', command), opts)
  end,
})

local keymap = overlay(vim.keymap, {
  set = function(mode, lhs, rhs, opts)
    record('keymap', { mode = mode, lhs = lhs, buffer = opts and opts.buffer })

    return vim.keymap.set(mode, lhs, guard('the ' .. lhs .. ' mapping', rhs), opts)
  end,
})

local uv = overlay(vim.uv, {
  new_timer = function()
    return guarded_timer(vim.uv.new_timer())
  end,
})

local script_vim = overlay(vim, {
  api = api,
  keymap = keymap,
  uv = uv,
  loop = uv,
  defer_fn = function(fn, timeout)
    return vim.defer_fn(guard('a deferred function', fn), timeout)
  end,
})

local RUNNER = debug.getinfo(1, 'S').short_src

local function traceback(err)
  local out = {}

  for _, line in ipairs(vim.split(debug.traceback(tostring(err), 2), '\n', { plain = true })) do
    if line:find('in function \'xpcall\'', 1, true) then break end

    if not line:find(RUNNER, 1, true) and not line:find('[C]: in function \'error\'', 1, true) then
      out[#out + 1] = line
    end
  end

  return table.concat(out, '\n')
end

local function take_errors()
  if #errors == 0 then return nil end

  local note = 'Earlier script callbacks failed and were disabled:\n- ' .. table.concat(errors, '\n- ')

  errors = {}

  return note
end

function script.run(code, timeout_ms)
  local note = take_errors()
  local chunk, err = loadstring(code, '=script')

  if not chunk then error((note and (note .. '\n\n') or '') .. 'syntax error: ' .. err, 0) end

  local printed = { note }
  local timeout = timeout_ms or DEFAULT_TIMEOUT_MS
  local deadline = vim.uv.hrtime() + timeout * 1e6

  setfenv(chunk, scratch)
  scratch.print = function(...)
    printed[#printed + 1] = render({ ... }, select('#', ...))
  end

  jit.off(chunk, true)
  debug.sethook(function()
    if vim.uv.hrtime() > deadline then error(string.format('script timed out after %d ms', timeout), 0) end
  end, '', 10000)

  local count, results = pack(xpcall(chunk, traceback))

  debug.sethook()
  scratch.print = nil

  if not results[1] then error((note and (note .. '\n\n') or '') .. results[2], 0) end

  local returned = render({ unpack(results, 2, count) }, count - 1)

  if returned ~= '' then printed[#printed + 1] = returned end

  return table.concat(printed, '\n')
end

local CLEAR = {
  autocmd = vim.api.nvim_del_autocmd,
  augroup = vim.api.nvim_del_augroup_by_id,
  window = function(win)
    vim.api.nvim_win_close(win, true)
  end,
  command = vim.api.nvim_del_user_command,
  keymap = function(map)
    vim.keymap.del(map.mode, map.lhs, { buffer = map.buffer })
  end,
  timer = function(timer)
    timer:stop()
    timer:close()
  end,
  decoration = function(ns)
    vim.api.nvim_set_decoration_provider(ns, {})
  end,
  namespace = function(ns)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end,
}

function script.clear()
  local removed = 0

  for i = #created, 1, -1 do
    local item = created[i]

    if pcall(CLEAR[item.kind], item.value) then removed = removed + 1 end
  end

  script.reset()

  return removed
end

function script.reset()
  scratch = setmetatable({ vim = script_vim }, { __index = _G })
  created = {}
  errors = {}
end

script.reset()

return script
