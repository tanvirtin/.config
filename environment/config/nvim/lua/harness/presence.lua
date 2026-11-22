local lazy = require('core.lazy')

local Lens = lazy('ui.Lens')
local compact = lazy('compact')
local Timer = lazy('core.Timer')
local guides = lazy('ui.guides')
local Object = lazy('core.Object')
local console = lazy('core.console')
local glyph = lazy('ui.design.glyph')
local tokens = lazy('ui.design.motion')
local Window = lazy('core.editor.Window')
local events = lazy('harness.types.events')
local theme = lazy('harness.transcript.theme')

local Presence = Object:extend()

Presence.LINGER_MS = 8000

Presence.BAR_WIDTH = 10

Presence.ACTIVITY_WIDTH = 46

local active = {}

function Presence.head(step, width)
  local span = 2 * (width - 1)
  local at = step % span

  return at < width and at or span - at
end

function Presence.bar(step, width)
  if theme.reduced() then return { { string.rep('▱', width), 'UiMuted' } } end

  local head = Presence.head(step, width)
  local from, to = math.max(head - 1, 0), math.min(head + 1, width - 1)

  return {
    { string.rep('▱', from), 'UiMuted' },
    { string.rep('▰', to - from + 1), 'UiAccent' },
    { string.rep('▱', width - 1 - to), 'UiMuted' },
  }
end

