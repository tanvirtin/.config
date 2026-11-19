local text = require('core.text')
local Timer = require('core.Timer')
local Object = require('core.Object')
local MarkSpec = require('ui.MarkSpec')
local Buffer = require('core.editor.Buffer')
local Renderer = require('ui.markdown.Renderer')
local Block = require('sn.transcript.model.Block')
local settings = require('sn.settings.transcript')
local content = require('sn.transcript.model.content')
local decorators = require('sn.transcript.decorators')
local status_line = require('sn.transcript.status_line')
local Following = require('sn.transcript.view.Following')
local context = require('sn.transcript.decorators.context')
local builtin = require('sn.transcript.model.content.builtin')
local Layout = require('sn.transcript.model.calculators.Layout')
local FoldCalculator = require('sn.transcript.model.calculators.FoldCalculator')

builtin()
require('sn.transcript.model.content.json')
require('sn.transcript.model.content.markdown')
require('sn.transcript.model.content.table')

local Document = Object:extend()

Document.NAMESPACE = Buffer.namespace('sn.document')

Document.SPLICE_LINES = 400
Document.STATUS_NAMESPACE = Buffer.namespace('sn.document.status')

local documents = setmetatable({}, { __mode = 'v' })

Buffer.set_decoration_provider(Document.NAMESPACE, function(bufnr, top, bottom)
  local document = documents[bufnr]

  if document and not document.scheduled and document:has_pending(top, bottom) then
    document.scheduled = true
    Timer.defer(0, function()
      document.scheduled = false

      if document:decorate_visible() and document.on_decorate then document.on_decorate() end
    end)
  end
end)

function Document:constructor(bufnr)
  return {
    bufnr = bufnr,
    buffer = Buffer(bufnr),
    pending = {},
    partial = {},
    deferred = {},
    decorated = {},
    revealed = {},
    scheduled = false,
    lines = {},
    blocks = {},
    state = { running = false, frame = 1 },
    renderer = Renderer(bufnr, {
      hidden_labels = { output = true, terminal = true, split = true, diff = true, edit = true },
      code_hl = { output = 'UiToolOutput', terminal = 'UiTerminal', split = false },
      defer_callouts = true,
    }),
  }
end

function Document:_merge(state, update)
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
    plan_open = state.plan_open,
    width = self.width,
    revealed = self.revealed,
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
  self.deferred = {}

  self:decorate_visible()
end

Document.COMMAND_LANG = { [Block.CATEGORY.execute] = 'bash' }

