local fs = require('core.fs')
local process = require('core.process')
local symbols = require('harness.symbols')

local walkthrough_scope = {}

walkthrough_scope.MAX_COMMITS = 200
walkthrough_scope.MAX_LABELLED = 60
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

local function count(text)
  return text == '' and 1 or tonumber(text)
end

function walkthrough_scope.parse_diff(text)
  local files, deleted, file, hunk, old_path = {}, {}, nil, nil, nil
  local old_left, new_left = 0, 0

  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    if hunk and (old_left > 0 or new_left > 0) then
      local mark = line:sub(1, 1)

      if mark == '-' then
        old_left = old_left - 1
        hunk.lines[#hunk.lines + 1] = line
      elseif mark == '+' then
        new_left = new_left - 1
        hunk.lines[#hunk.lines + 1] = line
      elseif mark == ' ' then
        old_left, new_left = old_left - 1, new_left - 1
      end
    elseif line:match('^diff %-%-git ') then
      file, hunk, old_path = nil, nil, nil
    elseif line:match('^%-%-%- ') then
      old_path = line:match('^%-%-%- a/(.+)$')
    elseif line:match('^%+%+%+ /dev/null') then
      deleted[#deleted + 1] = old_path
      file = nil
    elseif line:match('^%+%+%+ b/') then
      local path = line:match('^%+%+%+ b/(.+)$')

      file = { path = path, old_path = old_path, hunks = {} }
      files[#files + 1] = file
    else
      local removed, start, added = line:match('^@@ %-%d+,?(%d*) %+(%d+),?(%d*) @@')

      if start and file then
        local first = tonumber(start)

        old_left, new_left = count(removed), count(added)
        hunk = {
          first = math.max(first, 1),
          last = math.max(first + new_left - 1, first, 1),
          added = new_left,
          removed = old_left,
          lines = {},
        }
        file.hunks[#file.hunks + 1] = hunk
      elseif start then
        hunk = { lines = {} }
        old_left, new_left = count(removed), count(added)
      end
    end
  end

  return files, deleted
end

local function label(root, rev, file)
  local lines = walkthrough_scope.show(root, rev, file.path)

  if not lines then return end

  local list = symbols.parse(lines, file.path)

  for _, hunk in ipairs(file.hunks) do
    local symbol = symbols.enclosing(list, hunk.first, hunk.last) or symbols.enclosing(list, hunk.first, hunk.first)

    hunk.symbol = symbol and symbol.name or nil
  end
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

  local diff, diff_err =
    git(root, { 'diff', '--no-color', '--no-ext-diff', '--find-renames', '-U0', base_sha, head_sha })

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

  local files, deleted = walkthrough_scope.parse_diff(diff)
  local by_id, next_id = {}, 0

  for index, file in ipairs(files) do
    file.absolute = fs.normalize(fs.joinpath(root, file.path))

    if index <= walkthrough_scope.MAX_LABELLED then label(root, head_sha, file) end

    for _, hunk in ipairs(file.hunks) do
      next_id = next_id + 1
      hunk.id = 'h' .. next_id
      by_id[hunk.id] = { file = file, hunk = hunk }
    end
  end

  local current = git(root, { 'rev-parse', 'HEAD' })

  return {
    root = root,
    base = base_sha,
    head = head_sha,
    commits = commits,
    files = files,
    deleted = deleted,
    by_id = by_id,
    checked_out = current ~= nil and vim.trim(current) == head_sha,
  }
end

function walkthrough_scope.base_path(scope, absolute)
  for _, file in ipairs(scope and scope.files or {}) do
    if file.absolute == absolute then return file.old_path end
  end

  return fs.make_relative(scope and scope.root, absolute)
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
        missing[#missing + 1] =
          { id = hunk.id, path = file.path, absolute = file.absolute, first = hunk.first, last = hunk.last }
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
