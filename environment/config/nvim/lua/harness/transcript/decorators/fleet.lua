local text = require('core.text')
local glitch = require('ui.glitch')
local MarkSpec = require('ui.MarkSpec')
local glyph = require('ui.design.glyph')
local theme = require('harness.transcript.theme')
local FleetMember = require('harness.transcript.model.FleetMember')

local STATE = FleetMember.STATE

local fleet = {}

fleet.KEY_WIDTH = 4
fleet.AGENT_WIDTH = 9
fleet.MODEL_WIDTH = 12
fleet.TUNE_MS = 400
fleet.SPARK = { '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' }

fleet.WORDS = {
  [STATE.starting] = 'starting',
  [STATE.idle] = 'idle',
  [STATE.working] = 'working',
  [STATE.waiting] = 'needs you',
  [STATE.done] = 'done',
  [STATE.failed] = 'failed',
  [STATE.cancelled] = 'cancelled',
  [STATE.gone] = 'ended',
}

local function pad(value, width)
  value = text.truncate(value or '', width - 1)

  return value .. string.rep(' ', width - text.width(value))
end

local function icon_of(member, key, ctx)
  local state = member and member.state

  if state == STATE.working then return theme.loader('busy', ctx.now) end
  if state == STATE.waiting then return theme.loader('waiting', ctx.now) end
  if state == STATE.starting then return theme.loader('loading', ctx.now) end

  if state == STATE.done or state == STATE.failed then
    local failed = state == STATE.failed
    local burst = theme.burst('fleet:' .. key, member.finished, ctx.now, failed)

    return burst or theme.TOOL_ICONS[failed and 'failed' or 'completed']
  end

  if state == STATE.cancelled then return { theme.TOOL_ICONS.failed[1], 'UiMuted' } end

  return theme.IDLE_ICON
end