local function signature(chunks)
  local parts = {}

  for _, chunk in ipairs(chunks) do
    local group = chunk[2]

    parts[#parts + 1] = chunk[1]
    parts[#parts + 1] = type(group) == 'table' and table.concat(group, '+') or (group or '')
  end

  return table.concat(parts, '\0')
end

function Presence.count(count, word)
  return count .. ' ' .. word .. (count == 1 and '' or 's')
end

function Presence.notes(count)
  return glyph.SEPARATOR .. Presence.count(count, 'note') .. ', ]g'
end

function Presence.tail(text, width)
  local last

  for line in (text or ''):gmatch('[^\n]+') do
    if line:match('%S') then last = line end
  end

  if not last then return '' end

  last = vim.trim((last:gsub('%s+', ' ')))

  local chars = {}

  for char in last:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
    chars[#chars + 1] = char
  end

  if #chars <= width then return last end

  return '…' .. table.concat(chars, '', #chars - width + 2)
end

function Presence.detail(event)
  local location = (event.locations or {})[1]
  local input = event.input or {}

  if location and location.path then return compact.path(location.path) end

  return input.command or input.pattern or input.query or input.url or input.file_path or input.path or ''
end

function Presence.sentence(reply)
  local text = vim.trim(reply or '')

  return text:match('^(.-[%.%?!])%s') or text:match('^([^\n]+)') or ''
end

function Presence:constructor(session, request)
  return {
    session = session,
    request = request,
    phase = 'working',
    activity = 'starting',
    steps = {},
    step_count = 0,
    reply = '',
    stream = '',
    stream_group = 'UiMuted',
    failure = nil,
    started = Timer.now(),
    finished = nil,
    frame = 0,
    drawn = nil,
    lens = nil,
    held = nil,
    unsubscribe = nil,
    ticker = Timer(),
  }
end

function Presence:start()
  local window = Window.find(self.request.win)

  if not window then return nil end

  self.lens = Lens(window, self.request.line):reserve(1)
  self.held = self.lens:follow('presence.' .. self.session.key, nil, function()
    Timer.schedule(function()
      self:dispose()
    end)
  end)
  self.unsubscribe = self.session:subscribe(function(event)
    self:observe(event)
  end)

  if not self:safely(Timer.now()) then return nil end

  self.ticker:every(tokens.STEP_MS, function()
    self:tick()
  end)

  return self
end

function Presence:safely(now)
  local ok, err = pcall(self.draw, self, now)

  if ok then return true end

  self:dispose()
  console.warn('Harness: the progress line stopped: ' .. tostring(err))

  return false
end

function Presence:finish(phase)
  if self.phase ~= 'working' then return end

  self.phase = phase
  self.finished = Timer.now()
  self:safely(self.finished)
end

function Presence:observe(event)
  local K = events.KIND
  local kind = event.kind

  if kind == K.tool_call or kind == K.tool_update then
    if event.id and not self.steps[event.id] then
      self.steps[event.id] = true
      self.step_count = self.step_count + 1
    end

    if event.title and event.title ~= '' then self.activity = event.title end

    local detail = Presence.detail(event)

    if detail ~= '' then
      self.stream, self.stream_group = detail, 'UiPath'
    end
  elseif kind == K.thought then
    self.activity = 'thinking'
    self.stream, self.stream_group = event.text or '', 'UiThought'
  elseif kind == K.message then
    self.activity = 'writing the answer'
    self.reply = event.text or self.reply
    self.stream, self.stream_group = self.reply, 'UiNormal'
  elseif kind == K.stop then
    if #self.session.queue == 0 then self:finish(event.reason == 'cancelled' and 'stopped' or 'done') end
  elseif kind == K.error then
    self.failure = event.message
    self:finish('failed')
  elseif kind == K.prompt and self.phase ~= 'working' then
    self:dispose()
  end
end

function Presence:chunks(now)
  local session = self.session
  local line = { { ' ' } }
  local elapsed = theme.duration((self.finished or now) - self.started)
  local clock = self.frame * tokens.STEP_MS

  local function add(text, group)
    line[#line + 1] = { text, group }
  end

  if self.phase == 'working' then
    local request = (session:waiting() or {})[1]

    if request then
      vim.list_extend(line, theme.working(clock, self.started, 'wait', session.key))
      add(' waiting for you: ', 'UiWarn')
      add(compact.line(request.title or request.tool or 'a tool', Presence.ACTIVITY_WIDTH), 'UiPromptBar')
      add(glyph.SEPARATOR .. '<leader>aw', 'UiAccent')

      return line
    end

    vim.list_extend(line, theme.working(clock, self.started, 'work', session.key))
    add(' ')
    vim.list_extend(line, Presence.bar(self.frame, Presence.BAR_WIDTH))
    add(' ' .. compact.line(self.activity, Presence.ACTIVITY_WIDTH), 'UiMuted')

    if self.step_count > 0 then add(glyph.SEPARATOR .. Presence.count(self.step_count, 'step'), 'UiMuted') end
    if elapsed then add(glyph.SEPARATOR .. elapsed, 'UiMuted') end

    local notes = guides.count(session.key)

    if notes > 0 then add(Presence.notes(notes), 'UiAccent') end

    return line
  end

  if self.phase == 'done' then
    local notes = guides.count(session.key)

    add(glyph.STATUS.done .. ' done', 'UiAdded')

    if notes > 0 then add(Presence.notes(notes), 'UiAccent') end
    if elapsed then add(glyph.SEPARATOR .. elapsed, 'UiMuted') end

    add(glyph.SEPARATOR .. '<leader>as chat', 'UiMuted')

    return line
  end

  if self.phase == 'failed' then
    add(glyph.STATUS.failed .. ' failed', 'UiError')
    add(glyph.SEPARATOR .. '<leader>as chat', 'UiMuted')

    return line
  end

  add(glyph.STATUS.pending .. ' stopped', 'UiMuted')

  return line
end

function Presence:width()
  return math.max(20, self.lens.window:get_text_width() - 4)
end

function Presence:body()
  local width = self:width()

  if self.phase == 'done' then
    local summary = Presence.sentence(self.reply)

    return { { '   ' }, { compact.line(summary ~= '' and summary or 'no answer', width), 'UiNormal' } }
  end

  if self.phase == 'failed' then
    return { { '   ' }, { compact.line(self.failure or 'no reason given', width), 'UiError' } }
  end

  return { { '   ' }, { Presence.tail(self.stream, width), self.phase == 'working' and self.stream_group or 'UiMuted' } }
end

function Presence:draw(now)
  if not self.lens then return false end

  local head, body = self:chunks(now), self:body()
  local drawn = signature(head) .. '\1' .. signature(body)

  if drawn == self.drawn then return false end

  self.drawn = drawn
  self.lens:header(Lens.band(head), { Lens.band(body) })

  return true
end

function Presence:tick()
  local now = Timer.now()

  if self.finished and now - self.finished > Presence.LINGER_MS then return self:dispose() end

  self.frame = self.frame + 1
  self:safely(now)
end

function Presence:dispose()
  if active[self.session.key] == self then active[self.session.key] = nil end

  self.ticker:stop()

  if self.unsubscribe then self.unsubscribe() end
  if self.held then self.held.dispose() end

  self.unsubscribe, self.held, self.lens = nil, nil, nil
end

local presence = {}

presence.Presence = Presence

function presence.show(session, request)
  presence.clear(session.key)

  local shown = Presence(session, request):start()

  if shown then active[session.key] = shown end

  return shown
end

function presence.get(key)
  return active[key]
end

function presence.clear(key)
  if active[key] then active[key]:dispose() end
end

function presence.clear_all()
  for _, key in ipairs(vim.tbl_keys(active)) do
    presence.clear(key)
  end
end

return presence
