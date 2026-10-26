local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path

local Connection = require('harness.servers.acp.Connection')
local Session = require('harness.Session')
local BlockBuilder = require('harness.transcript.BlockBuilder')
local display = require('harness.ui.display')
local events = require('harness.servers.acp.updates')
local fake_agent = require('harness.servers.acp.fake_agent')

local TURNS = tonumber(os.getenv('TURNS') or 30)
local CHUNKS = tonumber(os.getenv('CHUNKS') or 1500)
local BUDGET_MS = tonumber(os.getenv('BENCH_BUDGET_MS') or '')

vim.o.columns, vim.o.lines = 160, 50

local function now()
  return vim.uv.hrtime() / 1e6
end

local out = {}
local failed = false

local function log(...)
  out[#out + 1] = string.format(...)
end

local spent = {}

local function wrap(module, name, label)
  local ok, tbl = pcall(require, module)

  if not ok or type(tbl[name]) ~= 'function' then return end

  local fn = tbl[name]

  tbl[name] = function(...)
    local start = now()
    local a, b, c = fn(...)
    local entry = spent[label] or { 0, 0 }

    entry[1], entry[2] = entry[1] + now() - start, entry[2] + 1
    spent[label] = entry

    return a, b, c
  end
end

local function report()
  local labels = vim.tbl_keys(spent)

  table.sort(labels, function(a, b)
    return spent[a][1] > spent[b][1]
  end)

  for _, label in ipairs(labels) do
    log('    %-26s %9.1f ms %7d calls', label, spent[label][1], spent[label][2])
  end

  spent = {}
end

wrap('harness.transcript.BlockBuilder', 'build', 'BlockBuilder.build')
wrap('harness.ui.Document', 'write', 'Document.write')
wrap('harness.ui.Document', 'decorate_visible', 'Document.decorate_visible')
wrap('ui.markdown.Renderer', 'annotate', 'Renderer.annotate')
wrap('harness.vgit', 'patch', 'vgit.patch')
wrap('harness.vgit', 'stat', 'vgit.stat')
wrap('harness.edits.Edit', 'syntax', 'Edit.syntax')
wrap('harness.transcript.decorators', 'decorate', 'decorators.decorate')
wrap('core.buffers', 'lines_of', 'buffers.lines_of')
wrap('harness.transcript.output_style', 'strip', 'output_style.strip')
wrap('harness.transcript.output_style', 'language', 'output_style.language')
wrap('ui.markdown.Renderer', 'syntax', 'Renderer.syntax')

local files = vim.fn.glob(root .. '/lua/harness/**/*.lua', false, true)
local session = Session({ key = 'bench', id = 'bench', dir = root, connection = Connection(fake_agent.new()) })

local function update(fields)
  session:_on_event(events.from_update(fields))
end

local function text(value)
  return { type = 'text', text = value }
end

local PARAGRAPH = 'Here is some **bold** text with `inline code` and a [link](lua/harness/init.lua) to read.\n'
local CODE = '```lua\nlocal x = 1\nfor i = 1, 10 do\n  print(i, x)\nend\nreturn x\n```\n'
local KINDS = { 'read', 'search', 'execute', 'edit' }

local tool_id = 0

local function tool(kind)
  tool_id = tool_id + 1

  local id = 't' .. tool_id
  local output = {}

  for line = 1, 40 do
    output[line] = 'output line ' .. line .. ' of tool ' .. id
  end

  local content = { { type = 'content', content = text(table.concat(output, '\n')) } }

  if kind == 'edit' then
    local path = files[tool_id % #files + 1]
    local new = table.concat(vim.list_slice(vim.fn.readfile(path), 5, 8), '\n')

    content[#content + 1] = { type = 'diff', path = path, oldText = new .. '\n-- old', newText = new }
  end

  update({ sessionUpdate = 'tool_call', toolCallId = id, title = 'Tool ' .. id, kind = kind, status = 'pending' })
  update({ sessionUpdate = 'tool_call_update', toolCallId = id, status = 'completed', content = content })
end

local function turn()
  session:_emit(events.prompt('please do task ' .. tool_id))
  update({ sessionUpdate = 'agent_thought_chunk', content = text('Thinking about it.\nMore thoughts.') })

  for i = 1, 10 do
    tool(KINDS[i % #KINDS + 1])
  end

  for i = 1, 8 do
    update({
      sessionUpdate = 'agent_message_chunk',
      content = text('## Heading ' .. i .. '\n\n' .. PARAGRAPH .. '\n- item one\n- item two\n\n' .. CODE .. '\n'),
    })
  end

  session:_emit(events.stop('end_turn'))
end

local function time(label, n, fn)
  local start = now()

  for _ = 1, n do
    fn()
  end

  log('  %-34s %8.2f ms/op', label, (now() - start) / n)
end

for _ = 1, TURNS do
  turn()
end

log(
  'harness bench: %d turns, %d events, %d reply chunks after %d thought chunks',
  TURNS,
  #session.history,
  CHUNKS,
  math.floor(CHUNKS / 2)
)

local RUNS = tonumber(os.getenv('RUNS') or 5)

local function median(values)
  local sorted = vim.deepcopy(values)

  table.sort(sorted)

  return sorted[math.ceil(#sorted / 2)]
end

local function open_once()
  local started = now()

  display.open(session)

  local mounted = now()

  vim.cmd('redraw')

  return mounted - started, now() - mounted
end

local load = (vim.uv.loadavg())
local cpus = #vim.uv.cpu_info()

if load > cpus / 2 then
  log('warning: load average %.1f on %d cpus, timings are noisy', load, cpus)
end

open_once()
display.forget(session)
spent = {}

local mounts, shows, totals = {}, {}, {}

for run = 1, RUNS do
  if run > 1 then
    display.forget(session)
    spent = {}
  end

  local mount, show = open_once()

  mounts[run], shows[run], totals[run] = mount, show, mount + show
end

local view = display.view_of(session)

log('open (%d runs after 1 warmup, median / min)', RUNS)
log(
  '  mount %.1f / %.1f ms, show+redraw %.1f / %.1f ms, total %.1f / %.1f ms, %d lines',
  median(mounts),
  math.min(unpack(mounts)),
  median(shows),
  math.min(unpack(shows)),
  median(totals),
  math.min(unpack(totals)),
  vim.api.nvim_buf_line_count(view.bufnr)
)

if BUDGET_MS and median(totals) > BUDGET_MS then
  failed = true
  log('  budget %.1f ms exceeded by %.1f ms', BUDGET_MS, median(totals) - BUDGET_MS)
end

report()

log('build')
time('BlockBuilder.build (cached)', 20, function()
  BlockBuilder.build(session.history, session.title, {
    times = session.times,
    cache = view.cache,
    edits = view.edits,
    groups = true,
    live_turns = 50,
  })
end)
spent = {}

session:_emit(events.prompt('stream test'))
session.state = 'running'

local prompted = now()

view:render()
vim.cmd('redraw')
log('new prompt')
log('  render %.2f ms', now() - prompted)
report()

local function stream(label, kind, chunks)
  local total, worst, at, samples = 0, 0, 0, {}

  for chunk = 1, chunks do
    local piece = chunk % 60 == 0 and ('\n' .. CODE .. '\n')
      or ('word' .. chunk .. ' ' .. (chunk % 12 == 0 and '\n\n' or ''))

    update({ sessionUpdate = kind, content = text(piece) })

    local start = now()

    view:render()
    vim.cmd('redraw')

    local took = now() - start

    if took > worst then
      worst, at = took, chunk
    end

    total = total + took

    if chunk % 300 == 0 then samples[#samples + 1] = string.format('%d:%.1f', chunk, took) end
  end

  log(label)
  log(
    '  per chunk avg %.2f ms, worst %.2f ms at chunk %d, at chunk(ms) %s',
    total / chunks,
    worst,
    at,
    table.concat(samples, ' ')
  )
  report()
end

local function stream_tool(label, lines)
  local total, worst, output = 0, 0, {}

  update({
    sessionUpdate = 'tool_call',
    toolCallId = 'live',
    title = 'make test',
    kind = 'execute',
    status = 'in_progress',
    rawInput = { command = 'make test 2>&1 | tee out.log' },
  })

  for line = 1, lines do
    output[line] = line % 25 == 0 and ('\27[31mFAIL\27[0m lua/x_spec.lua:' .. line .. ': expected')
      or line % 7 == 0 and ('warning: lua/y.lua:' .. line .. ': unused')
      or ('\27[32mok\27[0m test ' .. line .. ' passed')

    update({
      sessionUpdate = 'tool_call_update',
      toolCallId = 'live',
      status = 'in_progress',
      content = { { type = 'content', content = text(table.concat(output, '\n')) } },
    })

    local start = now()

    view:render()
    vim.cmd('redraw')

    local took = now() - start

    worst = math.max(worst, took)
    total = total + took
  end

  update({ sessionUpdate = 'tool_call_update', toolCallId = 'live', status = 'completed' })
  log(label)
  log('  per update avg %.2f ms, worst %.2f ms', total / lines, worst)
  report()
end

stream_tool('stream tool output', 300)
stream('stream thought', 'agent_thought_chunk', math.floor(CHUNKS / 2))
log('  thought folded away: %s', tostring(view.document:folded(view.document.blocks[#view.document.blocks])))
stream('stream reply', 'agent_message_chunk', CHUNKS)

log(
  'buffer matches the document: %s',
  tostring(vim.deep_equal(vim.api.nvim_buf_get_lines(view.bufnr, 0, -1, false), view.document.lines))
)

session.state = 'idle'
view:dispose()

io.stdout:write(table.concat(out, '\n') .. '\n')
vim.cmd(failed and 'cquit 1' or 'qa!')