local function spark(activity)
  if not activity then return nil end

  local top = 0

  for _, n in ipairs(activity) do
    top = math.max(top, n)
  end

  if top == 0 then return nil end

  local out = {}

  for _, n in ipairs(activity) do
    out[#out + 1] = n == 0 and ' ' or fleet.SPARK[math.max(1, math.ceil(n / top * #fleet.SPARK))]
  end

  return table.concat(out)
end

local function cost_text(cost)
  return cost and string.format('$%.3f', cost) or nil
end

local function duration(member, ctx)
  if not (member and member.started) then return nil end

  local finish = member.finished or (FleetMember.live(member) and ctx.now) or nil

  return finish and theme.duration(finish - member.started) or nil
end

local function detail_of(member, info)
  local state = member and member.state

  if state == STATE.waiting then return member.ask and ('allow ' .. member.ask .. '?') or 'needs you', 'UiWarn' end
  if state == STATE.working then return member.tool or 'thinking', 'UiToolName' end
  if state == STATE.done then return member.result or 'done', 'UiAdded' end
  if state == STATE.failed then return member.result or 'failed', 'UiError' end
  if state == STATE.starting then return info.prompt or 'starting', 'UiMuted' end

  return (member and fleet.WORDS[state]) or info.prompt or 'ended', 'UiMuted'
end

local function tuned(chunks, member, ctx)
  if theme.reduced() or not (member and member.started and ctx.now) then return chunks end

  local elapsed = ctx.now - member.started

  if elapsed < 0 or elapsed >= fleet.TUNE_MS then return chunks end

  local density = 1 - elapsed / fleet.TUNE_MS

  for i, chunk in ipairs(chunks) do
    chunks[i] = { glitch.scramble(chunk[1], density, ctx.now + i), chunk[2] }
  end

  return chunks
end

local width_of = text.width_of

local function place(out, row, line, head, tail, ctx)
  MarkSpec.add(out, row, 0, { end_col = #line, conceal = '', line_hl_group = 'UiSurface' })
  MarkSpec.add(out, row, 0, { virt_text = head, virt_text_pos = 'inline' })

  if #tail == 0 then return end

  local fits = ctx.width and width_of(head) + width_of(tail) + 2 <= ctx.width

  if not fits then table.insert(tail, 1, { '  ' }) end

  MarkSpec.add(out, row, 0, { virt_text = tail, virt_text_pos = fits and 'right_align' or 'eol' })
end

function fleet.tally(block, snapshot)
  local counts = { live = 0, waiting = 0, done = 0, failed = 0, total = #(block.members or {}) }
  local cost, started, finished

  for _, info in ipairs(block.members or {}) do
    local member = snapshot and snapshot[info.key]
    local state = member and member.state

    if FleetMember.live(member) then counts.live = counts.live + 1 end
    if state == STATE.waiting then counts.waiting = counts.waiting + 1 end
    if state == STATE.done then counts.done = counts.done + 1 end
    if state == STATE.failed or state == STATE.cancelled then counts.failed = counts.failed + 1 end

    if member and member.cost then cost = (cost or 0) + member.cost end
    if member and member.started then started = math.min(started or member.started, member.started) end
    if member and member.finished then finished = math.max(finished or member.finished, member.finished) end
  end

  counts.cost, counts.started, counts.finished = cost, started, finished

  return counts
end

function fleet.summary(counts)
  local parts = { text.plural(counts.total, 'agent') }

  if counts.live > 0 then
    if counts.live > counts.waiting then parts[#parts + 1] = (counts.live - counts.waiting) .. ' working' end
    if counts.waiting > 0 then parts[#parts + 1] = counts.waiting .. ' needs you' end
  else
    parts[#parts + 1] = glyph.STATUS.done .. counts.done .. ' ' .. glyph.STATUS.failed .. counts.failed
  end

  return glyph.join(parts)
end

local function header(block, ctx, out)
  local snapshot = ctx.fleet
  local counts = fleet.tally(block, snapshot)
  local live = counts.live > 0
  local icon

  if counts.waiting > 0 then
    icon = theme.loader('waiting', ctx.now)
  elseif live then
    icon = theme.loader('busy', ctx.now)
  else
    icon = theme.TOOL_ICONS[counts.failed > 0 and 'failed' or 'completed']
  end

  local head =
    { icon, { 'fleet', 'UiToolName' }, { '  ' .. fleet.summary(counts), counts.waiting > 0 and 'UiWarn' or 'UiMuted' } }
  local tail = {}
  local cost = cost_text(counts.cost)
  local finish = live and ctx.now or counts.finished
  local elapsed = counts.started and finish and theme.duration(finish - counts.started)

  if cost then tail[#tail + 1] = { cost, live and 'UiAccent' or 'UiMuted' } end
  if elapsed then tail[#tail + 1] = { (cost and '  ' or '') .. elapsed, 'UiMuted' } end

  place(out, block.start, block.lines[1], head, tail, ctx)
end

local function member_row(block, index, ctx, out)
  local info = block.members[index]
  local member = ctx.fleet and ctx.fleet[info.key]
  local detail, group = detail_of(member, info)
  local settled = member and FleetMember.SETTLED[member.state]
  local name_group = (settled or not member) and 'UiMuted' or 'UiTitle'

  local head = { { '  ' }, icon_of(member, info.key, ctx), { ' ' } }
  local body = tuned({
    { pad(info.key, fleet.KEY_WIDTH), name_group },
    { pad((member and member.agent) or info.agent or '', fleet.AGENT_WIDTH), 'UiMuted' },
    { pad(member and member.model or '', fleet.MODEL_WIDTH), 'UiMuted' },
    { detail, group },
  }, member, ctx)

  vim.list_extend(head, body)

  local tail = {}
  local line = spark(member and member.activity)
  local cost = cost_text(member and member.cost)
  local took = duration(member, ctx)

  if line then tail[#tail + 1] = { line, 'UiAccent' } end
  if cost then tail[#tail + 1] = { (#tail > 0 and '  ' or '') .. cost, 'UiMuted' } end
  if took then tail[#tail + 1] = { (#tail > 0 and '  ' or '') .. took, 'UiMuted' } end

  local row = block.start + index

  place(out, row, block.lines[index + 1], head, tail, ctx)
end

function fleet.decorate(block, ctx)
  local out = {}

  header(block, ctx, out)

  for index = 1, #(block.members or {}) do
    member_row(block, index, ctx, out)
  end

  return out
end

return setmetatable(fleet, {
  __call = function(_, block, ctx)
    return fleet.decorate(block, ctx)
  end,
})
