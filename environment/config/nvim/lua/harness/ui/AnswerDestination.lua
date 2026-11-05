local lazy = require('core.lazy')

local asks = lazy('harness.ui.asks')
local PromptDestination = require('harness.ui.PromptDestination')

local AnswerDestination = PromptDestination:extend()

AnswerDestination.GONE = 'the question was already answered or withdrawn'

AnswerDestination.EMPTY = 'write an answer, or close to go back to the choices'

function AnswerDestination:constructor(session, store, display, prompt)
  local fields = PromptDestination.constructor(self, session, store, display)

  fields.prompt = prompt

  return fields
end

function AnswerDestination:answers()
  return self.prompt
end

function AnswerDestination:target()
  local prompt = self.prompt

  return prompt and prompt:is_open() and prompt:writing() and prompt or nil
end

function AnswerDestination:label()
  local target = self:target()

  return target and target:writing_label()
end

function AnswerDestination:keeps_draft()
  return false
end

function AnswerDestination:history_hint()
  return self:label() == nil
end

function AnswerDestination:placeholder()
  return 'write your answer'
end

function AnswerDestination:hints(add, shown)
  if self:label() then return add(shown.send, 'answer') end

  PromptDestination.hints(self, add, shown)
end

function AnswerDestination:closing()
  local target = self:target()

  if target then
    target:stop_writing()
    asks.changed(self.session)
  end
end

function AnswerDestination:submit(text)
  local target = self:target()

  if not target then return false, AnswerDestination.GONE end
  if text == '' then return false, AnswerDestination.EMPTY end

  local ok, why = target:submit_text(text)

  if not ok then return false, why end

  asks.changed(self.session)

  return true, 'answered'
end

return AnswerDestination
