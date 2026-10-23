local lazy = require('core.lazy')

local Object = lazy('core.Object')

local ComposerStore = Object:extend()

function ComposerStore:constructor()
  return { drafts = {}, attached = {} }
end

function ComposerStore:draft(key)
  return self.drafts[key]
end

function ComposerStore:set_draft(key, lines)
  self.drafts[key] = lines

  return self
end

function ComposerStore:attachments(key)
  return self.attached[key] or {}
end

function ComposerStore:has_attachments(key)
  return self.attached[key] ~= nil
end

function ComposerStore:attach(key, selection)
  self.attached[key] = self.attached[key] or {}
  self.attached[key][#self.attached[key] + 1] = selection

  return self
end

function ComposerStore:detach(key)
  local list = self.attached[key]

  if not list then return self end

  list[#list] = nil

  if #list == 0 then self.attached[key] = nil end

  return self
end

function ComposerStore:clear(key)
  self.drafts[key] = nil
  self.attached[key] = nil

  return self
end

return ComposerStore
