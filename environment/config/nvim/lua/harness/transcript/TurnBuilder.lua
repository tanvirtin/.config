local compact = require('compact')
local Object = require('core.Object')
local fences = require('core.fences')
local context = require('harness.context')
local EditLog = require('harness.edits.EditLog')
local Block = require('harness.transcript.Block')
local EVENT = require('harness.types.events').KIND
local settings = require('harness.settings.transcript')
local elicitation = require('harness.types.elicitation')
local block_text = require('harness.transcript.block_text')
local tool_label = require('harness.transcript.tool_label')
local output_style = require('harness.transcript.output_style')

local TurnBuilder = Object:extend()

TurnBuilder.FINISHED = { [Block.STATUS.completed] = true, [Block.STATUS.failed] = true }

TurnBuilder.TOOL = { tool_call = true, tool_update = true }

TurnBuilder.TOOL_FIELDS = { 'title', 'name', 'category', 'status', 'locations', 'output' }

TurnBuilder.BODY = {
  [Block.CATEGORY.execute] = true,
  [Block.CATEGORY.search] = true,
  [Block.CATEGORY.fetch] = true,
  [Block.CATEGORY.other] = true,
}

TurnBuilder.SURFACE = { [Block.CATEGORY.execute] = output_style.TERMINAL }

function TurnBuilder:constructor(history, range, opts)
  opts = opts or {}

  return {
    history = history,
    from = range.from,
    to = range.to,
    last_turn = range.last_turn,
    updates = range.updates,
    opts = opts,
    times = opts.times or {},
    edits = opts.edits or EditLog(),
    text = opts.outputs == false,
    list = {},
    tools = {},
    states = {},
    plans = {},
    diffs_shown = {},
    turn = { tools = 0 },
  }
end

