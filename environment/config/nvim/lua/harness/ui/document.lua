local Block = require('harness.transcript.Block')
local Buffer = require('core.Buffer')
local FoldCalculator = require('harness.transcript.calculators.FoldCalculator')
local Layout = require('harness.transcript.calculators.Layout')
local MarkSpec = require('ui.MarkSpec')
local Object = require('core.Object')
local Renderer = require('ui.markdown.Renderer')
local StatusLine = require('harness.transcript.StatusLine')
local Timer = require('core.Timer')
local context = require('harness.transcript.decorators.context')
local decorators = require('harness.transcript.decorators')
local settings = require('harness.settings.transcript')

local Document = Object:extend()

Document.NAMESPACE = Buffer.namespace('harness.document')

Document.RAW = { [Block.KIND.prompt] = true, [Block.KIND.note] = true, [Block.KIND.plan] = true }
Document.STATUS_NAMESPACE = Buffer.namespace('harness.document.status')

local documents = setmetatable({}, { __mode = 'v' })

Buffer.set_decoration_provider(Document.NAMESPACE, function(bufnr, top, bottom)
  local document = documents[bufnr]

  if document and not document.scheduled and document:has_pending(top, bottom) then
    document.scheduled = true
    Timer.defer(0, function()
      document.scheduled = false
      document:decorate_visible()
    end)
  end
end)

function Document:constructor(bufnr)
  return {
    bufnr = bufnr,
    buffer = Buffer(bufnr),
    pending = {},
    partial = {},
    scheduled = false,
    lines = {},
    blocks = {},
    state = { running = false, frame = 1 },
    renderer = Renderer(bufnr, {
      hidden_labels = { output = true, diff = true, edit = true },
      code_hl = { output = 'UiToolOutput' },
    }),
  }
end

local function merge(state, update)
  for key, value in pairs(update or {}) do
    state[key] = value
  end

  return state
end

function Document:_context()
  local state = self.state

  return {
    running = state.running,
    frame = state.frame,
    waiting = state.waiting,
    active = state.active,
    width = self.width,
    now = Timer.now(),
  }
end

function Document:text_width()
  local width

  for _, window in ipairs(self.buffer:get_windows()) do
    local text_width = window:get_text_width()

    width = width and math.min(width, text_width) or text_width
  end

  return width
end

function Document:resize()
  local width = self:text_width()

  if not width or width == self.width then return end

  self.width = width

  for i in ipairs(self.blocks) do
    self.pending[i] = true
  end

  self.partial = {}

  self:decorate_visible()
end

function Document:_decorate(block, ctx)
  self.buffer:clear_namespace(Document.NAMESPACE, block.start, block.finish)
  MarkSpec.apply(self.buffer, Document.NAMESPACE, decorators.decorate(block, ctx or self:_context()))
end

function Document:_live(block)
  return block.live or context.live_tool(block, self.state)
end

function Document:reset()
  self.lines = self.buffer:is_valid() and self.buffer:get_lines() or {}
  self.blocks = {}
  self.pending = {}
  self.partial = {}
end

function Document:attach()
  documents[self.bufnr] = self
  return self
end

function Document:stale()
  return self.changedtick ~= self.buffer:get_changedtick()
end

function Document:fold_level(row)
  return FoldCalculator.level(self.blocks, row)
end

function Document:block_at(row)
  return Layout.block_at(self.blocks, row)
end

function Document:_set_lines(lines, from)
  local buffer = self.buffer
  local modifiable = buffer:get_option('modifiable')

  buffer:set_option('modifiable', true)
  buffer:set_lines(lines, from, -1)
  buffer:set_option('modifiable', modifiable)
  buffer:set_option('modified', false)
end

