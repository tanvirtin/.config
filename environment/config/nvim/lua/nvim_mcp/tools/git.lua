local compact = require('compact')
local schema = require('nvim_mcp.schema')
local util = require('nvim_mcp.tools.util')

local function git(args, opts)
  opts = opts or {}

  local out = vim
    .system(vim.list_extend({ 'git' }, args), {
      cwd = opts.cwd or vim.fn.getcwd(),
      text = true,
      stdin = opts.stdin,
    })
    :wait()

  if out.code ~= 0 and not opts.allow_failure then
    util.fail('git ' .. table.concat(args, ' ') .. ': ' .. vim.trim(out.stderr ~= '' and out.stderr or out.stdout))
  end

  return out.stdout or ''
end

local function relative(path)
  return path and vim.fn.fnamemodify(path, ':.') or nil
end

local function git_status(_, ctx)
  local raw = git({ 'status', '--porcelain=v1', '--branch' })
  local lines = vim.split(vim.trim(raw), '\n', { plain = true })
  local branch = table.remove(lines, 1) or ''
  local rows = {}

  for _, line in ipairs(lines) do
    if line ~= '' then rows[#rows + 1] = { status = line:sub(1, 2):gsub(' ', '.'), path = line:sub(4) } end
  end

  local text = branch:gsub('^## ', 'branch ') .. '\n'

  if #rows == 0 then
    text = text .. 'clean'
  else
    text = text .. compact.rows(rows, { 'status', 'path' })
  end

  return compact.reply(ctx.caller, raw, text)
end

local function git_log(args, ctx)
  local cmd = { 'log', '--format=%h%x09%an%x09%ar%x09%s', '-n', tostring(args.limit or 20) }

  if args.rev then cmd[#cmd + 1] = args.rev end
  if args.path then vim.list_extend(cmd, { '--', relative(args.path) }) end

  local raw = git(cmd)
  local rows = {}

  for line in raw:gmatch('[^\n]+') do
    local hash, author, when, subject = line:match('^(.-)\t(.-)\t(.-)\t(.*)$')
    if hash then rows[#rows + 1] = { commit = hash, when = when, author = author, subject = subject } end
  end

  local text = #rows == 0 and 'no commits' or compact.rows(rows, { 'commit', 'when', 'author', 'subject' })

  return compact.reply(ctx.caller, raw, text)
end

local function git_diff(args, ctx)
  local base = { 'diff', '--no-color', '--no-ext-diff' }

  if args.staged then base[#base + 1] = '--cached' end
  if args.rev then base[#base + 1] = args.rev end

  local tail = args.path and { '--', relative(args.path) } or {}
  local stat = git(vim.list_extend(vim.list_extend(vim.deepcopy(base), { '--stat' }), tail))
  local patch = git(vim.list_extend(vim.list_extend(vim.deepcopy(base), { '--unified=2' }), tail))

  if vim.trim(patch) == '' then return compact.reply(ctx.caller, patch, 'no changes') end

  local text = vim.trim(stat) .. '\n\n' .. compact.text(patch, args.budget or compact.BUDGET)

  return compact.reply(ctx.caller, patch, text)
end

local function git_blame(args, ctx)
  local last = args.end_line or args.start_line
  local raw = git({
    'blame',
    '--date=short',
    '-L',
    string.format('%d,%d', args.start_line, last),
    '--',
    relative(args.path),
  })
  local rows = {}

  for line in raw:gmatch('[^\n]+') do
    local hash, author, date, lnum, text = line:match('^(%S+) .-%((.-)%s+(%d%d%d%d%-%d%d%-%d%d)%s+(%d+)%) ?(.*)$')

    if hash then
      rows[#rows + 1] =
        { line = lnum, commit = hash:gsub('^%^', ''):sub(1, 8), date = date, author = vim.trim(author), text = text }
    end
  end

  return compact.reply(ctx.caller, raw, compact.rows(rows, { 'line', 'commit', 'date', 'author', 'text' }))
end

local MUTATING = {
  stash = { add = true, pop = true, apply = true, drop = true, clear = true },
  worktree = { add = true, remove = true, switch = true, prune = true },
}

local VGIT_TIMEOUT_MS = 10000

local function vgit(command, args)
  local ok, api = pcall(require, 'vgit')
  local fargs = vim.list_extend({ command }, vim.deepcopy(args or {}))

  if not ok or type(api) ~= 'table' or type(api.run) ~= 'function' then
    if vim.fn.exists(':VGit') ~= 2 then util.fail('this needs vgit: neither require("vgit").run nor :VGit exists') end

    local ran, err = pcall(vim.api.nvim_cmd, { cmd = 'VGit', args = fargs }, {})

    if not ran then util.fail(string.format('VGit %s: %s', command, tostring(err))) end

    return
  end

  local task = api.run(fargs)
  local done, err = pcall(task.wait, task, VGIT_TIMEOUT_MS)

  if not done then util.fail(string.format('VGit %s: %s', command, tostring(err))) end
end

local function git_view(args, ctx)
  local first = args.args and args.args[1]

  if MUTATING[args.command] and first and MUTATING[args.command][first] then
    util.fail(string.format('git %s %s changes the repository; use git_run, which asks the user', args.command, first))
  end

  if args.command == 'branch' and first then
    util.fail('git_view branch takes no arguments; use git_run to switch branches')
  end

  vgit(args.command, args.args)

  return 'opened :VGit ' .. args.command .. '\n\n' .. util.screen(3000)
end

local function hunk_patch(path, line, cached)
  local cmd = { 'diff', '--no-color', '--no-ext-diff', '--unified=0' }

  if cached then cmd[#cmd + 1] = '--cached' end

  vim.list_extend(cmd, { '--', path })

  local header, hunk = {}, nil

  for _, text in ipairs(vim.split(git(cmd), '\n', { plain = true })) do
    local start, count = text:match('^@@ %-%d+,?%d* %+(%d+),?(%d*) @@')

    if start then
      if hunk then break end

      start, count = tonumber(start), count == '' and 1 or tonumber(count)

      local last = count == 0 and start + 1 or start + count - 1

      if line >= start and line <= last then hunk = { text } end
    elseif hunk then
      hunk[#hunk + 1] = text
    elseif #header < 4 and text ~= '' then
      header[#header + 1] = text
    end
  end

  if not hunk then return nil end

  while hunk[#hunk] == '' do
    hunk[#hunk] = nil
  end

  return table.concat(vim.list_extend(header, hunk), '\n') .. '\n'
end

local function file_of(args)
  local buf = util.resolve(args)
  local path = util.buf_path(buf)

  if not path then util.fail('bufnr ' .. buf .. ' has no file') end

  return buf, relative(path)
end

local function apply_hunk(args, cached, flags)
  local buf, path = file_of(args)

  if vim.bo[buf].modified then
    util.fail(path .. ' has unsaved changes; save it first (buffer_save) so git sees them')
  end

  local patch = hunk_patch(path, args.line, cached)

  if not patch then
    util.fail(
      string.format('no %s hunk at %s:%d (git_diff shows them)', cached and 'staged' or 'unstaged', path, args.line)
    )
  end

  git(vim.list_extend({ 'apply', '--unidiff-zero' }, flags), { stdin = patch })

  return buf
end

local function git_stage(args, ctx)
  if args.line then
    if args.unstage then
      apply_hunk(args, true, { '--cached', '--reverse' })
    else
      apply_hunk(args, false, { '--cached' })
    end

    return git_status({}, ctx)
  end

  local buf, path = file_of(args)

  git(args.unstage and { 'restore', '--staged', '--', path } or { 'add', '--', path })

  local note = vim.bo[buf].modified and 'note: the buffer has unsaved changes, which were not staged\n' or ''

  return note .. git_status({}, ctx)
end

local function git_discard(args, ctx)
  if args.line then
    apply_hunk(args, false, { '--reverse' })
  else
    local _, path = file_of(args)

    git({ 'restore', '--', path })
  end

  vim.cmd('checktime')

  return git_status({}, ctx)
end

local function git_run(args, ctx)
  vgit(args.command, args.args)

  return 'ran :VGit ' .. args.command .. ' ' .. table.concat(args.args or {}, ' ') .. '\n\n' .. util.screen(3000)
end

local VIEWS =
  schema.literal({ 'status', 'diff', 'blame', 'hunk', 'log', 'show', 'branch', 'stash', 'worktree', 'commit' })
local ARGS = {
  name = 'args',
  type = schema.list(schema.str()),
  optional = true,
}

return {
  {
    name = 'git_status',
    risk = 'read',
    summary = 'Branch, ahead/behind, and each changed file with its two-letter status: index then worktree, "." for unchanged (M. staged, .M unstaged, ?? untracked).',
    params = {},
    fn = git_status,
  },
  {
    name = 'git_log',
    risk = 'read',
    summary = 'Recent commits (hash, when, author, subject), of the repo or one path.',
    params = {
      { name = 'path', type = schema.str(), optional = true },
      { name = 'rev', type = schema.str(), optional = true },
      { name = 'limit', type = schema.int(), optional = true },
    },
    fn = git_log,
  },
  {
    name = 'git_diff',
    risk = 'read',
    summary = 'Diffstat, then the patch (2 lines of context, long patches shortened) of the worktree, the index (staged) or against rev, for the repo or one path.',
    params = {
      { name = 'path', type = schema.str(), optional = true },
      { name = 'staged', type = schema.bool(), optional = true },
      { name = 'rev', type = schema.str(), optional = true },
      { name = 'budget', type = schema.int(), optional = true },
    },
    fn = git_diff,
  },
  {
    name = 'git_blame',
    risk = 'read',
    summary = 'Who last changed each of lines start_line..end_line of a file: commit, date, author, text.',
    params = {
      { name = 'path', type = schema.str() },
      { name = 'start_line', type = schema.int() },
      { name = 'end_line', type = schema.int(), optional = true },
    },
    fn = git_blame,
  },
  {
    name = 'git_view',
    risk = 'write',
    summary = 'Open a vgit view for the user, with git-style args: status, diff ([rev] [--staged] [-- path]), blame, hunk, log ([path]), show <rev>, branch, stash, worktree, commit. Returns the screen; read and drive it with ui_screen and ui_keys.',
    params = { { name = 'command', type = VIEWS }, ARGS },
    fn = git_view,
  },
  {
    name = 'git_stage',
    risk = 'write',
    summary = 'Stage (or unstage) a whole file, or just the hunk at line. The file must be saved. Returns git status.',
    params = util.params(util.TARGET, {
      { name = 'line', type = schema.int(), optional = true },
      { name = 'unstage', type = schema.bool(), optional = true },
    }),
    fn = git_stage,
  },
  {
    name = 'git_discard',
    risk = 'exec',
    always_ask = true,
    summary = 'Throw away unstaged changes of a whole file, or of the hunk at line. Cannot be undone: the user is always asked.',
    params = util.params(util.TARGET, { { name = 'line', type = schema.int(), optional = true } }),
    fn = git_discard,
  },
  {
    name = 'git_run',
    risk = 'exec',
    always_ask = true,
    summary = 'Run any :VGit command, including ones that change the repository (stash pop/drop, worktree add/remove). The user is always asked.',
    params = { { name = 'command', type = schema.str() }, ARGS },
    fn = git_run,
  },
}
