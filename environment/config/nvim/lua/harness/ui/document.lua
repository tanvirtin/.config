local Object = require('core.Object')
local Renderer = require('ui.markdown.Renderer')
local SyntaxAnnotator = require('ui.annotators.SyntaxAnnotator')
local blocks = require('harness.ui.blocks')

local Block = blocks.Block

local Document = Object:extend()

Document.NAMESPACE = vim.api.nvim_create_namespace('harness.document')
Document.STATUS_NAMESPACE = vim.api.nvim_create_namespace('harness.document.status')

Document.SPINNER = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

Document.TOOL_ICONS = {
  [Block.STATUS.pending] = { '󰔟 ', 'UiToolPending' },
  [Block.STATUS.in_progress] = { '󰔟 ', 'UiToolPending' },
  [Block.STATUS.completed] = { '󰄬 ', 'UiToolDone' },
  [Block.STATUS.failed] = { '󰅖 ', 'UiToolFailed' },
}

Document.STOP_ICONS = {
  end_turn = { '󰄬 ', 'UiToolDone' },
  cancelled = { '󰜺 ', 'UiWarn' },
}

Document.PRIORITY = 300

Document.GUTTER = '  │ '
Document.GUTTER_PRIORITY = 10

Document.USER_ICON = '󰀄 '
Document.AGENT_ICON = '󰚩 '

Document.MARGIN_SCREENS = 2

local documents = setmetatable({}, { __mode = 'v' })

vim.api.nvim_set_decoration_provider(Document.NAMESPACE, {
  on_win = function(_, _, bufnr, top, bottom)
    local document = documents[bufnr]

    if document and not document.scheduled and document:has_pending(top, bottom) then
      document.scheduled = true
      vim.schedule(function()
        document.scheduled = false
        document:decorate_visible()
      end)
    end

    return false
  end,
})

local FINISHED = { [Block.STATUS.completed] = true, [Block.STATUS.failed] = true }

function Document:constructor(bufnr)
  return {
    bufnr = bufnr,
    pending = {},
    scheduled = false,
    lines = {},
    blocks = {},
    offsets = {},
    state = { running = false, frame = 1 },
    renderer = Renderer(bufnr, { hidden_labels = { output = true, diff = true } }),
    syntax = SyntaxAnnotator(),
  }
end

function Document.duration(ms)
  if not ms or ms < 1000 then return nil end

  local seconds = math.floor(ms / 1000)

  if seconds < 60 then return seconds .. 's' end

  return string.format('%dm %ds', math.floor(seconds / 60), seconds % 60)
end

function Document:_mark(row, col, opts)
  opts.priority = opts.priority or Document.PRIORITY
  pcall(vim.api.nvim_buf_set_extmark, self.bufnr, Document.NAMESPACE, row, col, opts)
end

