local event = require('core.event')
local fs = require('core.fs')
local lazy = require('core.lazy')

local api = lazy('vgit.api')

local vgit = {}

vgit.COMMAND = 'VGit'

function vgit.patch(file, opts)
  return api.patch({ file }, vim.tbl_extend('force', { syntax = false }, opts or {}))
end

function vgit.stat(file)
  return api.diff(file.old_lines, file.new_lines).stat or { added = 0, removed = 0 }
end

function vgit.patch_text(file, opts)
  return api.patch_text({ file }, opts)
end

function vgit.show(files, opts)
  opts = opts or {}

  local relative = vim.tbl_map(function(file)
    return vim.tbl_extend('force', file, { filename = file.filename and fs.relative_filename(file.filename) })
  end, files)
  local ok, shown = pcall(api.show, { files = relative, layout = opts.layout, keymaps = opts.keymaps })

  if not ok then return false, tostring(shown) end
  if not shown then return false, 'nothing to show' end

  return true
end

function vgit.git_diff(path)
  if not event.has_command(vgit.COMMAND) then return false, 'vgit is not available' end

  local ok, err = pcall(event.run_command, vgit.COMMAND, { 'diff', '--', path })

  if not ok then return false, tostring(err) end

  return true
end

return vgit
