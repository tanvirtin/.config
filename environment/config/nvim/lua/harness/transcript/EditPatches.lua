local fs = require('core.fs')
local vgit = require('harness.vgit')
local Object = require('core.Object')
local Block = require('harness.transcript.Block')
local EditLog = require('harness.transcript.EditLog')
local settings = require('harness.settings.transcript')
local EditResolver = require('harness.transcript.EditResolver')
local SyntaxAnnotator = require('ui.annotators.SyntaxAnnotator')

local EditPatches = Object:extend()

local Edit = Object:extend()

local annotator = SyntaxAnnotator()

local SOURCE = { remove = 'old', add = 'new', context = 'new' }

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

local function by_line(lines, filetype)
  local map = {}

  for _, hl in ipairs(annotator:annotate(lines, filetype)) do
    local line = hl.row + 1

    map[line] = map[line] or {}
    map[line][#map[line] + 1] = hl
  end

  return map
end

function Edit:syntax()
  if self._syntax then return self._syntax end

  local patch, file = self:patch(), self.file
  local filetype = file.filename and fs.detect_filetype(file.filename) or ''
  local maps = {}
  local out = {}

  for i, row in ipairs(patch.rows) do
    local source = SOURCE[row.kind]
    local lnum = source == 'old' and row.old_lnum or row.new_lnum

    if source and lnum then
      maps[source] = maps[source] or by_line(source == 'old' and file.old_lines or file.new_lines, filetype)

      local length = #(patch.lines[i] or '')

      for _, hl in ipairs(maps[source][lnum] or {}) do
        out[#out + 1] = {
          row = i - 1,
          col_start = hl.col_start,
          col_end = hl.col_end >= 0 and hl.col_end or length,
          hl_group = hl.hl_group,
        }
      end
    end
  end

  self._syntax = out

  return out
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

function EditPatches:reset()
  self.entries = {}
  self.primed = nil
end

function EditPatches:prime(history)
  if self.primed == #history then return end

  self.primed = #history

  local files = {}
  local log = EditLog.edits(history)

  for t = #log, 1, -1 do
    local tool = log[t]

    for index = #tool.diffs, 1, -1 do
      local diff = tool.diffs[index]
      local path = diff.path

      if path then
        local key = tool.id .. ':' .. index
        local entry = self.entries[key]

        if not (entry and entry.final) then
          local file = files[path] or self.file_lines(path) or {}

          entry = { edit = Edit(diff, EditResolver.resolve(diff, file)), final = true, failed = false }
          self.entries[key] = entry
        end

        files[path] = entry.edit.whole and entry.edit.resolved.old_lines or nil
      end
    end
  end
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