function Document:_decorate(block, ctx)
  local decorate_ctx = ctx or self:_context()
  local marks = decorators.decorate(block, decorate_ctx)
  local extra = content.decorate(block, decorate_ctx)

  if extra then vim.list_extend(marks, extra) end

  local treesitter = content.option(block, 'treesitter')

  if treesitter then vim.list_extend(marks, Renderer.content(block, treesitter)) end

  local table_spec = content.option(block, 'table')

  if table_spec then
    vim.list_extend(marks, require('sn.transcript.model.content.table').render(block, table_spec, decorate_ctx))
  end

  self:_links(marks, block)

  local lang = block.kind == Block.KIND.tool and block.argument and Document.COMMAND_LANG[block.category]

  if lang and Renderer.ready(lang, function()
    self:_redecorate(lang)
  end) then
    Renderer.code(marks, block.argument, lang, block.start, #block.lines[1] - #block.argument)
  end

  self.buffer:clear_namespace(Document.NAMESPACE, block.start, block.finish)
  MarkSpec.apply(self.buffer, Document.NAMESPACE, marks)

  if block.index then self.decorated[block.index] = true end
end

function Document:redecorate_kind(kind)
  if not self.buffer:is_valid() then return end

  local ctx = self:_context()

  for _, block in ipairs(self.blocks) do
    if block.kind == kind then self:_decorate(block, ctx) end
  end
end

function Document:_links(marks, block)
  local resolve = self.renderer.resolve

  for _, link in ipairs(block.links or {}) do
    local row = block.start + link.row - 1
    local decoration = resolve and resolve(Renderer.INLINE.link, link.target)

    if decoration then
      MarkSpec.add(marks, row, link.col, { virt_text = { decoration.icon }, virt_text_pos = 'inline' })
    end

    MarkSpec.add(marks, row, link.col, {
      end_col = link.end_col,
      hl_group = 'UiMarkdownLink',
      priority = Renderer.LINK_PRIORITY,
    })
  end

  return marks
end

function Document:_live(block)
  return block.live or context.live_tool(block, self.state)
end

function Document:reset()
  self.lines = self.buffer:is_valid() and self.buffer:get_lines() or {}
  self.blocks = {}
  self.pending = {}
  self.partial = {}
  self.deferred = {}
  self.decorated = {}
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

function Document:toggle_live(block)
  if not block or not block.live or not block.first_event then return false end

  local key = block.first_event

  self.revealed[key] = not self.revealed[key] or nil

  if self.buffer:is_valid() then self:_decorate(block) end

  return self.revealed[key] == true
end

function Document:_set_lines(lines, from, to)
  local buffer = self.buffer
  local modifiable = buffer:get_option('modifiable')

  buffer:set_option('modifiable', true)

  if to then
    buffer:set_lines(lines, from, to)
  else
    for _, edit in ipairs(Document.edits(self.buffer:get_lines(from, -1), lines, from, self:_watched_below(from))) do
      buffer:set_lines(edit.lines, edit.from, edit.to)
    end

    if buffer:get_line_count() ~= from + #lines then buffer:set_lines(lines, from, -1) end
  end

  buffer:set_option('modifiable', modifiable)
  buffer:set_option('modified', false)
end

function Document:_watched_below(row)
  for _, window in ipairs(self.buffer:get_windows()) do
    if window:get_cursor()[1] > row + 1 then return true end
  end

  return #self.buffer:get_extmarks(Following.ANCHOR, { row, 0 }, -1, { limit = 1 }) > 0
end

function Document.edits(old, new, offset, splice)
  if not splice and #old + #new < Document.SPLICE_LINES then
    return { { lines = new, from = offset, to = offset + #old } }
  end

  local out = {}
  local hunks = text.hunks(old, new)

  for h = #hunks, 1, -1 do
    local old_start, old_count, new_start, new_count = unpack(hunks[h])
    local from = offset + (old_count == 0 and old_start or old_start - 1)

    out[#out + 1] = {
      lines = new_count == 0 and {} or vim.list_slice(new, new_start, new_start + new_count - 1),
      from = from,
      to = from + old_count,
    }
  end

  return out
end

function Document:write(list, state)
  if not self.buffer:is_valid() then return end

  self:_merge(self.state, state)

  local width = self:text_width()
  local resized = width ~= nil and width ~= self.width

  if resized then self.width = width end

  self.touched = nil

  local old = self.blocks
  local changed = Layout.first_changed(old, list)
  local keep = (changed or #list + 1) - 1

  for i = 1, keep do
    list[i].start, list[i].finish = old[i].start, old[i].finish
  end

  local pending, partial, deferred = {}, {}, {}

  for i = 1, keep do
    local same = list[i] == old[i] or Layout.signature(list[i]) == Layout.signature(old[i])

    if resized or not same or self:_live(list[i]) then
      pending[i] = true
    elseif self.pending[i] then
      pending[i], partial[i] = true, self.partial[i]
    elseif self.deferred[i] then
      deferred[i] = true
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

    self.touched = first and { from = from + first - 1, to = #self.lines - 1 } or nil

    local settled = not resized and first and self:_settled(old, list, changed, first) or from

    self.buffer:clear_namespace(Document.NAMESPACE, from, -1)
    self.renderer:clear(settled)

    for i in pairs(self.decorated) do
      if i >= changed then self.decorated[i] = nil end
    end

    if settled > from then partial[changed] = settled end

    for i = changed, #list do
      pending[i] = true
    end
  end

  self.changedtick = self.buffer:get_changedtick()
  self.pending = pending
  self.partial = partial
  self.deferred = deferred
  self:decorate_visible()
  self:_status()
end

function Document.growing(list, i)
  local block = list[i]

  if i ~= #list then return false end
  if content.option(block, 'live') then return block.live == true end

  return Layout.streaming(list, i)
end

function Document:_settled(old, list, changed, first)
  local block, previous = list[changed], old[changed]

  if not block then return nil end
  if not previous or previous.start ~= block.start or previous.kind ~= block.kind then return block.start end
  if not Document.growing(list, changed) or not Document.growing(old, changed) then return block.start end

  local row = block.start + Layout.settled(block.lines, first)

  if self.pending[changed] or self.deferred[changed] then row = math.min(row, self.partial[changed] or block.start) end

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

function Document:_overlaps(block, ranges)
  for _, range in ipairs(ranges) do
    if block.finish > range[1] and block.start < range[2] then return true end
  end

  return false
end

function Document:_redecorate(lang)
  if not self.buffer:is_valid() then return end

  local ctx, ranges = self:_context(), self:visible_ranges()

  for i, block in ipairs(self.blocks) do
    local command = block.kind == Block.KIND.tool and Document.COMMAND_LANG[block.category] == lang

    if command and not self.pending[i] and self:_overlaps(block, ranges) then self:_decorate(block, ctx) end
  end
end

function Document:redecorate(index)
  local block = self.blocks[index]

  if not block or not self.buffer:is_valid() then return end
  if self.pending[index] or not self.decorated[index] then return end

  self:_decorate(block)
end

function Document:has_pending(top, bottom)
  for _, set in ipairs({ self.pending, self.deferred }) do
    for i in pairs(set) do
      local block = self.blocks[i]

      if block and block.finish > top and block.start <= bottom then return true end
    end
  end

  local first = Layout.block_at(self.blocks, top)

  for i = first and first.index or 1, #self.blocks do
    local block = self.blocks[i]

    if block.start > bottom then break end
    if not self.decorated[i] and block.finish > top then return true end
  end

  return false
end

function Document:_undecorate(from, to)
  self.buffer:clear_namespace(Document.NAMESPACE, from, to)
  self.buffer:clear_namespace(Renderer.NAMESPACE, from, to)
end

function Document:_trim(ranges)
  local stale = {}

  for i in pairs(self.decorated) do
    local block = self.blocks[i]

    if not block or not self:_overlaps(block, ranges) then stale[#stale + 1] = i end
  end

  if #stale == 0 then return end

  table.sort(stale)

  local from, to

  local function flush()
    if from then self:_undecorate(from, to) end
    from, to = nil, nil
  end

  for _, i in ipairs(stale) do
    local block = self.blocks[i]

    self.decorated[i] = nil

    if block and from and block.start == to then
      to = block.finish
    else
      flush()

      if block then
        from, to = block.start, block.finish
      end
    end
  end

  flush()
end

function Document:_undecorated(ranges)
  for _, range in ipairs(ranges) do
    local first = Layout.block_at(self.blocks, range[1])

    for i = first and first.index or 1, #self.blocks do
      local block = self.blocks[i]

      if block.start >= range[2] then break end
      if not self.decorated[i] and block.finish > range[1] then return true end
    end
  end

  return false
end

function Document:folded(block)
  if #block.lines < 2 then return false end

  for _, window in ipairs(self.buffer:get_windows()) do
    if not window:fold_closed(block.start + 2) then return false end
  end

  return true
end

function Document:decorate_visible()
  if not self.buffer:is_valid() then return end

  local ranges = self:visible_ranges()

  if #ranges == 0 then
    self:_trim({})
    return false
  end

  self:_trim(ranges)

  if not next(self.pending) and not next(self.deferred) and not self:_undecorated(ranges) then return false end

  local group

  local function flush()
    if group then self.renderer:render(group[1], group[2], group[3]) end
    group = nil
  end

  local due = {}

  for i, block in ipairs(self.blocks) do
    local waiting = self.pending[i] or self.deferred[i] or not self.decorated[i]

    if waiting and self:_overlaps(block, ranges) and content.option(block, 'quote') and self:folded(block) then
      flush()

      if self.pending[i] or not self.decorated[i] then
        self.renderer:render(block.start, block.start + 1)
        self.decorated[i] = true
        due[#due + 1] = block
        self.pending[i], self.partial[i], self.deferred[i] = nil, nil, true
      end
    elseif waiting and self:_overlaps(block, ranges) then
      local top = self.partial[i] or block.start

      due[#due + 1] = block
      self.pending[i], self.partial[i], self.deferred[i] = nil, nil, nil

      if content.mode(block) == 'raw' then
        flush()
      elseif group and group[2] == block.start then
        group[2] = block.finish
      else
        flush()
        group = { top, block.finish, content.option(block, 'quote') and block.start or top }
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

  return #due > 0
end

function Document:tick(state)
  if not self.buffer:is_valid() then return end

  self:_merge(self.state, state)

  local ctx = self:_context()

  for _, block in ipairs(self.blocks) do
    if self:_live(block) then self:_decorate(block, ctx) end
  end

  self:_status()
end

function Document:_status()
  local buffer = self.buffer
  local shown = self.status
  local lines = status_line.lines(self.state, Timer.now())

  if not lines then
    buffer:clear_namespace(Document.STATUS_NAMESPACE)
    self.status = nil

    return
  end

  local last = math.max(buffer:get_line_count() - 1, 0)

  if not shown then buffer:clear_namespace(Document.STATUS_NAMESPACE) end

  if
    shown
    and buffer:get_extmark_row(Document.STATUS_NAMESPACE, shown.id) == last
    and vim.deep_equal(shown.lines, lines)
  then
    return
  end

  local id = buffer:set_extmark(Document.STATUS_NAMESPACE, last, 0, { id = shown and shown.id, virt_lines = lines })

  self.status = id and { id = id, lines = lines } or nil
end

return Document
