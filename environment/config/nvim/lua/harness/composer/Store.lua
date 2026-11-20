local lazy = require('core.lazy')

local Object = lazy('core.Object')

local ComposerStore = Object:extend()

ComposerStore.LIMIT = 200

function ComposerStore:constructor()
  return { drafts = {}, sent = {} }
end

function ComposerStore:draft(key)
  return self.drafts[key]
end

function ComposerStore:set_draft(key, lines)
  self.drafts[key] = lines

  return self
end

function ComposerStore:remember(text)
  self.sent[#self.sent + 1] = text

  if #self.sent > ComposerStore.LIMIT then table.remove(self.sent, 1) end

  return self
end

function ComposerStore:clear(key)
  self.drafts[key] = nil

  return self
end

return ComposerStore
