local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path

local Connection = require('harness.servers.acp.connection')
local Session = require('harness.session')
local BlockBuilder = require('harness.transcript.BlockBuilder')
local display = require('harness.ui.display')
local events = require('harness.servers.acp.updates')
local fake_agent = require('harness.servers.acp.fake_agent')

local TURNS = tonumber(os.getenv('TURNS') or 30)
local CHUNKS = tonumber(os.getenv('CHUNKS') or 1500)

vim.o.columns, vim.o.lines = 160, 50

local function now()
  return vim.uv.hrtime() / 1e6
end

local out = {}

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
wrap('harness.ui.document', 'write', 'Document.write')
wrap('harness.ui.document', 'decorate_visible', 'Document.decorate_visible')
wrap('ui.markdown.Renderer', 'annotate', 'Renderer.annotate')
wrap('harness.vgit', 'patch', 'vgit.patch')
wrap('harness.vgit', 'stat', 'vgit.stat')
wrap('harness.edits.Edit', 'syntax', 'Edit.syntax')
wrap('harness.transcript.decorators', 'decorate', 'decorators.decorate')
wrap('core.buffers', 'lines_of', 'buffers.lines_of')

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

local started = now()

display.open(session)

local view = display.view_of(session)
local mounted = now()

vim.cmd('redraw')

local shown = now()

log('open')
log(
  '  mount %.1f ms, show+redraw %.1f ms, total %.1f ms, %d lines',
  mounted - started,
  shown - mounted,
  shown - started,
  vim.api.nvim_buf_line_count(view.bufnr)
)
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
vim.cmd('qa!')
