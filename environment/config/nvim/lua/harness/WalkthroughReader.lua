local lazy = require('core.lazy')

local fs = lazy('core.fs')
local hub = lazy('harness.hub')
local Object = require('core.Object')
local settings = lazy('harness.settings')
local events = lazy('harness.types.events')
local walkthrough_scope = lazy('harness.walkthrough_scope')

local WalkthroughReader = Object:extend()

WalkthroughReader.SYSTEM = table.concat({
  'You write the notes of a code walkthrough the user reads in their editor, one step at a time, beside the code.',
  'Each message gives you a step and its code. Reply with only the note: two to five sentences of markdown on what',
  'this code does in the walkthrough and why it matters, how it connects to the steps around it, and for a change',
  'what to watch for. Do not restate the code line by line, add headings or greet. Read other files only when the',
  'step cannot be understood without them.',
}, ' ')

local function ranges(step)
  return step.ranges and #step.ranges > 0 and step.ranges or { step }
end

local function fence(out, header, lang, lines)
  out[#out + 1] = header
  out[#out + 1] = '```' .. (lang or '')
  vim.list_extend(out, lines)
  out[#out + 1] = '```'
end

function WalkthroughReader.prompt(walkthrough, index, read, opts)
  opts = opts or {}

  local steps = walkthrough.steps
  local step = steps[index]
  local root = walkthrough.root or opts.dir
  local budget = settings.walkthrough:get('reader_lines')
  local out = {}

  local function where(path)
    return root and fs.make_relative(root, path) or path
  end

  if opts.brief then
    out[#out + 1] = 'Walkthrough: ' .. walkthrough.title

    if walkthrough.summary then out[#out + 1] = walkthrough.summary end

    out[#out + 1] = 'Steps:'

    for at, each in ipairs(steps) do
      out[#out + 1] = string.format('%d. %s', at, each.title or fs.basename(each.path))
    end

    out[#out + 1] = ''
  end

  out[#out + 1] = string.format(
    'Step %d/%d: %s%s',
    index,
    #steps,
    step.title or fs.basename(step.path),
    step.supporting and ' (supporting: tests, docs or wiring)' or ''
  )

  local hunks = walkthrough.scope and walkthrough_scope.covered(walkthrough.scope, step) or {}

  if #hunks > 0 then
    for _, hunk in ipairs(hunks) do
      if budget <= 0 then break end

      local lines = vim.list_slice(hunk.lines, 1, budget)

      budget = budget - #lines
      fence(out, string.format('%s:%d-%d', hunk.path, hunk.first, hunk.last), 'diff', lines)
    end

    return table.concat(out, '\n')
  end

  for _, range in ipairs(ranges(step)) do
    if budget <= 0 then break end

    local lines = read(range.path) or {}
    local last = math.min(range.end_line, #lines, range.line + budget - 1)
    local slice = vim.list_slice(lines, range.line, last)

    budget = budget - #slice
    fence(
      out,
      string.format('%s:%d-%d', where(range.path), range.line, last),
      fs.detect_filetype(range.path) or '',
      slice
    )
  end

  return table.concat(out, '\n')
end

function WalkthroughReader:constructor(walkthrough, opts)
  opts = opts or {}

  return {
    walkthrough = walkthrough,
    dir = opts.dir,
    agent = opts.agent,
    session = nil,
    starting = false,
    busy = false,
    briefed = false,
    closed = false,
    queue = {},
    requested = {},
    waiting = {},
  }
end

function WalkthroughReader:_read(path)
  local walkthrough = self.walkthrough

  return walkthrough_scope.lines(walkthrough.root, walkthrough.rev, path)
end

function WalkthroughReader:_index_of(step)
  for index, each in ipairs(self.walkthrough.steps) do
    if each == step then return index end
  end

  return nil
end

function WalkthroughReader:note(index, done)
  local step = self.walkthrough.steps[index]

  if self.closed or not step then return end

  if step.note ~= '' then
    if done then done(step.note) end
    return
  end

  if done then
    self.waiting[step] = self.waiting[step] or {}
    table.insert(self.waiting[step], done)
  end

  if self.requested[step] then
    if done then
      for at, queued in ipairs(self.queue) do
        if queued == step then
          table.remove(self.queue, at)
          table.insert(self.queue, 1, step)
          break
        end
      end
    end

    return
  end

  self.requested[step] = true
  table.insert(self.queue, done and 1 or #self.queue + 1, step)
  self:_pump()
end

function WalkthroughReader:_finish(step, note, err)
  self.requested[step] = nil

  if note then step.note = note end

  local waiting = self.waiting[step] or {}

  self.waiting[step] = nil

  for _, done in ipairs(waiting) do
    done(note, err)
  end
end

function WalkthroughReader:_fail_all(err)
  local queued = self.queue

  self.queue = {}

  for _, step in ipairs(queued) do
    self:_finish(step, nil, err)
  end
end

function WalkthroughReader:_start()
  if self.starting then return end

  self.starting = true

  local model = settings.walkthrough:get('model') or {}

  hub
    .start({
      dir = self.dir,
      agent = self.agent,
      hidden = true,
      system = WalkthroughReader.SYSTEM,
      model = model[self.agent],
    })
    :on_complete(function(err, session)
      self.starting = false

      if self.closed then
        if session then hub.discard(session) end
        return
      end

      if err or not session then return self:_fail_all(tostring(err or 'the reader did not start')) end

      self.session = session
      self:_pump()
    end)
end

local function reply_since(history, mark)
  local text = {}

  for index = mark + 1, #history do
    local event = history[index]

    if event.kind == events.KIND.message and not event.parent then text[#text + 1] = event.text end
  end

  return vim.trim(table.concat(text, ''))
end

function WalkthroughReader:_pump()
  if self.closed or self.busy or #self.queue == 0 then return end
  if not self.session then return self:_start() end

  local step = table.remove(self.queue, 1)
  local index = self:_index_of(step)

  if not index then
    self.requested[step] = nil
    return self:_pump()
  end

  local text = WalkthroughReader.prompt(self.walkthrough, index, function(path)
    return self:_read(path)
  end, { brief = not self.briefed, dir = self.dir })
  local mark = #self.session.history
  local task, err = self.session:prompt(text)

  if not task then
    self:_finish(step, nil, err)
    return self:_pump()
  end

  self.busy, self.briefed = true, true

  task:on_complete(function(prompt_err)
    self.busy = false

    if self.closed then return end

    local note = not prompt_err and reply_since(self.session.history, mark) or ''

    self:_finish(step, note ~= '' and note or nil, prompt_err and tostring(prompt_err) or nil)
    self:_pump()
  end)
end

function WalkthroughReader:close()
  if self.closed then return end

  self.closed = true
  self.queue, self.waiting, self.requested = {}, {}, {}

  if self.session then
    hub.discard(self.session)
    self.session = nil
  end
end

return WalkthroughReader
