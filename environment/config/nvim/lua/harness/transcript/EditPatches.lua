local Block = require('harness.transcript.Block')
local EditResolver = require('harness.transcript.EditResolver')
local Object = require('core.Object')
local settings = require('harness.settings.transcript')
local vgit = require('harness.vgit')

local EditPatches = Object:extend()

local Edit = Object:extend()

function Edit:constructor(diff, resolved)
  return {
    resolved = resolved,
    whole = EditResolver.whole(resolved),
    file = { filename = diff.path, old_lines = resolved.old_lines, new_lines = resolved.new_lines },
  }
end

function Edit:patch()
  self._patch = self._patch or vgit.patch(self.file, { header = false, context = settings:get('diff_context') })

  return self._patch
end

function Edit:stat()
  if self._patch then return self._patch.stat end

  self._stat = self._stat or vgit.stat(self.file)

  return self._stat
end

function Edit:text()
  self._text = self._text or vgit.patch_text(self.file, { header = false, context = settings:get('diff_context') })

  return self._text
end

local function none()
  return {}
end

function EditPatches:constructor(file_lines)
  return { file_lines = file_lines or none, entries = {} }
end

function EditPatches:get(diff, key, final, failed)
  local entry = self.entries[key]

  if entry and entry.final then return entry.edit end

  local file = self.file_lines(diff.path) or {}
  local fingerprint = table.concat(file, '\n')

  if
    entry
    and entry.fingerprint == fingerprint
    and entry.failed == failed
    and entry.old == diff.old
    and entry.new == diff.new
  then
    entry.final = final
    return entry.edit
  end

  local edit = Edit(diff, EditResolver.resolve(diff, file, { failed = failed }))

  self.entries[key] = {
    edit = edit,
    final = final,
    failed = failed,
    fingerprint = fingerprint,
    old = diff.old,
    new = diff.new,
  }

  return edit
end

local owned = setmetatable({}, { __mode = 'k' })

function EditPatches.of(owner, file_lines)
  owned[owner] = owned[owner] or EditPatches(file_lines)

  return owned[owner]
end

function EditPatches.line_at(block, row)
  local entry = block.patch and block.whole and block.patch.rows[row - block.start - Block.DIFF_HEADER + 1]

  return entry and (entry.new_lnum or entry.old_lnum) or nil
end

return EditPatches
