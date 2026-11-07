local lazy = require('core.lazy')

local fs = lazy('core.fs')
local hub = lazy('harness.hub')
local tools = lazy('nvim_mcp.tools')
local schema = lazy('nvim_mcp.schema')
local walkthrough_type = lazy('harness.types.walkthrough')
local walkthrough_scope = lazy('harness.walkthrough_scope')
local walkthrough_store = lazy('harness.walkthrough_store')
local walkthrough_locate = lazy('harness.walkthrough_locate')

local walkthrough_tools = {}

walkthrough_tools.MAX_COMMITS = 30
walkthrough_tools.MAX_DIFF_LINES = 400
walkthrough_tools.MAX_HUNK_LINES = 40

local function dir_of(ctx)
  local caller = ctx.caller and hub.session(ctx.caller)

  return caller and caller.dir or hub.dir()
end

local function fail(message)
  error(message, 0)
end

local function session_of(ctx)
  local caller = ctx and ctx.caller

  if type(caller) ~= 'string' or caller == '' then
    fail('a walkthrough belongs to a session; ask for one in your session')
  end

  return caller
end

local function short(sha)
  return sha:sub(1, 7)
end

local function plural(count, word)
  return string.format('%d %s%s', count, word, count == 1 and '' or 's')
end

local function lines_of(first, last)
  return first == last and tostring(first) or string.format('%d-%d', first, last)
end

local function env_of(dir, scope, rev, root)
  local check = rev
      and function(path)
        return walkthrough_scope.exists_at(root, rev, fs.make_relative(root, path))
      end
    or nil

  return {
    dir = dir,
    scope = scope,
    check = check,
    read = function(path)
      if rev then return walkthrough_scope.show(root, rev, fs.make_relative(root, path)) end

      return (fs.read_file(path))
    end,
  }
end

local function steps_of(list, env)
  local steps = {}

  for index, fields in ipairs(list or {}) do
    local ranges, err = walkthrough_locate.ranges(fields.at, env)

    if not ranges then fail(string.format('step %d: %s', index, err)) end

    steps[index] = { ranges = ranges, title = fields.title, note = fields.note, supporting = fields.supporting }
  end

  return steps
end

