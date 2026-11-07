local lazy = require('core.lazy')

local fs = lazy('core.fs')
local hub = lazy('harness.hub')
local Window = lazy('core.Window')
local Object = require('core.Object')
local notice = lazy('harness.ui.notice')
local settings = lazy('harness.settings')
local display = lazy('harness.ui.display')
local composer = lazy('harness.ui.composer')
local Block = lazy('harness.transcript.Block')
local walkthrough_scope = lazy('harness.walkthrough_scope')
local WalkthroughReader = lazy('harness.WalkthroughReader')

local SideChats = Object:extend()

SideChats.SYSTEM = table.concat({
  'You answer the user\'s questions about one step of a code walkthrough they are reading in their editor;',
  'the step, its code and the plan it belongs to follow. Answer briefly and concretely, naming code as',
  'path:line. When a picture would help, draw a small diagram in a fenced text block, boxes and arrows.',
  'Read other files when the answer needs them. Never change any file.',
}, ' ')

function SideChats:constructor(walkthrough, opts)
  opts = opts or {}

  return {
    walkthrough = walkthrough,
    dir = opts.dir,
    agent = opts.agent,
    on_keep = opts.on_keep,
    on_share = opts.on_share,
    owner_view = opts.owner_view,
    chats = {},
    closed = false,
  }
end

function SideChats:context(index)
  local walkthrough = self.walkthrough
  local step = walkthrough.steps[index]
  local packet = WalkthroughReader.prompt(walkthrough, index, function(path)
    return walkthrough_scope.lines(walkthrough.root, walkthrough.rev, path)
  end, { brief = true, dir = self.dir })

  if step.note ~= '' then packet = packet .. '\n\nThe note beside the code:\n' .. step.note end

  return SideChats.SYSTEM .. '\n\n' .. packet
end

function SideChats:title(index)
  local step = self.walkthrough.steps[index]

  return string.format('Step %d: %s', index, step.title or fs.basename(step.path))
end

function SideChats:open(index)
  local step = self.walkthrough.steps[index]

  if self.closed or not step then return false end

  local chat = self.chats[step]

  if chat and chat.session then return self:_show(chat) end
  if chat then return true end

  chat = { step = step }
  self.chats[step] = chat

  local model = settings.walkthrough:get('model') or {}

  notice.info('Opening a side chat on ' .. self:title(index))

  hub
    .start({
      dir = self.dir,
      agent = self.agent,
      hidden = true,
      title = self:title(index),
      system = self:context(index),
      model = model[self.agent],
    })
    :on_complete(function(err, session)
      if self.closed then
        if session then hub.discard(session) end
        return
      end

      if err or not session then
        self.chats[step] = nil
        notice.warn('The side chat did not start: ' .. tostring(err))
        return
      end

      chat.session = session
      chat.unsubscribe = session:subscribe(function(update)
        composer.on_session_event(session, update)
      end)
      self:_show(chat)
    end)

  return true
end

function SideChats:_place(session)
  display.open(session, { background = true })

  local view = display.view_of(session)

  if view:is_visible() then return view, view:windows()[1] end

  local owner = self.owner_view and self.owner_view()
  local beside = owner and owner:windows()[1]
  local window = beside and beside:split_below(view.buffer) or Window.get_current():split_right(view.buffer)

  return view, window
end

function SideChats:_show(chat)
  local view, window = self:_place(chat.session)

  view:show_in(window)
  display.set_current(view)

  if not chat.bound then
    chat.bound = true

    local keys = settings.keymaps:get('side_chat')

    view:map(keys.keep, function()
      self:keep(chat, view)
    end, 'Keep this answer in the walkthrough step\'s note')
    view:map(keys.share, function()
      self:share(chat, view)
    end, 'Take this answer to the main session')
  end

  composer.open(chat.session, { display = display, insert = true })

  return true
end

local function text_of(history, block)
  local parts = {}

  for index = block.first_event or 1, block.last_event or 0 do
    local event = history[index]

    if event and event.kind == block.kind and event.text then parts[#parts + 1] = event.text end
  end

  local text = vim.trim(table.concat(parts, ''))

  return text ~= '' and text or nil
end

function SideChats.answer_at(view, row)
  local blocks = view.document.blocks
  local block = view.document:block_at(row)
  local from = block and block.index or #blocks

  for index = math.min(from, #blocks), 1, -1 do
    local candidate = blocks[index]

    if candidate and candidate.kind == Block.KIND.message and not candidate.depth then
      local text = text_of(view.session.history, candidate)

      if text then return text end
    end
  end

  return nil
end

function SideChats:_answer(view)
  local window = Window.get_current()

  if window:get_buffer().bufnr ~= view.bufnr then window = view:windows()[1] end

  local text = SideChats.answer_at(view, window and window:get_cursor()[1] - 1 or math.huge)

  if not text then notice.info('No answer here yet') end

  return text
end

function SideChats:keep(chat, view)
  local text = self:_answer(view)

  if text and self.on_keep then self.on_keep(chat.step, text) end
end

function SideChats:share(chat, view)
  local text = self:_answer(view)

  if text and self.on_share then self.on_share(chat.step, text) end
end

function SideChats:close()
  if self.closed then return end

  self.closed = true

  for _, chat in pairs(self.chats) do
    if chat.session then
      if chat.unsubscribe then chat.unsubscribe() end

      composer.forget(chat.session)
      display.forget(chat.session)
      hub.discard(chat.session)
    end
  end

  self.chats = {}
end

return SideChats
