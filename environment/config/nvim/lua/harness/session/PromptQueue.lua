local lazy = require('core.lazy')

local Object = lazy('core.Object')
local async = lazy('harness.async')
local console = lazy('core.console')
local content = lazy('harness.types.content')
local events = lazy('harness.types.events')

local PromptQueue = Object:extend()

PromptQueue.STEER_FALLBACK = 'promptRequired'

function PromptQueue:constructor(session)
  return { session = session, items = {} }
end

function PromptQueue:_changed()
  self.session:_notify({ kind = events.NOTICE.queue })
end

function PromptQueue:queued()
  return vim.tbl_map(function(item)
    return item.text
  end, self.items)
end

function PromptQueue:size()
  return #self.items
end

function PromptQueue:take_all()
  local texts = self:queued()

  for i = #self.items, 1, -1 do
    self.items[i] = nil
  end

  if #texts > 0 then self:_changed() end

  return texts
end

function PromptQueue:drain()
  local session = self.session

  if not session:idle() or #self.items == 0 then return end

  local next = table.remove(self.items, 1)

  self:_changed()

  local ok, err = pcall(session.prompt, session, next.text, next.context, { shown = next.shown })

  if not ok then
    table.insert(self.items, 1, next)
    self:_changed()
    console.warn('Harness: could not send the queued message: ' .. tostring(err))
  end
end

function PromptQueue:enqueue(text, context, shown)
  self.items[#self.items + 1] = { text = text, context = context, shown = shown }
  self:_changed()

  if self.session:idle() then self:drain() end
end

function PromptQueue:steer(text, context)
  local session = self.session

  if not session:running() or not session:can('steer') then return self:enqueue(text, context) end

  session:_emit(events.prompt(text, { steered = true, selections = content.labels(context) }))

  local steered = session.history[#session.history]

  return async.run(function()
    local result = session.connection:steer(session.id, content.prompt(text, context))

    if type(result) == 'table' and result.outcome == PromptQueue.STEER_FALLBACK then
      steered.steered = nil
      session:_notify({ kind = events.NOTICE.reset })

      if session:running() then
        self.items[#self.items + 1] = { text = text, context = context, shown = true }
        self:_changed()
      else
        session:prompt(text, context, { shown = true })
      end
    end

    return result
  end)
end

return PromptQueue
