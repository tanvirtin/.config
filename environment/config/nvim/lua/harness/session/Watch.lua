local lazy = require('core.lazy')
local compact = require('compact')

local Timer = lazy('core.Timer')
local Object = lazy('core.Object')
local settings = lazy('harness.settings.wake')

local Watch = Object:extend()

Watch.KIND = { subagent = 'subagent', tool = 'tool' }

Watch.LABEL = { subagent = 'subagent', tool = 'tool' }

-- What a turn left running. A turn that ends while something is still open
-- marks it: if it finishes after the turn ended, nobody was there to read it,
-- so it starts a new turn. Work that finished inside the turn is never marked,
-- which is what keeps an agent that waited for its own subagent from being
-- woken about it.
function Watch:constructor(session)
  return {
    session = session,
    items = {},
    pending = {},
    wakes = 0,
    firing = false,
    scheduled = false,
    generation = 0,
  }
end

local function key(kind, id)
  return kind .. ':' .. id
end

function Watch:open(kind, id, fields)
  if not settings:get('enabled') then return end
  if kind == Watch.KIND.tool and not settings:get('tools') then return end

  local name = key(kind, id)
  local item = self.items[name]

  if not item then
    item = { kind = kind, id = id }
    self.items[name] = item
  end

  for field, value in pairs(fields or {}) do
    if value ~= nil then item[field] = value end
  end

  return item
end

function Watch:settle(kind, id, fields)
  local name = key(kind, id)
  local item = self.items[name]

  if not item or item.settled then return end

  for field, value in pairs(fields or {}) do
    if value ~= nil then item[field] = value end
  end

  item.settled = true
  self.items[name] = nil

  if item.armed then
    self.pending[#self.pending + 1] = item
    self:_schedule()
  end
end

function Watch:turn_ended(reason)
  if reason == 'cancelled' or reason == 'error' then
    self.items = {}
    return
  end

  for _, item in pairs(self.items) do
    if not item.settled then item.armed = true end
  end
end

function Watch:prompted(opts)
  if not (opts and opts.wake) then self.wakes = 0 end
end

function Watch:clear()
  self.items = {}
  self.pending = {}
  self.wakes = 0
  self.scheduled = false
  self.generation = self.generation + 1
end

function Watch:waiting()
  return #self.pending
end

-- A short pause lets several things that finish together become one turn
-- instead of one turn each.
function Watch:_schedule()
  if self.scheduled then return end

  self.scheduled = true
  local generation = self.generation

  Timer.defer(settings:get('settle_ms'), function()
    if generation ~= self.generation then return end

    self.scheduled = false
    self:_fire()
  end)
end

function Watch:_fire()
  if self.firing or #self.pending == 0 then return end
  if not settings:get('enabled') then return end

  local session = self.session

  if session:loading() or session.state == 'closed' then return end
  if self.wakes >= settings:get('max') then return end

  local items = self.pending
  local text = self:_text(items)

  self.pending = {}
  self.wakes = self.wakes + 1
  self.firing = true

  session:enqueue(text, nil, { wake = true })

  self.firing = false

  if #self.pending == 0 then return end

  -- the session refused it; keep the items for the next turn
  for _, item in ipairs(items) do
    self.pending[#self.pending + 1] = item
  end
end

function Watch:_text(items)
  local limit = settings:get('max_items')
  local preview = settings:get('preview')
  local lines = {}

  if #items == 1 then
    lines[#lines + 1] = string.format(
      '[harness] the %s you left running finished after your last turn:',
      Watch.LABEL[items[1].kind] or 'work'
    )
  else
    lines[#lines + 1] = string.format('[harness] %d items you left running finished after your last turn:', #items)
  end

  for i = 1, math.min(#items, limit) do
    local item = items[i]
    local detail = item.kind == Watch.KIND.subagent and item.stop or item.status
    local body = compact.line(vim.trim((item.summary or item.output or ''):gsub('%s+', ' ')), preview)
    local label = compact.line(item.title or item.name or item.id or '?', 60)

    lines[#lines + 1] = string.format(
      '- %s "%s"%s%s',
      Watch.LABEL[item.kind] or 'item',
      label,
      detail and (' (' .. detail .. ')') or '',
      body ~= '' and (': ' .. body) or ''
    )
  end

  if #items > limit then lines[#lines + 1] = string.format('- (+%d more)', #items - limit) end

  lines[#lines + 1] = 'Their output is in the transcript. Carry on from where the turn ended.'

  return table.concat(lines, '\n')
end

return Watch
