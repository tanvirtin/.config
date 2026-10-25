local fs = require('core.fs')
local vgit = require('harness.vgit')
local Object = require('core.Object')
local edit_text = require('harness.edits.edit_text')
local settings = require('harness.settings.transcript')
local SyntaxAnnotator = require('ui.annotators.SyntaxAnnotator')

local Edit = Object:extend()

Edit.KIND = { applied = 'applied', pending = 'pending', created = 'created', snippet = 'snippet' }

Edit.REASON = { changed = 'changed since', unknown = 'no record of what it replaced' }

Edit.SOURCE = { remove = 'old', add = 'new', context = 'new' }

local annotator = SyntaxAnnotator()

function Edit.resolve(diff, file, opts)
  local old, new = edit_text.trimmed(diff.old), edit_text.trimmed(diff.new)
  local text = table.concat(file or {}, '\n')

  if opts and opts.failed then
    return { kind = Edit.KIND.snippet, old_lines = edit_text.lines_of(old), new_lines = edit_text.lines_of(new) }
  end

  if new ~= '' then
    local at = edit_text.locate(text, new)

    if at then
      if old == '' and at == 1 and #new >= #text then
        return { kind = Edit.KIND.created, old_lines = {}, new_lines = edit_text.lines_of(text) }
      end

      return {
        kind = Edit.KIND.applied,
        old_lines = edit_text.lines_of(edit_text.replace(text, at, #new, old)),
        new_lines = file,
      }
    end
  end

  if old ~= '' then
    local at = edit_text.locate(text, old)

    if at then
      return {
        kind = Edit.KIND.pending,
        old_lines = file,
        new_lines = edit_text.lines_of(edit_text.replace(text, at, #old, new)),
      }
    end
  end

  return { kind = Edit.KIND.snippet, old_lines = edit_text.lines_of(old), new_lines = edit_text.lines_of(new) }
end

function Edit.undo(text, diff)
  local old, new = edit_text.trimmed(diff.old), edit_text.trimmed(diff.new)

  if new == '' then return nil, Edit.REASON.unknown end
  if old == '' and text == new then return '' end

  local at = edit_text.locate(text, new)

  if not at then return nil, Edit.REASON.changed end

  return edit_text.replace(text, at, #new, old)
end

function Edit:constructor(diff, file, opts)
  local resolved = Edit.resolve(diff, file, opts)

  return {
    diff = diff,
    resolved = resolved,
    whole = resolved.kind ~= Edit.KIND.snippet,
    file = { filename = diff.path, old_lines = resolved.old_lines, new_lines = resolved.new_lines },
    _patch = nil,
    _stat = nil,
    _syntax = nil,
    _text = nil,
  }
end

function Edit:patch(width)
  local layout = vgit.layout(settings:get('diff_layout'))
  local overflow = settings:get('diff_overflow')

  if (width and width ~= self._width) or layout ~= self._layout or overflow ~= self._overflow then
    self._width = width or self._width
    self._layout = layout
    self._overflow = overflow
    self._patch = nil
    self._syntax = nil
  end

  local opts = {
    header = false,
    context = settings:get('diff_context'),
    layout = layout,
    overflow = settings:get('diff_overflow'),
    width = self._width,
    numbers = self.whole,
  }

  self._patch = self._patch or vgit.patch(self.file, opts)

  return self._patch
end

function Edit:stat()
  if self._patch then return self._patch.stat end

  self._stat = self._stat or vgit.stat(self.file)

  return self._stat
end

function Edit:_highlights_by_line(lines, filetype)
  local map = {}

  for _, hl in ipairs(annotator:annotate(lines, filetype)) do
    local line = hl.row + 1

    map[line] = map[line] or {}
    map[line][#map[line] + 1] = hl
  end

  return map
end

function Edit:_split_syntax(patch, file, filetype)
  local maps, out = {}, {}

  local function highlights(source, lnum)
    maps[source] = maps[source]
      or self:_highlights_by_line(source == 'old' and file.old_lines or file.new_lines, filetype)

    return maps[source][lnum] or {}
  end

  for i, row in ipairs(patch.rows) do
    for _, side in ipairs({ { row.old_code, 'old', row.old_lnum }, { row.new_code, 'new', row.new_lnum } }) do
      local offset, source, lnum = side[1], side[2], side[3]

      if offset and lnum then
        local line = (source == 'old' and file.old_lines or file.new_lines)[lnum] or ''

        for _, hl in ipairs(highlights(source, lnum)) do
          out[#out + 1] = {
            row = i - 1,
            col_start = offset + hl.col_start,
            col_end = offset + (hl.col_end >= 0 and hl.col_end or #line),
            hl_group = hl.hl_group,
          }
        end
      end
    end
  end

  return out
end

function Edit:syntax()
  if self._syntax then return self._syntax end

  local patch, file = self:patch(), self.file
  local filetype = file.filename and fs.detect_filetype(file.filename) or ''

  if patch.layout == 'split' then
    self._syntax = self:_split_syntax(patch, file, filetype)

    return self._syntax
  end

  local maps = {}
  local out = {}

  for i, row in ipairs(patch.rows) do
    local source = Edit.SOURCE[row.kind]
    local lnum = source == 'old' and row.old_lnum or row.new_lnum

    if source and lnum then
      maps[source] = maps[source]
        or self:_highlights_by_line(source == 'old' and file.old_lines or file.new_lines, filetype)

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

return Edit
