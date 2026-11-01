local lazy = require('core.lazy')

local hub = lazy('harness.hub')
local tools = lazy('nvim_mcp.tools')
local schema = lazy('nvim_mcp.schema')
local tour_type = lazy('harness.types.tour')
local tour_store = lazy('harness.tour_store')

local tour_tools = {}

local function dir_of(ctx)
  local caller = ctx.caller and hub.session(ctx.caller)

  return caller and caller.dir or hub.dir()
end

local function tour_start(args, ctx)
  local tour, err = tour_type.parse(args, dir_of(ctx))

  if not tour then error(err, 0) end

  tour_store.start(tour, { session = ctx.caller })

  return { title = tour.title, steps = #tour.steps }
end

local function tour_update(args, ctx)
  local current = tour_store.current()

  if not current then error('no tour is running; start one with tour_start', 0) end

  local update = { mode = args.mode, note = args.note, steps = {} }

  if args.mode == 'note' and (args.note == nil or args.note == '') then error('mode note needs a note', 0) end

  if args.mode ~= 'note' and #(args.steps or {}) == 0 then error('mode ' .. args.mode .. ' needs steps', 0) end

  for index, fields in ipairs(args.steps or {}) do
    local step, err = tour_type.step(fields, dir_of(ctx))

    if not step then error(string.format('step %d: %s', index, err), 0) end

    update.steps[index] = step
  end

  local ok, why = tour_store.update(update)

  if not ok then error(why, 0) end

  return { title = current.title, steps = #current.steps }
end

local STEP = schema.model({
  { name = 'path', type = schema.str({ description = 'File, relative to the project or absolute.' }) },
  { name = 'line', type = schema.int({ description = 'First line, 1-based.' }) },
  { name = 'end_line', type = schema.int({ description = 'Last line of the range.' }), optional = true },
  { name = 'title', type = schema.str({ description = 'A few words.' }), optional = true },
  { name = 'note', type = schema.str({ description = 'Markdown shown beside the code.' }), optional = true },
})

function tour_tools.definitions()
  return {
    {
      name = 'tour_update',
      risk = 'read',
      summary = 'Change the tour the user is following, after they ask about a step. mode "insert" adds steps right after the step they are on and moves them to the first new one; "replace" swaps every step after the current one for new steps; "note" rewrites the current step\'s note with a better explanation and keeps them where they are. Prefer "note" for a quick clarification, "insert" for a deeper look, "replace" when the tour should go somewhere else. Steps are as in tour_start.',
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
    {
      name = 'tour_start',
      risk = 'read',
      summary = 'Walk the user through code in their editor: opens each step\'s file at the lines it is about, highlights them and shows your note beside them, and the user steps through with keys. Use it to explain how something works, to show where a change was made and why, or to review code. Give a short title, an optional summary, and 3 to 15 steps in the order you want them read. Each step names a file (relative to the project), the line or range it is about, a short title and a note in markdown: say what the code does and why it matters here, not what the line says. Check the paths and line numbers by reading the files first.',
      params = {
        { name = 'title', type = schema.str({ description = 'What the tour is about, in a few words.' }) },
        {
          name = 'summary',
          type = schema.str({ description = 'One or two sentences of orientation.' }),
          optional = true,
        },
        {
          name = 'steps',
          type = schema.list(schema.model({
            { name = 'path', type = schema.str({ description = 'File, relative to the project or absolute.' }) },
            { name = 'line', type = schema.int({ description = 'First line, 1-based.' }) },
            { name = 'end_line', type = schema.int({ description = 'Last line of the range.' }), optional = true },
            { name = 'title', type = schema.str({ description = 'A few words.' }), optional = true },
            { name = 'note', type = schema.str({ description = 'Markdown shown beside the code.' }), optional = true },
          })),
        },
      },
      fn = tour_start,
    },
  }
end

function tour_tools.register()
  tools.register('tour', tour_tools.definitions())
end

return tour_tools
