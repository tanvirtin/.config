local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path

local SYSTEM = require('harness.agent').BUILTIN.claude.system

local MODEL = os.getenv('MODEL') or 'claude-sonnet-5-5'
local RUNS = tonumber(os.getenv('RUNS') or 2)
local JOBS = tonumber(os.getenv('JOBS') or 4)
local ONLY = os.getenv('TASK')
local TIMEOUT_MS = tonumber(os.getenv('TIMEOUT_MS') or 600000)

local ARMS = { 'plain', 'nvim' }
local CONTEXT = '<editor-context>The user has no file open.</editor-context>\n\n'

local BUILTIN_TOOLS = { 'Read', 'Grep', 'Glob', 'Edit', 'Write' }
local EDITOR_TOOLS = {
  'editor_state',
  'buffer_read',
  'buffer_edit',
  'buffer_write',
  'buffer_save',
  'outline',
  'search',
  'diagnostics',
  'lsp_hover',
}

local function allowed(arm)
  local names = vim.deepcopy(BUILTIN_TOOLS)

  if arm == 'nvim' then
    for _, name in ipairs(EDITOR_TOOLS) do
      names[#names + 1] = 'mcp__nvim__' .. name
    end
  end

  return table.concat(names, ',')
end

local work = string.format('%s/nvim-bench-%d', vim.uv.os_tmpdir(), vim.uv.os_getpid())

local function sh(command, cwd)
  local result = vim.system({ 'sh', '-c', command }, { cwd = cwd, text = true }):wait()

  return vim.trim(result.stdout or ''), result.code
end

local function callers()
  local out = {}

  for _, path in ipairs(vim.split(sh('grep -rl "compact.reply(" lua', root), '\n', { trimempty = true })) do
    if path ~= 'lua/compact.lua' then out[#out + 1] = (path:gsub('^lua/', '')) end
  end

  return out
end

local CALLERS = callers()

local TASKS = {
  {
    name = 'outline',
    prompt = 'List the methods lua/harness/ui/TranscriptView.lua defines on TranscriptView, one line each with what it does. Do not change anything.',
    check = function(run)
      return run.answer:find('reserve', 1, true) ~= nil and run.answer:find('render', 1, true) ~= nil
    end,
  },
  {
    name = 'symbol',
    prompt = 'What does changed_span in lua/nvim_mcp/tools/buffer.lua return? Answer in two sentences. Do not change anything.',
    check = function(run)
      return run.answer:lower():find('line', 1, true) ~= nil
    end,
  },
  {
    name = 'callers',
    prompt = 'Which files under lua/ call compact.reply? List only their paths. Do not change anything.',
    check = function(run)
      for _, path in ipairs(CALLERS) do
        if not run.answer:find(path, 1, true) then return false end
      end

      return true
    end,
  },
  {
    name = 'rename',
    prompt = 'Rename compact.BUDGET to compact.MAX_CHARS and compact.WIDTH to compact.MAX_WIDTH everywhere under lua/. Save every file you change to disk.',
    check = function(run)
      local _, left = sh('grep -rqE "compact\\.(BUDGET|WIDTH)([^_A-Z]|$)" lua', run.dir)
      local _, renamed = sh('grep -rq "compact.MAX_CHARS" lua && grep -rq "compact.MAX_WIDTH" lua', run.dir)

      return left ~= 0 and renamed == 0
    end,
  },
}

local SCRIPT = [[
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
if [ "$ARM" = nvim ]; then
  nvim --headless --listen "$SOCK" >/dev/null 2>&1 &
  EDITOR_PID=$!
  tries=0
  while [ ! -S "$SOCK" ] && [ $tries -lt 100 ]; do sleep 0.1; tries=$((tries + 1)); done
  claude -p "$PROMPT" --model "$MODEL" --output-format stream-json --verbose \
    --strict-mcp-config --mcp-config mcp.json --allowedTools "$ALLOWED" \
    --append-system-prompt "$SYSTEM" > out.jsonl 2> err.log
  kill $EDITOR_PID
else
  claude -p "$PROMPT" --model "$MODEL" --output-format stream-json --verbose \
    --strict-mcp-config --mcp-config mcp.json --allowedTools "$ALLOWED" > out.jsonl 2> err.log
fi
]]

local function prepare(run)
  vim.fn.mkdir(run.dir, 'p')
  sh(string.format('cp -R %s %s', vim.fn.shellescape(root .. '/lua'), vim.fn.shellescape(run.dir .. '/lua')))

  local servers = {}

  if run.arm == 'nvim' then
    servers.nvim = {
      command = 'nvim',
      args = { '--headless', '-u', 'NONE', '-l', root .. '/lua/nvim_mcp/run.lua', run.sock },
    }
  end

  vim.fn.writefile(
    { vim.json.encode({ mcpServers = next(servers) and servers or vim.empty_dict() }) },
    run.dir .. '/mcp.json'
  )
end

local function read(run)
  run.tools, run.calls, run.editor_calls, run.answer = {}, 0, 0, ''

  local file = io.open(run.dir .. '/out.jsonl')

  if not file then return end

  for line in file:lines() do
    local ok, event = pcall(vim.json.decode, line)

    if ok and type(event) == 'table' then
      if event.type == 'assistant' and type(event.message) == 'table' then
        for _, part in ipairs(event.message.content or {}) do
          if part.type == 'tool_use' then
            run.tools[part.name] = (run.tools[part.name] or 0) + 1
            run.calls = run.calls + 1

            if part.name:find('^mcp__nvim__') then run.editor_calls = run.editor_calls + 1 end
          end
        end
      elseif event.type == 'result' then
        local usage = event.usage or {}

        run.answer = type(event.result) == 'string' and event.result or ''
        run.failed = event.is_error == true
        run.turns = event.num_turns or 0
        run.cost = event.total_cost_usd or 0
        run.seconds = (event.duration_ms or 0) / 1000
        run.output = usage.output_tokens or 0
        run.input = (usage.input_tokens or 0)
          + (usage.cache_creation_input_tokens or 0)
          + (usage.cache_read_input_tokens or 0)
      end
    end
  end

  file:close()
end

local runs, pending = {}, {}

for _, task in ipairs(TASKS) do
  if not ONLY or ONLY == task.name then
    for _, arm in ipairs(ARMS) do
      for n = 1, RUNS do
        local id = string.format('%s-%s-%d', task.name, arm, n)

        runs[#runs + 1] = {
          task = task,
          arm = arm,
          dir = work .. '/' .. id,
          sock = string.format('/tmp/nvim-bench-%d-%s.sock', vim.uv.os_getpid(), id),
        }
        pending[#pending + 1] = runs[#runs]
      end
    end
  end
end

local active, finished = 0, 0

local function pump()
  while active < JOBS and #pending > 0 do
    local run = table.remove(pending, 1)

    active = active + 1
    prepare(run)
    vim.system({ 'sh', '-c', SCRIPT }, {
      cwd = run.dir,
      timeout = TIMEOUT_MS,
      env = {
        ARM = run.arm,
        SOCK = run.sock,
        MODEL = MODEL,
        SYSTEM = SYSTEM,
        ALLOWED = allowed(run.arm),
        PROMPT = (run.arm == 'nvim' and CONTEXT or '') .. run.task.prompt,
      },
    }, function()
      vim.schedule(function()
        read(run)
        run.passed = run.turns ~= nil and not run.failed and run.task.check(run)
        active, finished = active - 1, finished + 1
        io.stderr:write(
          string.format('[%d/%d] %s %s %s\n', finished, #runs, run.task.name, run.arm, run.passed and 'ok' or 'FAILED')
        )
        pump()
      end)
    end)
  end
end

pump()
vim.wait(TIMEOUT_MS * #runs, function()
  return finished == #runs
end, 200)

local function mean(list, field)
  local sum, count = 0, 0

  for _, run in ipairs(list) do
    if run[field] then
      sum, count = sum + run[field], count + 1
    end
  end

  return count > 0 and sum / count or 0
end

local function group(task, arm)
  return vim.tbl_filter(function(run)
    return (not task or run.task.name == task) and run.arm == arm
  end, runs)
end

local function passed(list)
  return #vim.tbl_filter(function(run)
    return run.passed
  end, list)
end

local out = {
  string.format('model %s, %d runs per cell, means; work in %s', MODEL, RUNS, work),
  '',
  'task     | arm   | pass | turns | calls | editor | input tok | output tok | cost $ | seconds',
}

local function row(label, arm, list)
  out[#out + 1] = string.format(
    '%-8s | %-5s | %d/%d  | %5.1f | %5.1f | %6.1f | %9.0f | %10.0f | %6.3f | %7.1f',
    label,
    arm,
    passed(list),
    #list,
    mean(list, 'turns'),
    mean(list, 'calls'),
    mean(list, 'editor_calls'),
    mean(list, 'input'),
    mean(list, 'output'),
    mean(list, 'cost'),
    mean(list, 'seconds')
  )
end

for _, task in ipairs(TASKS) do
  if not ONLY or ONLY == task.name then
    for _, arm in ipairs(ARMS) do
      row(task.name, arm, group(task.name, arm))
    end
  end
end

for _, arm in ipairs(ARMS) do
  row('all', arm, group(nil, arm))
end

for _, arm in ipairs(ARMS) do
  local used = {}

  for _, run in ipairs(group(nil, arm)) do
    for name, count in pairs(run.tools) do
      used[name] = (used[name] or 0) + count
    end
  end

  local names = vim.tbl_keys(used)

  table.sort(names, function(a, b)
    return used[a] > used[b] or (used[a] == used[b] and a < b)
  end)

  out[#out + 1] = ''
  out[#out + 1] = arm
    .. ' tools: '
    .. table.concat(
      vim.tbl_map(function(name)
        return string.format('%s %d', (name:gsub('^mcp__nvim__', 'nvim:')), used[name])
      end, names),
      ', '
    )
end

io.stdout:write(table.concat(out, '\n') .. '\n')
os.exit(passed(runs) == #runs and 0 or 1)
