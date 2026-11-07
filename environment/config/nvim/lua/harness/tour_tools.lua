local lazy = require('core.lazy')

local fs = lazy('core.fs')
local hub = lazy('harness.hub')
local tools = lazy('nvim_mcp.tools')
local schema = lazy('nvim_mcp.schema')
local tour_type = lazy('harness.types.tour')
local tour_scope = lazy('harness.tour_scope')
local tour_store = lazy('harness.tour_store')

local tour_tools = {}

tour_tools.MAX_FILES = 80
tour_tools.MAX_COMMITS = 30
tour_tools.MAX_UNCOVERED = 30

local function dir_of(ctx)
  local caller = ctx.caller and hub.session(ctx.caller)

  return caller and caller.dir or hub.dir()
end

local function fail(message)
  error(message, 0)
end

local function session_of(ctx)
  local caller = ctx and ctx.caller

  if type(caller) ~= 'string' or caller == '' then fail('a tour belongs to a session; ask for one in your session') end

  return caller
end

local function snapshot(dir, rev)
  if not rev then return {} end

  local sha, err = tour_scope.resolve(dir, rev)

  if not sha then fail(err) end

  local head = tour_scope.git(dir, { 'rev-parse', 'HEAD' })

  if head and vim.trim(head) == sha then return {} end

  local root, root_err = tour_scope.root(dir)

  if not root then fail(root_err) end

  return {
    rev = sha,
    root = root,
    check = function(path)
      return tour_scope.exists_at(root, sha, fs.make_relative(root, path))
    end,
  }
end

local function scope_for(session, sha)
  local scope = tour_store.scope(session)

  if not scope or (sha or (scope.checked_out and scope.head)) ~= scope.head then return nil end

  return scope
end

local function uncovered(session, tour, sha)
  local scope = scope_for(session, sha)

  if not scope then return nil end

  local missing = tour_scope.uncovered(scope, tour.steps)
  local shown = {}

  tour.uncovered = missing

  for index = 1, math.min(#missing, tour_tools.MAX_UNCOVERED) do
    shown[index] = { path = missing[index].path, first = missing[index].first, last = missing[index].last }
  end

  return {
    uncovered = #missing > 0 and shown or nil,
    uncovered_count = #missing > 0 and #missing or nil,
    note = #missing > 0 and string.format(
      '%d changed hunk%s no step covers; add them with tour_update.',
      #missing,
      #missing == 1 and '' or 's'
    ) or 'Every changed hunk in the range is covered.',
  }
end

local function with(result, extra)
  return extra and vim.tbl_extend('force', result, extra) or result
end

local function short(sha)
  return sha:sub(1, 7)
end

