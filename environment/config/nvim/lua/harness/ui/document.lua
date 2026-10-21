local Buffer = require('core.Buffer')
local DiffLineCalculator = require('harness.transcript.calculators.DiffLineCalculator')
local FoldCalculator = require('harness.transcript.calculators.FoldCalculator')
local Layout = require('harness.transcript.calculators.Layout')
local MarkSpec = require('ui.MarkSpec')
local Object = require('core.Object')
local Renderer = require('ui.markdown.Renderer')
local StatusLine = require('harness.transcript.StatusLine')
local SyntaxAnnotator = require('ui.annotators.SyntaxAnnotator')
local Timer = require('core.Timer')
local buffers = require('core.buffers')
local context = require('harness.transcript.decorators.context')
local decorators = require('harness.transcript.decorators')
local settings = require('harness.settings.transcript')
local theme = require('harness.transcript.theme')

local Document = Object:extend()

Document.NAMESPACE = Buffer.namespace('harness.document')
Document.STATUS_NAMESPACE = Buffer.namespace('harness.document.status')

Document.PRIORITY = MarkSpec.PRIORITY

Document.duration = theme.duration
Document.diff_numbers = DiffLineCalculator.numbers

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
    scheduled = false,
    lines = {},
    blocks = {},
    offsets = {},
    state = { running = false, frame = 1 },
    renderer = Renderer(bufnr, {
      hidden_labels = { output = true, diff = true },
      code_hl = { output = 'UiToolOutput' },
    }),
    syntax = SyntaxAnnotator(),
  }
end

local function merge(state, update)
  for key, value in pairs(update or {}) do
    state[key] = value
  end

  return state
end

function Document:diff_offset(block)
  return DiffLineCalculator.offset(block, buffers.lines_of, self.offsets)
end

function Document:diff_line(block, row)
  return DiffLineCalculator.line(block, row, self:diff_offset(block))
end

function Document:_context()
  local state = self.state

  return {
    running = state.running,
    frame = state.frame,
    waiting = state.waiting,
    agent = state.agent,
    now = Timer.now(),
    syntax = self.syntax,
    diff_offset = function(block)
      return self:diff_offset(block)
    end,
  }
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

  local old = self.blocks
  local changed = Layout.first_changed(old, list)
  local keep = (changed or #list + 1) - 1

  for i = 1, keep do
    list[i].start, list[i].finish = old[i].start, old[i].finish
  end

  local pending = {}

  for i = 1, keep do
    local same = list[i] == old[i] or Layout.signature(list[i]) == Layout.signature(old[i])

    if self.pending[i] or not same or self:_live(list[i]) then pending[i] = true end
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

    self.buffer:clear_namespace(Document.NAMESPACE, from, -1)
    self.renderer:clear(from)

    for i = changed, #list do
      pending[i] = true
    end
  end

  self.changedtick = self.buffer:get_changedtick()
  self.pending = pending
  self:decorate_visible()
  self:_status()
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
      due[#due + 1] = block
      self.pending[i] = nil

      if group and group[2] == block.start then
        group[2] = block.finish
      else
        flush()
        group = { block.start, block.finish }
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

function Document:dispose()
  self.syntax:dispose()
end

return Document