function TurnBuilder:_tool_indices()
  local history, indices, own = self.history, {}, {}

  for i = self.from, self.to do
    local event = history[i]

    if TurnBuilder.TOOL[event.kind] then indices[#indices + 1] = i end
    if event.kind == EVENT.tool_call then own[event.id] = true end
  end

  for id in pairs(own) do
    for _, i in ipairs(self.updates and self.updates[id] or {}) do
      if i > self.to then indices[#indices + 1] = i end
    end
  end

  table.sort(indices)

  return indices
end

function TurnBuilder:_collect_states()
  local history, states = self.history, {}

  for _, i in ipairs(self:_tool_indices()) do
    local event = history[i]

    if TurnBuilder.TOOL[event.kind] then
      local state = states[event.id] or { started = i, input = {} }

      for _, key in ipairs(TurnBuilder.TOOL_FIELDS) do
        if event[key] ~= nil then state[key] = event[key] end
      end

      if event.diffs and #event.diffs > 0 then state.diffs = event.diffs end
      state.parent = state.parent or event.parent

      for key, value in pairs(event.input or {}) do
        state.input[key] = value
      end

      if TurnBuilder.FINISHED[event.status] then state.finished = i end

      states[event.id] = state
    end
  end

  self.states = states

  return self
end

function TurnBuilder:_collect_plans()
  local history, last, latest = self.history, {}, nil

  for i = self.from, self.to do
    local event = history[i]

    if event.kind == EVENT.prompt or event.kind == EVENT.user then
      if latest then last[latest] = true end
      latest = nil
    elseif event.kind == EVENT.plan then
      latest = i
    end
  end

  if latest then last[latest] = true end

  self.plans = last

  return self
end

function TurnBuilder:_add(kind, lines, fields)
  local list = self.list

  list[#list + 1] = Block.make(kind, lines, fields)

  return list[#list]
end

function TurnBuilder:_stream(kind, text, i, parent, message_id)
  local last = self.list[#self.list]

  if last and last.kind == kind and last.parent == parent then
    last.text = last.text .. text
    last.last_event = i
    last.message_id = message_id or last.message_id
  else
    self:_add(kind, {}, {
      text = text,
      first_event = i,
      last_event = i,
      parent = parent,
      depth = parent and 1 or nil,
      message_id = message_id,
    })
  end

  return self
end

function TurnBuilder:_show_diffs(id, tool)
  local state = self.states[id] or {}

  if self.diffs_shown[id] or not state.diffs then return self end

  self.diffs_shown[id] = true

  for index, diff in ipairs(state.diffs) do
    local edit = self.edits:get(
      diff,
      id .. ':' .. index,
      TurnBuilder.FINISHED[state.status] == true,
      state.status == Block.STATUS.failed
    )
    if not self.text then edit:patch(self.opts.width) end
    local layout = not self.text and edit:patch().layout or nil
    local lines = block_text.diff(edit, tool_label.relative(diff.path, self.opts.dir), self.text, layout)
    local patch = not self.text and edit:patch() or nil
    local stat = edit:stat()
    local added, removed = stat.added, stat.removed
    local last = self.list[#self.list]
    local preview = settings:get('diff_preview_lines')
    local folds = {}

    if patch and #patch.lines > preview + 1 then folds[1] = { Block.DIFF_HEADER + preview, #lines - 2 } end

    self:_add(Block.KIND.diff, lines, {
      id = id,
      patch = patch and {
        layout = patch.layout,
        rows = patch.rows,
        highlights = patch.highlights,
        words = patch.words,
        voids = patch.voids,
        syntax = function()
          return edit:syntax()
        end,
      } or nil,
      whole = edit.whole,
      edit = edit.file,
      folds = folds,
      attached = last ~= nil and last.id == id and (last.kind == Block.KIND.tool or last.kind == Block.KIND.diff),
      path = diff.path,
      added = added,
      removed = removed,
      status = state.status,
      parent = state.parent,
      depth = state.parent and 1 or nil,
    })

    if tool then
      tool.added = (tool.added or 0) + added
      tool.removed = (tool.removed or 0) + removed
    end
  end

  return self
end

function TurnBuilder:on_prompt(event, i)
  if not event.steered then self.turn = { tools = 0, started = self.times[i] } end

  local text, found = context.selections_in(context.strip(event.text))
  local selections = vim.list_extend(vim.deepcopy(event.selections or {}), found)
  local lines = block_text.quoted(vim.trim(text))

  for _, label in ipairs(selections) do
    lines[#lines + 1] = '> + ' .. label
  end

  self:_add(Block.KIND.prompt, lines, {
    steered = event.steered,
    selections = #selections > 0 and #selections or nil,
    event = i,
  })
end

function TurnBuilder:on_message(event, i)
  self:_stream(Block.KIND.message, event.text, i, event.parent, event.message_id)
end

function TurnBuilder:on_thought(event, i)
  self:_stream(Block.KIND.thought, event.text, i, event.parent)
end

function TurnBuilder:on_tool_call(event)
  local opts = self.opts
  local state = self.states[event.id] or { input = {} }
  local name, argument = tool_label.label(state, event.id, opts.dir)
  local lines = { '-> ' .. name .. (argument and ' ' .. argument or '') }
  local category = state.category or Block.CATEGORY.other
  local folds = {}
  local lang, ansi

  if opts.outputs ~= false and state.output and state.output ~= '' then
    if TurnBuilder.BODY[category] or state.status == Block.STATUS.failed then
      local body

      body, ansi = output_style.strip(block_text.output(state.output))
      lang = not ansi and state.status ~= Block.STATUS.failed and output_style.language(state.input.command, body)
        or nil

      vim.list_extend(lines, fences.wrap(body, output_style.label(lang, TurnBuilder.SURFACE[category])))

      if category ~= Block.CATEGORY.execute and #body > settings:get('preview_lines') + 1 then
        folds[1] = { 2 + settings:get('preview_lines'), #lines - 2 }
      end
    end
  end

  self.turn.tools = self.turn.tools + 1

  local tool = self:_add(Block.KIND.tool, lines, {
    id = event.id,
    name = name,
    argument = argument,
    status = state.status,
    category = category,
    locations = state.locations,
    output = state.output,
    lang = lang,
    ansi = ansi,
    started = self.times[state.started],
    finished = state.finished and self.times[state.finished] or nil,
    folds = folds,
    parent = state.parent,
    depth = state.parent and 1 or nil,
  })
  local tools = self.tools

  if state.parent and tools[state.parent] then tools[state.parent].nested = (tools[state.parent].nested or 0) + 1 end

  tools[event.id] = tool
  self:_show_diffs(event.id, tool)
end

function TurnBuilder:on_tool_update(event)
  if event.status == Block.STATUS.failed and not self.tools[event.id] then
    self:_add(Block.KIND.note, block_text.note('failed', compact.line(event.title or event.name or event.id, 200)), {
      label = 'failed',
    })
  end

  self:_show_diffs(event.id, self.tools[event.id])
end

function TurnBuilder:on_plan(event, i)
  if not self.plans[i] then return end

  local lines, statuses = block_text.plan(event.entries)

  self:_add(Block.KIND.plan, lines, { statuses = statuses })
end

function TurnBuilder:on_permission(event)
  if event.allowed then return end

  local tool = event.id and self.tools[event.id]
  local outcome = event.cancelled and 'cancelled' or 'refused'

  if tool then
    tool.denied = outcome
  elseif not event.cancelled then
    self:_add(Block.KIND.note, block_text.note('refused', block_text.tool(event.tool, self.opts.dir)), {
      label = 'refused',
    })
  end
end

TurnBuilder.ELICITATION_NOTES = {
  [elicitation.ACTION.decline] = Block.NOTE.declined,
  [elicitation.ACTION.cancel] = Block.NOTE.cancelled,
}

function TurnBuilder:on_elicitation(event)
  local label, detail = TurnBuilder.ELICITATION_NOTES[event.action], event.message

  if event.completed then
    label = Block.NOTE.done
  elseif not label and event.mode == elicitation.MODE.url then
    label = Block.NOTE.opened
  elseif not label then
    local answers = {}

    for _, answer in ipairs(event.answers or {}) do
      answers[#answers + 1] = answer.label .. ' → ' .. answer.value
    end

    label = Block.NOTE.answered
    if #answers > 0 then detail = detail .. ' ' .. table.concat(answers, '; ') end
  end

  self:_add(Block.KIND.note, block_text.note(label, compact.line(detail, 400)), { label = label })
end

function TurnBuilder:on_stop(event, i)
  local times, turn = self.times, self.turn
  local duration = turn.started and times[i] and times[i] - turn.started or nil
  local reason = event.reason or 'end_turn'

  turn.stopped = true
  self:_add(Block.KIND.stop, { '*' .. reason .. '*' }, { reason = reason, duration = duration, tools = turn.tools })
end

function TurnBuilder:on_error(event)
  self:_add(Block.KIND.note, block_text.note('error', event.message), { label = 'error' })
end

TurnBuilder.HANDLERS = {
  prompt = TurnBuilder.on_prompt,
  user = TurnBuilder.on_prompt,
  message = TurnBuilder.on_message,
  thought = TurnBuilder.on_thought,
  tool_call = TurnBuilder.on_tool_call,
  tool_update = TurnBuilder.on_tool_update,
  plan = TurnBuilder.on_plan,
  permission = TurnBuilder.on_permission,
  elicitation = TurnBuilder.on_elicitation,
  stop = TurnBuilder.on_stop,
  error = TurnBuilder.on_error,
}

function TurnBuilder:_finish()
  local times, opts, list = self.times, self.opts, self.list
  local ended = self.turn.stopped or not self.last_turn

  for i, block in ipairs(list) do
    local tail = self.last_turn and i == #list

    if ended and block.kind == Block.KIND.tool and not TurnBuilder.FINISHED[block.status] then
      block.interrupted = true
    end

    if block.text then
      if block.kind == Block.KIND.thought then
        block.lines = block_text.quoted(block.text, '> [!thought]')
        block.folds = { { 1, #block.lines - 1 } }
        block.started = times[block.first_event]
        block.finished = times[block.last_event + 1]
        block.live = tail and opts.running or false
      else
        block.lines = block_text.split(block.text)

        local open = not tail and fences.open(block.lines)

        if open then block.lines[#block.lines + 1] = open end
      end

      block.text = nil

      if block.depth then
        block.lines = block_text.indented(block.lines)
        block.indented = true
      end
    else
      block.lines = block_text.flatten(block.lines)
    end
  end

  return list
end

function TurnBuilder:build()
  self:_collect_states():_collect_plans()

  local history, handlers = self.history, TurnBuilder.HANDLERS

  for i = self.from, self.to do
    local event = history[i]
    local handler = handlers[event.kind]

    if handler then handler(self, event, i) end
  end

  return self:_finish()
end

return TurnBuilder
