local Object = require('core.Object')
local EVENT = require('harness.types.events').KIND

local PromptHistory = Object:extend()

PromptHistory.LIMIT = 200

function PromptHistory.collect(session, sent)
  local all = vim.list_extend({}, sent or {})

  for _, event in ipairs(session.history) do
    if event.kind == EVENT.prompt and not event.steered then all[#all + 1] = event.text end
  end

  local seen, newest = {}, {}

  for i = #all, 1, -1 do
    local text = all[i]

    if type(text) == 'string' and vim.trim(text) ~= '' and not seen[text] then
      seen[text] = true
      newest[#newest + 1] = text
    end
  end

  local entries = {}

  for i = math.min(#newest, PromptHistory.LIMIT), 1, -1 do
    entries[#entries + 1] = newest[i]
  end

  return entries
end

function PromptHistory:constructor(entries)
  return { entries = entries or {}, index = nil, stash = nil }
end

function PromptHistory:browsing()
  return self.index ~= nil
end

function PromptHistory:reset()
  self.index, self.stash = nil, nil

  return self
end

function PromptHistory:older(current)
  if #self.entries == 0 then return nil end

  if not self.index then
    self.stash = current
    self.index = #self.entries + 1
  end

  if self.index <= 1 then return nil end

  self.index = self.index - 1

  return self.entries[self.index]
end

function PromptHistory:newer()
  if not self.index then return nil end

  self.index = self.index + 1

  if self.index > #self.entries then
    local stash = self.stash

    self:reset()

    return stash or ''
  end

  return self.entries[self.index]
end

return PromptHistory
