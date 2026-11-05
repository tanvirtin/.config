local lazy = require('core.lazy')

local hub = lazy('harness.hub')
local Buffer = lazy('core.Buffer')
local Object = lazy('core.Object')
local tools = lazy('nvim_mcp.tools')
local context = lazy('harness.context')
local notice = lazy('harness.ui.notice')
local settings = lazy('harness.settings')

local PromptDestination = Object:extend()

function PromptDestination.warn(message)
  notice.warn(message)
end

function PromptDestination:constructor(session, store, display)
  return { session = session, store = store, display = display }
end

function PromptDestination:answers()
  return nil
end

function PromptDestination:label()
  return nil
end

function PromptDestination:keeps_draft()
  return true
end

function PromptDestination:history_hint()
  return true
end

function PromptDestination:placeholder()
  return 'ask anything · ' .. settings.keymaps:get('composer').slash .. ' for commands'
end

function PromptDestination:hints(add, shown)
  local session, keys = self.session, shown.keys

  if session:running() then
    add(shown.send, 'queue')

    if session:can('steer') then add(keys.steer, 'steer') end
    if not shown.inserting then add(keys.interrupt, 'interrupt') end
  else
    add(shown.send, 'send')
  end
end

function PromptDestination:closing() end

function PromptDestination:submit(text, message, opts)
  local session, source, store = self.session, message.source, self.store

  if text == '' then return true end
  if session.state == 'closed' then return false, 'this session has ended; your text is kept' end

  local where = Buffer.exists(source.buf) and context.capture_buffer(source.buf) or nil

  local problems
  where, problems =
    context.attach_tokens(where, text, session.dir, { max_lines = settings.composer:get('reference_lines') })

  if #problems > 0 then PromptDestination.warn(table.concat(problems, '; ')) end

  local sent, err = hub.send(session, text, where, opts)

  if err then return false, tostring(err) end

  store:clear(session.key)
  store:remember(text)

  if source.buf then tools.set_focus(source.win, source.buf) end

  if sent.task then
    sent.task:on_complete(function(turn_err)
      if turn_err and not (self.display and self.display.showing(session)) then
        PromptDestination.warn(tostring(turn_err))
      end
    end)
  end

  return true, sent.how
end

return PromptDestination