function Document:write(list, state)
  if not self.buffer:is_valid() then return end

  merge(self.state, state)

  local width = self:text_width()
  local resized = width ~= nil and width ~= self.width

  if resized then self.width = width end

  local old = self.blocks
  local changed = Layout.first_changed(old, list)
  local keep = (changed or #list + 1) - 1

  for i = 1, keep do
    list[i].start, list[i].finish = old[i].start, old[i].finish
  end

  local pending, partial = {}, {}

  for i = 1, keep do
    local same = list[i] == old[i] or Layout.signature(list[i]) == Layout.signature(old[i])

    if resized or not same or self:_live(list[i]) then
      pending[i] = true
    elseif self.pending[i] then
      pending[i], partial[i] = true, self.partial[i]
    end
  end

  self.blocks = list

  for i, block in ipairs(list) do
    block.index = i
  end

  if changed then
    local from = keep > 0 and list[keep].finish or 0
    local tail = Layout.place(list, changed, from)
    local first

    for j = 1, math.max(#tail, #self.lines - from) do
      if self.lines[from + j] ~= tail[j] then
        first = j
        break
      end
    end

    for j = #self.lines, from + 1, -1 do
      self.lines[j] = nil
    end

    for j, line in ipairs(tail) do
      self.lines[from + j] = line
    end

    if first then self:_set_lines(vim.list_slice(tail, first), from + first - 1) end

    local settled = not resized and first and self:_settled(old, list, changed, first) or from

    self.buffer:clear_namespace(Document.NAMESPACE, from, -1)
    self.renderer:clear(settled)

    if settled > from then partial[changed] = settled end

    for i = changed, #list do
      pending[i] = true
    end
  end

  self.changedtick = self.buffer:get_changedtick()
  self.pending = pending
  self.partial = partial
  self:decorate_visible()
  self:_status()
end

function Document:_settled(old, list, changed, first)
  local block, previous = list[changed], old[changed]

  if changed ~= #list or not previous or previous.start ~= block.start then return block.start end
  if not Layout.streaming(list, changed) or not Layout.streaming(old, changed) then return block.start end

  local row = block.start + Layout.settled(block.lines, first)

  if self.pending[changed] then row = math.min(row, self.partial[changed] or block.start) end

  return row
end

function Document:visible_ranges()
  local ranges = {}

  for _, window in ipairs(self.buffer:get_windows()) do
    local top, bottom = window:get_visible_range()
    local margin = window:get_height() * settings:get('margin_screens')

    ranges[#ranges + 1] = { math.max(top - margin, 0), bottom + margin }
  end

  return ranges
end

local function overlaps(block, ranges)
  for _, range in ipairs(ranges) do
    if block.finish > range[1] and block.start < range[2] then return true end
  end

  return false
end

function Document:has_pending(top, bottom)
  for i in pairs(self.pending) do
    local block = self.blocks[i]

    if block and block.finish > top and block.start <= bottom then return true end
  end

  return false
end

function Document:decorate_visible()
  if not next(self.pending) or not self.buffer:is_valid() then return end

  local ranges = self:visible_ranges()

  if #ranges == 0 then return end

  local group

  local function flush()
    if group then self.renderer:render(group[1], group[2]) end
    group = nil
  end

  local due = {}

  for i, block in ipairs(self.blocks) do
    if self.pending[i] and overlaps(block, ranges) then
      local top = self.partial[i] or block.start

      due[#due + 1] = block
      self.pending[i], self.partial[i] = nil, nil

      if Document.RAW[block.kind] then
        flush()
      elseif group and group[2] == block.start then
        group[2] = block.finish
      else
        flush()
        group = { top, block.finish }
      end
    else
      flush()
    end
  end

  flush()

  local ctx = self:_context()

  for _, block in ipairs(due) do
    self:_decorate(block, ctx)
  end
end

function Document:tick(state)
  if not self.buffer:is_valid() then return end

  merge(self.state, state)

  local ctx = self:_context()

  for _, block in ipairs(self.blocks) do
    if self:_live(block) then self:_decorate(block, ctx) end
  end

  self:_status()
end

function Document:_status()
  local buffer = self.buffer

  buffer:clear_namespace(Document.STATUS_NAMESPACE)

  local lines = StatusLine.lines(self.state, Timer.now())

  if not lines then return end

  local last = math.max(buffer:get_line_count() - 1, 0)

  buffer:set_extmark(Document.STATUS_NAMESPACE, last, 0, { virt_lines = lines })
end

return Document