function Document:_spinner()
  return Document.SPINNER[(self.state.frame - 1) % #Document.SPINNER + 1]
end

local function live_tool(self, block)
  return block.kind == Block.KIND.tool and self.state.running and not FINISHED[block.status]
end

Document.WAITING_ICON = { '󰀦 ', 'UiWarn' }

local function waiting_for(self, block)
  for _, request in ipairs(self.state.waiting or {}) do
    if request.id and request.id == block.id then return request end
  end
end

local function count_lines(text)
  local trimmed = (text or ''):gsub('%s+$', '')

  if trimmed == '' then return 0 end

  return select(2, trimmed:gsub('\n', '')) + 1
end

local SUMMARY = {
  [Block.CATEGORY.read] = function(block)
    local n = count_lines(block.output)
    return n > 0 and string.format('Read %d line%s', n, n == 1 and '' or 's') or nil
  end,
  [Block.CATEGORY.search] = function(block)
    local n = count_lines(block.output)
    return string.format('%d result%s', n, n == 1 and '' or 's')
  end,
}

local DECORATE = {}

Document.SEPARATOR_WIDTH = 400

function DECORATE.prompt(self, block)
  local header = {
    { { ' ' .. Document.USER_ICON .. 'You', 'UiSpeakerUser' }, block.steered and { ' · steered', 'UiMuted' } or nil },
  }

  if not block.first and not block.steered then
    table.insert(header, 1, { { string.rep('─', Document.SEPARATOR_WIDTH), 'UiTurnSeparator' } })
  end

  self:_mark(block.start, 0, { virt_lines = header, virt_lines_above = true })

  for row = block.start, block.finish - 2 do
    self:_mark(row, 0, {
      end_col = 1,
      virt_text = { { '▌', 'UiPromptBar' } },
      virt_text_pos = 'overlay',
      line_hl_group = 'UiPrompt',
    })
  end
end

function DECORATE.tool(self, block)
  local row = block.start
  local live = live_tool(self, block)
  local waiting = live and waiting_for(self, block)
  local icon = waiting and Document.WAITING_ICON
    or live and { self:_spinner() .. ' ', 'UiToolPending' }
    or Document.TOOL_ICONS[block.status]
    or Document.TOOL_ICONS[Block.STATUS.pending]

  self:_mark(row, 0, { end_col = 3, conceal = '' })
  self:_mark(row, 0, { virt_text = { icon }, virt_text_pos = 'inline' })
  self:_mark(row, 3, { end_col = 3 + #block.name, hl_group = 'UiToolName' })

  local tail = {}

  if block.nested then
    tail[#tail + 1] = { string.format('%d tool%s', block.nested, block.nested == 1 and '' or 's'), 'UiMuted' }
  end

  if block.added or block.removed then
    if #tail > 0 then tail[#tail + 1] = { '  ' } end
    tail[#tail + 1] = { '+' .. (block.added or 0), 'UiAdded' }
    tail[#tail + 1] = { ' ' }
    tail[#tail + 1] = { '-' .. (block.removed or 0), 'UiRemoved' }
  end

  if waiting then
    tail[#tail + 1] = { (#tail > 0 and '  ' or '') .. 'waiting for you', 'UiWarn' }
  elseif live and block.started then
    local elapsed = Document.duration(vim.uv.now() - block.started)
    if elapsed then tail[#tail + 1] = { (#tail > 0 and '  ' or '') .. elapsed, 'UiMuted' } end
  end

  if #tail > 0 then
    table.insert(tail, 1, { '  ' })
    self:_mark(row, 0, { virt_text = tail, virt_text_pos = 'eol' })
  end

  local body = #block.lines > 1

  if body then
    local failed = block.status == Block.STATUS.failed

    for body_row = row + 2, block.start + #block.lines - 2 do
      self:_mark(body_row, 0, {
        virt_text = { { body_row == row + 2 and '⎿ ' or '  ', 'UiMuted' } },
        virt_text_pos = 'inline',
      })

      if failed then self:_mark(body_row, 0, { end_row = body_row + 1, hl_group = 'UiError', hl_eol = false }) end
    end
  elseif FINISHED[block.status] and SUMMARY[block.category] then
    local summary = SUMMARY[block.category](block)

    if summary then
      local line = { { '  ⎿ ', 'UiMuted' }, { summary, 'UiMuted' } }

      if block.depth then table.insert(line, 1, { Document.GUTTER, 'UiMuted' }) end

      self:_mark(row, 0, { virt_lines = { line } })
    end
  end
end

local function hunk_start(line)
  local old, new = line:match('^@@ %-(%d+)[,%d]* %+(%d+)')

  return tonumber(old) or 0, tonumber(new) or 0
end

function Document.diff_numbers(lines)
  local numbers = {}
  local old_line, new_line = 0, 0

  for offset = 3, #lines - 1 do
    local line = lines[offset]
    local mark = line:sub(1, 1)

    if mark == '@' then
      old_line, new_line = hunk_start(line)
      numbers[offset] = { mark = '@' }
    elseif mark == '+' then
      numbers[offset] = { mark = '+', number = new_line, new = new_line, old = old_line }
      new_line = new_line + 1
    elseif mark == '-' then
      numbers[offset] = { mark = '-', number = old_line, new = new_line, old = old_line }
      old_line = old_line + 1
    else
      numbers[offset] = { mark = ' ', number = new_line, new = new_line, old = old_line }
      old_line, new_line = old_line + 1, new_line + 1
    end
  end

  return numbers
end

local function file_lines(path)
  local bufnr = vim.fn.bufnr(path)

  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) end
  if vim.fn.filereadable(path) == 1 then return vim.fn.readfile(path) end

  return {}
end

local function find_sequence(haystack, needle)
  if #needle == 0 then return nil end

  for i = 1, #haystack - #needle + 1 do
    local found = true

    for j = 1, #needle do
      if haystack[i + j - 1] ~= needle[j] then
        found = false
        break
      end
    end

    if found then return i end
  end
end

local function side_of(block, numbers, skip)
  local lines, first = {}, nil

  for offset = 3, #block.lines - 1 do
    local entry = numbers[offset]

    if entry and entry.mark == '@' and #lines > 0 then break end

    if entry and entry.mark ~= '@' and entry.mark ~= skip then
      first = first or (skip == '-' and entry.new or entry.old)
      lines[#lines + 1] = block.lines[offset]:sub(2)
    end
  end

  return lines, first
end

function Document:diff_offset(block)
  if not block.path then return nil end

  local numbers = Document.diff_numbers(block.lines)
  local key = block.path .. '\0' .. table.concat(block.lines, '\n')

  if self.offsets[key] then return self.offsets[key] end

  local file = file_lines(block.path)

  for _, skip in ipairs({ '-', '+' }) do
    local lines, first = side_of(block, numbers, skip)
    local found = first and find_sequence(file, lines)

    if found then
      if skip == '-' then self.offsets[key] = found - first end
      return found - first
    end
  end
end

function Document:diff_line(block, row)
  local entry = Document.diff_numbers(block.lines)[row - block.start + 1]
  local offset = self:diff_offset(block)

  return entry and entry.new and offset and entry.new + offset or nil
end

local DIFF_HL = { ['+'] = 'UiDiffAdd', ['-'] = 'UiDiffDelete' }
local MARK_HL = { ['+'] = 'UiAdded', ['-'] = 'UiRemoved' }

function DECORATE.diff(self, block)
  local path = block.lines[2]:sub(5)
  local filetype = vim.filetype.match({ filename = path }) or ''

  self:_mark(block.start + 1, 0, { end_col = 4, conceal = '' })
  self:_mark(block.start + 1, 0, { virt_text = { { '󰈔 ', 'UiPath' } }, virt_text_pos = 'inline' })
  self:_mark(block.start + 1, 4, { end_col = #block.lines[2], hl_group = 'UiPath' })

  local sides = { new = { lines = {}, rows = {} }, old = { lines = {}, rows = {} } }
  local shift = self:diff_offset(block)

  for offset, entry in pairs(Document.diff_numbers(block.lines)) do
    local row = block.start + offset - 1
    local line = block.lines[offset]

    if entry.mark == '@' then
      self:_mark(row, 0, { end_col = #line, conceal = '' })
      self:_mark(row, 0, { virt_text = { { '┈┈┈┈', 'UiMuted' } }, virt_text_pos = 'inline' })
    else
      self:_mark(row, 0, {
        virt_text = { { shift and string.format('%4d ', entry.number + shift) or '  ', 'UiDiffLineNr' } },
        virt_text_pos = 'inline',
        line_hl_group = DIFF_HL[entry.mark],
      })

      if MARK_HL[entry.mark] then self:_mark(row, 0, { end_col = 1, hl_group = MARK_HL[entry.mark] }) end

      local targets = entry.mark == '+' and { sides.new }
        or entry.mark == '-' and { sides.old }
        or { sides.new, sides.old }

      for _, target in ipairs(targets) do
        target.lines[#target.lines + 1] = line:sub(2)
        target.rows[#target.rows + 1] = row
      end
    end
  end

  if filetype == '' then return end

  local seen = {}

  for _, side in pairs(sides) do
    for _, highlight in ipairs(self.syntax:annotate(side.lines, filetype)) do
      local row = side.rows[highlight.row + 1]
      local key = row and string.format('%d:%d:%s', row, highlight.col_start, highlight.hl_group)

      if row and not seen[key] then
        seen[key] = true

        local text = block.lines[row - block.start + 1]
        local end_col = highlight.col_end == -1 and #text or highlight.col_end + 1

        self:_mark(row, highlight.col_start + 1, { end_col = end_col, hl_group = highlight.hl_group, priority = 150 })
      end
    end
  end
end

function DECORATE.thought(self, block)
  local text

  if block.live and self.state.running then
    text = { { '  ' .. self:_spinner() .. ' thinking', 'UiMuted' } }
  elseif block.started and block.finished then
    local duration = Document.duration(block.finished - block.started)
    if duration then text = { { '  ' .. duration, 'UiMuted' } } end
  end

  if text then self:_mark(block.start, 0, { virt_text = text, virt_text_pos = 'eol' }) end
end

function DECORATE.stop(self, block)
  local icon = Document.STOP_ICONS[block.reason] or { '󰀪 ', 'UiWarn' }
  local parts = { blocks.STOP_REASONS[block.reason] or tostring(block.reason) }
  local duration = Document.duration(block.duration)

  if duration then parts[1] = parts[1] .. ' in ' .. duration end
  if block.tools and block.tools > 0 then
    parts[#parts + 1] = string.format('%d tool%s', block.tools, block.tools == 1 and '' or 's')
  end

  self:_mark(block.start, 0, { end_col = #block.lines[1], conceal = '' })
  self:_mark(block.start, 0, {
    virt_text = { icon, { table.concat(parts, ' · '), 'UiMuted' } },
    virt_text_pos = 'inline',
  })
end

function DECORATE.note(self, block)
  if not block.error then return end

  for row = block.start, block.start + #block.lines - 1 do
    self:_mark(row, 0, { end_row = row + 1, hl_group = 'UiError', hl_eol = false })
  end
end

function Document:_decorate(block)
  vim.api.nvim_buf_clear_namespace(self.bufnr, Document.NAMESPACE, block.start, block.finish)

  if DECORATE[block.kind] then DECORATE[block.kind](self, block) end

  if block.depth then
    for row = block.start, block.finish - 1 do
      self:_mark(row, 0, {
        virt_text = { { Document.GUTTER, 'UiMuted' } },
        virt_text_pos = 'inline',
        priority = Document.GUTTER_PRIORITY,
      })
    end
  end

  if block.opens_reply then
    self:_mark(block.start, 0, {
      virt_lines = { { { ' ' .. Document.AGENT_ICON .. (self.state.agent or 'Agent'), 'UiSpeakerAgent' } } },
      virt_lines_above = true,
    })
  end
end

local function block_at(list, row)
  local low, high = 1, #list

  while low <= high do
    local mid = math.floor((low + high) / 2)
    local block = list[mid]

    if row < block.start then
      high = mid - 1
    elseif row >= block.finish then
      low = mid + 1
    else
      return block
    end
  end

  return list[#list]
end

local function same_lines(a, b)
  if #a ~= #b then return false end

  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end

  return true
end

local function streaming(list, i)
  return i == #list and list[i].kind == Block.KIND.message
end

local function first_changed(old, new)
  for i = 1, math.max(#old, #new) do
    local a, b = old[i], new[i]

    if not a or not b then return i end
    if a ~= b and (a.kind ~= b.kind or not same_lines(a.lines, b.lines)) then return i end
    if streaming(old, i) ~= streaming(new, i) then return i end
  end
end

local function layout(list, from, row)
  local lines, n = {}, 0

  for i = from, #list do
    local block = list[i]

    block.start = row + n

    for _, line in ipairs(block.lines) do
      n = n + 1
      lines[n] = line
    end

    if not streaming(list, i) then
      n = n + 1
      lines[n] = ''
    end

    block.finish = row + n
  end

  return lines
end

local function signature(block)
  return table.concat({
    block.kind,
    tostring(block.status),
    tostring(block.finished),
    tostring(block.live),
    tostring(block.added),
  }, ':')
end

function Document:reset()
  self.lines = {}
  self.blocks = {}
  self.pending = {}
end

function Document:attach()
  documents[self.bufnr] = self
  return self
end

function Document:stale()
  return self.changedtick ~= vim.api.nvim_buf_get_changedtick(self.bufnr)
end

function Document:fold_level(row)
  local block = block_at(self.blocks, row)

  if not block or row < block.start or row >= block.finish then return '0' end

  local base = block.depth or 0

  for _, fold in ipairs(block.folds or {}) do
    local from, to = block.start + fold[1], block.start + fold[2]

    if to > from then
      if row == from then return '>' .. (base + 1) end
      if row > from and row <= to then return tostring(base + 1) end
    end
  end

  if base > 0 then
    local previous = block.index and self.blocks[block.index - 1]
    local opens = not previous or previous.parent ~= block.parent

    if opens and row == block.start then return '>' .. base end

    return tostring(base)
  end

  return '0'
end

function Document:write(list, state)
  if not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  self.state = vim.tbl_extend('force', self.state, state or {})

  local old = self.blocks
  local changed = first_changed(old, list)
  local keep = (changed or #list + 1) - 1

  for i = 1, keep do
    list[i].start, list[i].finish = old[i].start, old[i].finish
  end

  local pending = {}

  for i = 1, keep do
    local same = list[i] == old[i] or signature(list[i]) == signature(old[i])

    if self.pending[i] or not same or list[i].live or live_tool(self, list[i]) then pending[i] = true end
  end

  self.blocks = list

  for i, block in ipairs(list) do
    block.index = i
  end

  if changed then
    local from = keep > 0 and list[keep].finish or 0
    local tail = layout(list, changed, from)
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

    if first then
      local modifiable = vim.bo[self.bufnr].modifiable

      vim.bo[self.bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(self.bufnr, from + first - 1, -1, false, vim.list_slice(tail, first))
      vim.bo[self.bufnr].modifiable = modifiable
      vim.bo[self.bufnr].modified = false
    end

    vim.api.nvim_buf_clear_namespace(self.bufnr, Document.NAMESPACE, from, -1)
    self.renderer:clear(from)

    for i = changed, #list do
      pending[i] = true
    end
  end

  self.changedtick = vim.api.nvim_buf_get_changedtick(self.bufnr)
  self.pending = pending
  self:decorate_visible()
  self:_status()
end

function Document:visible_ranges()
  local ranges = {}

  for _, win in ipairs(vim.fn.win_findbuf(self.bufnr)) do
    local top, bottom = vim.fn.line('w0', win), vim.fn.line('w$', win)
    local margin = vim.api.nvim_win_get_height(win) * Document.MARGIN_SCREENS

    ranges[#ranges + 1] = { math.max(top - 1 - margin, 0), bottom + margin }
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
  if not next(self.pending) or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

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

  for _, block in ipairs(due) do
    self:_decorate(block)
  end
end

function Document:tick(state)
  if not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  self.state = vim.tbl_extend('force', self.state, state or {})

  for _, block in ipairs(self.blocks) do
    if block.live or live_tool(self, block) then self:_decorate(block) end
  end

  self:_status()
end

Document.QUEUE_ICON = '󰔟 '

function Document:_queue_lines()
  local lines = {}

  for _, text in ipairs(self.state.queue or {}) do
    local first = vim.split(vim.trim(text), '\n', { plain = true })[1] or ''

    lines[#lines + 1] = {
      { '  ' .. Document.QUEUE_ICON, 'UiMuted' },
      { 'queued ', 'UiMuted' },
      { require('compact').line(first, 120), 'UiPromptBar' },
    }
  end

  return lines
end

function Document:_status()
  vim.api.nvim_buf_clear_namespace(self.bufnr, Document.STATUS_NAMESPACE, 0, -1)

  local queued = self:_queue_lines()
  local last = math.max(vim.api.nvim_buf_line_count(self.bufnr) - 1, 0)

  if not self.state.running then
    if #queued > 0 then
      table.insert(queued, 1, { { '' } })
      pcall(vim.api.nvim_buf_set_extmark, self.bufnr, Document.STATUS_NAMESPACE, last, 0, { virt_lines = queued })
    end

    return
  end

  local ask = (self.state.asks or {})[1]

  if ask then
    local choices = { { '   ' } }

    for _, choice in ipairs(require('harness.ui.transcript').CHOICES) do
      choices[#choices + 1] = { choice.key, 'UiAccent' }
      choices[#choices + 1] = { ' ' .. choice.label .. '   ' }
    end

    choices[#choices + 1] = { '<C-c>', 'UiAccent' }
    choices[#choices + 1] = { ' interrupt', 'UiMuted' }

    local more = #self.state.asks > 1 and { string.format('  (+%d more)', #self.state.asks - 1), 'UiMuted' } or nil
    local question = { Document.WAITING_ICON, { 'Allow ', 'UiWarn' }, { ask.text, 'UiPromptBar' }, { '?', 'UiWarn' } }

    if more then question[#question + 1] = more end

    pcall(vim.api.nvim_buf_set_extmark, self.bufnr, Document.STATUS_NAMESPACE, last, 0, {
      virt_lines = vim.list_extend({ { { '' } }, question, choices }, queued),
    })

    return
  end

  local elapsed = self.state.started and Document.duration(vim.uv.now() - self.state.started)
  local request = (self.state.waiting or {})[1]
  local chunks = request
      and {
        Document.WAITING_ICON,
        { 'Waiting for you: ', 'UiWarn' },
        { require('compact').line(request.title or request.tool or 'a tool', 80), 'UiPromptBar' },
        { ' · answer the prompt, or ', 'UiMuted' },
        { '<C-c>', 'UiAccent' },
        { ' to interrupt', 'UiMuted' },
      }
    or {
      { self:_spinner() .. ' ', 'UiAccent' },
      { self.state.label or 'Working', 'UiAccent' },
      { elapsed and ' · ' .. elapsed or '', 'UiMuted' },
      { ' · ', 'UiMuted' },
      { '<C-c>', 'UiAccent' },
      { ' interrupt', 'UiMuted' },
    }
  pcall(vim.api.nvim_buf_set_extmark, self.bufnr, Document.STATUS_NAMESPACE, last, 0, {
    virt_lines = vim.list_extend({ { { '' } }, chunks }, queued),
  })
end

function Document:block_at(row)
  return block_at(self.blocks, row)
end

function Document:dispose()
  self.syntax:dispose()
end

return Document
