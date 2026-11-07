local fs = require('core.fs')
local process = require('core.process')

local walkthrough_scope = {}

walkthrough_scope.MAX_COMMITS = 200
walkthrough_scope.BASES = { 'origin/main', 'origin/master', 'main', 'master' }

local function git(dir, args)
  local ok, result = pcall(function()
    return process.system(vim.list_extend({ 'git', '-C', dir }, args), { text = true }):wait()
  end)

  if not ok then return nil, 'git is not available' end

  if result.code ~= 0 then
    local message = vim.trim(result.stderr or '')

    return nil, message ~= '' and message or ('git ' .. args[1] .. ' failed')
  end

  return result.stdout
end

walkthrough_scope.git = git

function walkthrough_scope.root(dir)
  local out, err = git(dir, { 'rev-parse', '--show-toplevel' })

  if not out then return nil, err end

  return fs.normalize(vim.trim(out))
end

function walkthrough_scope.resolve(dir, ref)
  local out = git(dir, { 'rev-parse', '--verify', '--quiet', ref .. '^{commit}' })

  if not out then return nil, string.format('no commit "%s" in this repository', ref) end

  return vim.trim(out)
end

function walkthrough_scope.default_base(dir, head)
  for _, name in ipairs(walkthrough_scope.BASES) do
    if walkthrough_scope.resolve(dir, name) then
      local out = git(dir, { 'merge-base', name, head })

      if out then return vim.trim(out), name end
    end
  end

  return nil, 'no main or master branch to compare with; give a base commit'
end

function walkthrough_scope.parse_diff(text)
  local files, file = {}, nil

  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    local path = line:match('^%+%+%+ b/(.+)$')

    if path then
      file = { path = path, hunks = {} }
      files[#files + 1] = file
    elseif line:match('^%+%+%+ /dev/null') then
      file = { deleted = true, hunks = {} }
    elseif line:match('^%-%-%- /dev/null') and file == nil then
      file = nil
    end

    local old_count, start, count = line:match('^@@ %-%d+,?(%d*) %+(%d+),?(%d*) @@')

    if start and file and not file.deleted then
      local first = tonumber(start)
      local added = count == '' and 1 or tonumber(count)

      file.hunks[#file.hunks + 1] = {
        first = math.max(first, 1),
        last = math.max(first + added - 1, first, 1),
        added = added,
        removed = old_count == '' and 1 or tonumber(old_count),
      }
    end
  end

  return files
end

function walkthrough_scope.compute(dir, base, head)
  local root, err = walkthrough_scope.root(dir)

  if not root then return nil, err end

  local head_sha, head_err = walkthrough_scope.resolve(dir, head or 'HEAD')

  if not head_sha then return nil, head_err end

  local base_sha, base_err

  if base then
    base_sha, base_err = walkthrough_scope.resolve(dir, base)
  else
    base_sha, base_err = walkthrough_scope.default_base(dir, head_sha)
  end

  if not base_sha then return nil, base_err end

  local diff, diff_err = git(root, { 'diff', '--no-color', '--no-ext-diff', '--no-renames', '-U0', base_sha, head_sha })

  if not diff then return nil, diff_err end

  local log = git(root, {
    'log',
    '--format=%H%x09%s',
    '-n',
    tostring(walkthrough_scope.MAX_COMMITS),
    base_sha .. '..' .. head_sha,
  }) or ''
  local commits = {}

  for _, line in ipairs(vim.split(log, '\n', { plain = true, trimempty = true })) do
    local sha, subject = line:match('^(%x+)\t(.*)$')

    if sha then commits[#commits + 1] = { sha = sha, subject = subject } end
  end

  local files = walkthrough_scope.parse_diff(diff)

  for _, file in ipairs(files) do
    file.absolute = fs.normalize(fs.joinpath(root, file.path))
  end

  local current = git(root, { 'rev-parse', 'HEAD' })

  return {
    root = root,
    base = base_sha,
    head = head_sha,
    commits = commits,
    files = files,
    checked_out = current ~= nil and vim.trim(current) == head_sha,
  }
end

local function overlaps(range, hunk)
  return range.line <= hunk.last and range.end_line >= hunk.first
end

local function covers(step, file, hunk)
  for _, range in ipairs(step.ranges or { step }) do
    if range.path == file.absolute and overlaps(range, hunk) then return true end
  end

  return false
end

function walkthrough_scope.uncovered(scope, steps)
  local missing = {}

  for _, file in ipairs(scope.files) do
    for _, hunk in ipairs(file.hunks) do
      local covered = false

      for _, step in ipairs(steps) do
        covered = covered or covers(step, file, hunk)
      end

      if not covered then
        missing[#missing + 1] = { path = file.path, absolute = file.absolute, first = hunk.first, last = hunk.last }
      end
    end
  end

  return missing
end

function walkthrough_scope.exists_at(root, rev, path)
  return git(root, { 'cat-file', '-e', rev .. ':' .. path }) ~= nil
end

function walkthrough_scope.show(root, rev, path)
  local out = git(root, { 'show', rev .. ':' .. path })

  if not out then return nil end

  return vim.split(out, '\n', { plain = true })
end

return walkthrough_scope