function walkthrough_tools.runs(hunks)
  local out, first, last = {}, nil, nil

  local function flush()
    if first then out[#out + 1] = first == last and ('h' .. first) or string.format('h%d-h%d', first, last) end
  end

  for _, hunk in ipairs(hunks) do
    local number = tonumber(hunk.id:sub(2))

    if last and number == last + 1 then
      last = number
    else
      flush()
      first, last = number, number
    end
  end

  flush()

  return table.concat(out, ' ')
end

local function coverage(walkthrough)
  if not walkthrough.scope then return nil end

  local missing = walkthrough_scope.uncovered(walkthrough.scope, walkthrough.steps)

  walkthrough.uncovered = missing

  if #missing == 0 then return 'every hunk covered' end

  return string.format('uncovered: %s (add with walkthrough_update)', walkthrough_tools.runs(missing))
end

local function reply(verb, walkthrough)
  local head = string.format('%s "%s" · %s', verb, walkthrough.title, plural(#walkthrough.steps, 'step'))
  local covered = coverage(walkthrough)

  return covered and (head .. '\n' .. covered) or head
end

function walkthrough_tools.render_scope(scope, dir)
  local added, removed, count = 0, 0, 0

  for _, file in ipairs(scope.files) do
    for _, hunk in ipairs(file.hunks) do
      added, removed, count = added + hunk.added, removed + hunk.removed, count + 1
    end
  end

  local out = {
    string.format(
      '%s..%s%s · %s · %s · %s · +%d -%d',
      short(scope.base),
      short(scope.head),
      scope.checked_out and ' (checked out)' or '',
      plural(#scope.commits, 'commit'),
      plural(#scope.files, 'file'),
      plural(count, 'hunk'),
      added,
      removed
    ),
  }

  for index = 1, math.min(#scope.commits, walkthrough_tools.MAX_COMMITS) do
    out[#out + 1] = short(scope.commits[index].sha) .. ' ' .. scope.commits[index].subject
  end

  if #scope.commits > walkthrough_tools.MAX_COMMITS then
    out[#out + 1] = string.format('… %d more commits', #scope.commits - walkthrough_tools.MAX_COMMITS)
  end

  if #scope.deleted > 0 then out[#out + 1] = 'deleted: ' .. table.concat(scope.deleted, ' ') end

  local budget, cut = walkthrough_tools.MAX_DIFF_LINES, nil

  for _, file in ipairs(scope.files) do
    local path = fs.make_relative(dir, file.absolute)

    for _, hunk in ipairs(file.hunks) do
      out[#out + 1] = string.format(
        '%s %s:%s +%d -%d%s',
        hunk.id,
        path,
        lines_of(hunk.first, hunk.last),
        hunk.added,
        hunk.removed,
        hunk.symbol and (' · ' .. hunk.symbol) or ''
      )

      if budget > 0 then
        local shown = math.min(#hunk.lines, walkthrough_tools.MAX_HUNK_LINES, budget)

        vim.list_extend(out, hunk.lines, 1, shown)

        if shown < #hunk.lines then out[#out + 1] = string.format('… %d more lines', #hunk.lines - shown) end

        budget = budget - shown
      elseif not cut then
        cut = hunk.id
      end
    end
  end

  if cut then out[#out + 1] = string.format('diffs stop before %s; read the files for the rest', cut) end

  out[#out + 1] = 'next: walkthrough_start with steps naming these ids in at'

  return table.concat(out, '\n')
end

local function walkthrough_scope_tool(args, ctx)
  local dir = dir_of(ctx)
  local scope, err = walkthrough_scope.compute(dir, args.base, args.head)

  if not scope then fail(err) end

  walkthrough_store.set_scope(session_of(ctx), scope)

  return walkthrough_tools.render_scope(scope, dir)
end

local function walkthrough_start(args, ctx)
  local session = session_of(ctx)
  local dir = dir_of(ctx)
  local scope = walkthrough_store.scope(session)
  local rev = scope and not scope.checked_out and scope.head or nil
  local env = env_of(dir, scope, rev, scope and scope.root)

  local walkthrough, err = walkthrough_type.parse(
    {
      title = args.title,
      summary = args.summary,
      steps = steps_of(args.steps, env),
    },
    dir,
    {
      check = env.check,
      rev = rev,
      base = scope and scope.base,
      root = scope and scope.root,
      scope = scope,
    }
  )

  if not walkthrough then fail(err) end

  local text = reply('started', walkthrough)

  walkthrough_store.set_scope(session, nil)
  walkthrough_store.start(session, walkthrough)

  return text
end

local function walkthrough_update(args, ctx)
  local session = session_of(ctx)
  local current = walkthrough_store.current(session)

  if not current then fail('no walkthrough is running; start one with walkthrough_start') end

  if args.mode == 'note' and (args.note == nil or args.note == '') then fail('mode note needs a note') end
  if args.mode ~= 'note' and #(args.steps or {}) == 0 then fail('mode ' .. args.mode .. ' needs steps') end

  local dir = dir_of(ctx)
  local env = env_of(dir, current.scope, current.rev, current.root)
  local update = { mode = args.mode, note = args.note, steps = {} }

  for index, fields in ipairs(steps_of(args.steps, env)) do
    local step, err = walkthrough_type.step(fields, dir, env.check)

    if not step then fail(string.format('step %d: %s', index, err)) end

    update.steps[index] = step
  end

  local ok, why = walkthrough_store.update(session, update)

  if not ok then fail(why) end

  return reply('updated', current)
end

local STEP = schema.model({
  {
    name = 'at',
    type = schema.list(schema.str(), {
      description = 'What the step shows, in reading order: hunk ids (h3), path:Symbol, path:10-20 or path.',
    }),
  },
  { name = 'title', type = schema.str(), optional = true },
  { name = 'note', type = schema.str({ description = 'Markdown: why this code matters.' }), optional = true },
  { name = 'supporting', type = schema.bool({ description = 'Tests, docs, wiring: shown last.' }), optional = true },
})

function walkthrough_tools.definitions()
  return {
    {
      name = 'walkthrough_scope',
      risk = 'read',
      summary = 'First step of reviewing commits or a branch. Lists from git the commits and every changed hunk as an id (h1, h2…) with its lines, enclosing symbol and diff. base defaults to where the branch left main, head to HEAD.',
      params = {
        { name = 'base', type = schema.str(), optional = true },
        { name = 'head', type = schema.str(), optional = true },
      },
      fn = walkthrough_scope_tool,
    },
    {
      name = 'walkthrough_start',
      risk = 'read',
      summary = 'Walk the user through code in their editor, for a review (after walkthrough_scope) or to show how something works. Steps in reading order: for a review one step per purpose, core first; for a feature the order the code runs. Point at code by hunk id or symbol rather than reading files for line numbers.',
      params = {
        { name = 'title', type = schema.str() },
        { name = 'summary', type = schema.str({ description = 'One or two sentences.' }), optional = true },
        { name = 'steps', type = schema.list(STEP) },
      },
      fn = walkthrough_start,
    },
    {
      name = 'walkthrough_update',
      risk = 'read',
      summary = 'Change the running walkthrough after the user asks about a step. insert: new steps after the current one (prefer when an answer needs more than a sentence or two); replace: swap the steps after it; note: rewrite its note.',
      params = {
        { name = 'mode', type = schema.literal({ 'insert', 'replace', 'note' }) },
        { name = 'steps', type = schema.list(STEP), optional = true },
        { name = 'note', type = schema.str(), optional = true },
      },
      fn = walkthrough_update,
    },
  }
end

function walkthrough_tools.register()
  tools.register('walkthrough', walkthrough_tools.definitions())
end

return walkthrough_tools