local function tour_scope_tool(args, ctx)
  local scope, err = tour_scope.compute(dir_of(ctx), args.base, args.head)

  if not scope then fail(err) end

  tour_store.set_scope(session_of(ctx), scope)

  local files = {}

  for index = 1, math.min(#scope.files, tour_tools.MAX_FILES) do
    files[index] = { path = scope.files[index].path, hunks = scope.files[index].hunks }
  end

  local commits = {}

  for index = 1, math.min(#scope.commits, tour_tools.MAX_COMMITS) do
    commits[index] = { sha = short(scope.commits[index].sha), subject = scope.commits[index].subject }
  end

  return {
    base = short(scope.base),
    head = short(scope.head),
    rev = scope.head,
    checked_out = scope.checked_out,
    commits = commits,
    commit_count = #scope.commits,
    files = files,
    file_count = #scope.files,
    next = 'Read the changed code, then call tour_start with rev set to the rev above and steps in the order a reviewer should read them, covering every hunk: one step per purpose, its hunks as ranges, the core first and tests, docs and wiring marked supporting.',
  }
end

local function tour_start(args, ctx)
  local session = session_of(ctx)
  local dir = dir_of(ctx)
  local opts = snapshot(dir, args.rev)
  local sha = args.rev and tour_scope.resolve(dir, args.rev) or nil
  local scope = scope_for(session, sha)

  if scope then
    opts.base = scope.base
    opts.root = opts.root or scope.root
  end

  local tour, err = tour_type.parse(args, dir, opts)

  if not tour then fail(err) end

  local coverage = uncovered(session, tour, sha)

  tour_store.start(session, tour)

  return with({ title = tour.title, steps = #tour.steps }, coverage)
end

local function tour_update(args, ctx)
  local session = session_of(ctx)
  local current = tour_store.current(session)

  if not current then fail('no tour is running; start one with tour_start') end

  local update = { mode = args.mode, note = args.note, steps = {} }

  if args.mode == 'note' and (args.note == nil or args.note == '') then fail('mode note needs a note') end
  if args.mode ~= 'note' and #(args.steps or {}) == 0 then fail('mode ' .. args.mode .. ' needs steps') end

  local check = current.rev
      and function(path)
        return tour_scope.exists_at(current.root, current.rev, fs.make_relative(current.root, path))
      end
    or nil

  for index, fields in ipairs(args.steps or {}) do
    local step, err = tour_type.step(fields, dir_of(ctx), check)

    if not step then fail(string.format('step %d: %s', index, err)) end

    update.steps[index] = step
  end

  local ok, why = tour_store.update(session, update)

  if not ok then fail(why) end

  return with({ title = current.title, steps = #current.steps }, uncovered(session, current, current.rev))
end

local RANGE = schema.model({
  { name = 'path', type = schema.str({ description = 'File, relative to the project or absolute.' }) },
  { name = 'line', type = schema.int({ description = 'First line, 1-based.' }) },
  { name = 'end_line', type = schema.int({ description = 'Last line of the range.' }), optional = true },
})

local STEP = schema.model({
  {
    name = 'path',
    type = schema.str({ description = 'File, relative to the project or absolute (or give ranges).' }),
    optional = true,
  },
  { name = 'line', type = schema.int({ description = 'First line, 1-based.' }), optional = true },
  { name = 'end_line', type = schema.int({ description = 'Last line of the range.' }), optional = true },
  {
    name = 'ranges',
    type = schema.list(RANGE, {
      description = 'Several ranges, across files if need be, that one explanation covers (a section). The reader steps through them in this order. Use instead of path and line.',
    }),
    optional = true,
  },
  { name = 'title', type = schema.str({ description = 'A few words.' }), optional = true },
  { name = 'note', type = schema.str({ description = 'Markdown shown beside the code.' }), optional = true },
  {
    name = 'supporting',
    type = schema.bool({
      description = 'True for lower-signal changes (tests, docs, generated code, renames, wiring); they are shown after the core steps.',
    }),
    optional = true,
  },
})

function tour_tools.definitions()
  return {
    {
      name = 'tour_scope',
      risk = 'read',
      summary = 'Use first when the user asks you to review or walk through a range of commits or a branch ("review abc123..def456", "what does this branch change"). Works out, from git and without guessing, which commits and which hunks of which files changed between base and head, and remembers it so that tour_start can tell you what you have not covered. Both must be commits that exist in this repository. base defaults to where the branch left main; head defaults to HEAD. Returns the commits, the files with the line ranges of their hunks at head, and the rev to give tour_start.',
      params = {
        {
          name = 'base',
          type = schema.str({ description = 'The commit the range starts after (a sha, branch or tag).' }),
          optional = true,
        },
        {
          name = 'head',
          type = schema.str({ description = 'The commit the range ends at (default HEAD).' }),
          optional = true,
        },
      },
      fn = tour_scope_tool,
    },
    {
      name = 'tour_start',
      risk = 'read',
      summary = 'Walk the user through code in their editor, when they ask to be shown, taken through, or told how something works, or to review changes: opens each step\'s file at the lines it is about, highlights them and shows your note beside them, and the user steps through with keys (they can ask you about a step, and you can change the tour with tour_update). Give a short title, an optional summary, and 3 to 15 steps in the order you want them read: for a review, the order a reviewer should read the change in (entry point, core logic, callers, tests), with what to watch for; for a feature, the order the code runs in. Each step names a file (relative to the project), the line or range it is about, a short title and a note in markdown: say what the code does and why it matters here, not what the line says. Check paths and line numbers by reading the files first. After tour_scope, pass its rev: the steps are then lines of that commit, shown read-only if it is not checked out, each shown as a diff against the base, and the reply lists changed hunks no step covers. For a review, make each step a section: put the hunks that serve one purpose, across files if need be, under one explanation with ranges, and say why that part of the change exists and what it affects. Put the core of the change first and mark tests, docs, generated code, renames and wiring as supporting.',
      params = {
        { name = 'title', type = schema.str({ description = 'What the tour is about, in a few words.' }) },
        {
          name = 'summary',
          type = schema.str({ description = 'One or two sentences of orientation.' }),
          optional = true,
        },
        {
          name = 'rev',
          type = schema.str({
            description = 'The commit the line numbers refer to (from tour_scope). Omit for the files as they are on disk.',
          }),
          optional = true,
        },
        { name = 'steps', type = schema.list(STEP) },
      },
      fn = tour_start,
    },
    {
      name = 'tour_update',
      risk = 'read',
      summary = 'Change the tour the user is following, after they ask about a step. mode "insert" adds steps right after the step they are on and moves them to the first new one; "replace" swaps every step after the current one for new steps; "note" rewrites the current step\'s note with a better explanation and keeps them where they are. When a question opens something the step does not cover, prefer "insert" and give the answer its own steps; use "note" only for a sentence or two, and "replace" when the tour should go somewhere else. Steps are as in tour_start, and the reply lists changed hunks still uncovered when a range is being reviewed.',
      params = {
        { name = 'mode', type = schema.literal({ 'insert', 'replace', 'note' }) },
        { name = 'steps', type = schema.list(STEP), optional = true },
        {
          name = 'note',
          type = schema.str({ description = 'The new note for the current step (mode note).' }),
          optional = true,
        },
      },
      fn = tour_update,
    },
  }
end

function tour_tools.register()
  tools.register('tour', tour_tools.definitions())
end

return tour_tools
