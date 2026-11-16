local fs = require('core.fs')
local Timer = require('core.Timer')
local Window = require('core.Window')
local buffers = require('core.buffers')
local editor = require('core.editor')
local compact = require('compact')
local catalog = require('ui.pixel.catalog')
local schema = require('nvim_mcp.schema')
local sources = require('sources')
local surfaces = require('surfaces')
local util = require('nvim_mcp.tools.util')

local WAIT_MS = 2000

local function component_help()
  return '\nComponents: pass components [{id, type, ...props}] and put {@id} in lines (alone on a line for tall ones). Pixel graphics where the terminal has them, text otherwise. Colours are style names (accent, muted, added, removed, warn, error, info). Change data later with ui_command <surface> set {id, props}.\n'
    .. table.concat(catalog.describe(), '\n')
    .. '\nExample: components [{id:"t",type:"ring",value:0.7},{id:"b",type:"badge",text:"passing",color:"added"}], lines ["{@t} [title]tests[/] {@b}"].'
end

local function surface(id)
  local found = surfaces.find(id)

  if not found then util.fail('no surface ' .. tostring(id) .. ' (ui_surfaces lists them)') end

  return found
end

local function source_opts(args)
  if args.source == 'lsp' then
    local buf = util.resolve(args)
    local line, col = args.line, args.col

    if not line and buf == util.focused_buf() then
      local cursor = util.focused_cursor()
      line, col = cursor[1], cursor[2] + 1
    end

    if not line then util.fail('pass line (and col): the cursor is only known for the focused buffer') end

    return { method = args.method or 'references', buf = buf, line = line, col = col }
  end

  if args.source == 'diagnostics' then return { buf = (args.path or args.bufnr) and util.resolve(args) or nil } end

  local full = args.path and fs.normalize(fs.full_path(args.path)) or nil

  if full and not fs.is_dir(full) then return { cwd = fs.dirname(full), path = fs.basename(full) } end

  return { cwd = full }
end

local function render(items, args)
  local located = #items > 0 and items[1].line ~= nil

  if located and args.source == 'grep' and (args.context or 0) > 0 then
    return (
      compact.excerpts(items, {
        context = args.context,
        budget = args.budget,
        offset = args.offset,
        lines_of = buffers.lines_of,
      })
    )
  end

  if located then return (compact.locations(items, { budget = args.budget, offset = args.offset })) end

  local rows = vim.tbl_map(function(item)
    return { label = item.label or compact.path(item.path) }
  end, vim.list_slice(items, (args.offset or 0) + 1))

  if #items == 0 then return 'no results' end

  return string.format('%d results\n', #items)
    .. compact.rows(rows, { 'label' }, { budget = args.budget }):gsub('^label\n', '')
end

local function search(args, ctx)
  local opts = source_opts(args)
  local items, err = sources.collect(args.source, args.query or '', opts)
  local text = render(items, args)

  if err then text = text .. '\n(' .. err .. ')' end

  if args.show then
    local picker = surfaces.pick({
      title = args.source,
      source = args.source,
      source_opts = opts,
      owner = ctx.caller,
    })

    if args.query and args.query ~= '' then picker:command('query', { text = args.query }) end

    text = text .. '\nshown to the user in ' .. picker.id .. ' (drive it with ui_command)'
  end

  return compact.reply(ctx.caller, items, text)
end

local function ui_pick(args, ctx)
  local items = args.items and vim.tbl_map(function(label)
    return { label = label }
  end, args.items)

  local picker = surfaces.pick({
    title = args.title,
    source = not items and args.source or nil,
    items = items,
    owner = ctx.caller,
    on_select = function() end,
  })

  if args.query then picker:command('query', { text = args.query }) end

  return picker:describe() .. '\nthe user is choosing; ui_read ' .. picker.id .. ' shows their choice once made'
end

local function ui_draw(args, ctx)
  if not args.lines and #(args.frames or {}) == 0 then util.fail('pass lines, or frames to animate') end

  if args.surface then
    local canvas = surface(args.surface)

    if canvas.kind ~= 'canvas' then util.fail(args.surface .. ' is a ' .. canvas.kind .. ', not a canvas') end

    canvas:command('draw', { lines = args.lines, frames = args.frames, components = args.components })

    return canvas:snapshot()
  end

  if not args.title then util.fail('pass a title, or the surface of a canvas to redraw') end

  return surfaces
    .canvas({
      title = args.title,
      lines = args.lines,
      frames = not args.lines and args.frames or nil,
      components = args.components,
      interval_ms = args.interval_ms,
      duration_ms = args.duration_ms,
      owner = ctx.caller,
    })
    :describe()
end

local function ui_animate(args, ctx)
  local scene = vim.deepcopy(args.scene or {})

  scene.preset = args.preset or scene.preset
  scene.at = args.at or scene.at
  scene.duration_ms = args.duration_ms or scene.duration_ms
  scene.loop = args.loop or scene.loop

  if not scene.preset and not scene.actors then
    util.fail('pass a preset (' .. table.concat(require('ui.anim.presets').names(), ', ') .. ') or a scene with actors')
  end

  return surfaces.scene({ title = args.title or scene.preset or 'scene', scene = scene, owner = ctx.caller }):describe()
end

local function ui_surfaces()
  local all = surfaces.all()

  if #all == 0 then return 'no surfaces open' end

  return table.concat(
    vim.tbl_map(function(s)
      return s:describe()
    end, all),
    '\n'
  )
end

local function ui_read(args)
  return surface(args.surface):snapshot(args.budget)
end

local function ui_command(args)
  local target = surface(args.surface)
  local result = target:command(args.command, args.args or {})

  Timer.wait(args.wait_ms or WAIT_MS, function()
    return target.state ~= 'loading'
  end, 10)

  local out = target:snapshot(args.budget)

  if result ~= nil then out = vim.inspect(result) .. '\n' .. out end

  return out
end

local function ui_screen(args, ctx)
  local text = util.screen(args.budget)

  return compact.reply(ctx.caller, text, text)
end

local function ui_keys(args, ctx)
  if args.win then Window(args.win):focus() end

  editor.press(args.keys)

  return ui_screen({ budget = args.budget }, ctx)
end

local SOURCE_TARGET = {
  {
    name = 'path',
    type = schema.str({
      description = 'files/grep: directory to search (default cwd). lsp/diagnostics: the buffer (default focused).',
    }),
    optional = true,
  },
  { name = 'bufnr', type = schema.int(), optional = true },
}

return {
  {
    name = 'search',
    risk = 'read',
    summary = 'Search a source and get compact results at once: files (fuzzy path), grep (regex, smart case; context adds the lines around each match, so no read has to follow), lsp (method: definition, references, type_definition, implementation at line/col, default the cursor), diagnostics, buffers. show = true also plays the search out in a picker the user sees (optional: use it when showing your work helps).',
    params = util.params(
      {
        { name = 'source', type = schema.literal({ 'files', 'grep', 'lsp', 'diagnostics', 'buffers' }) },
        { name = 'query', type = schema.str(), optional = true },
      },
      SOURCE_TARGET,
      {
        {
          name = 'method',
          type = schema.literal({ 'definition', 'references', 'type_definition', 'implementation' }),
          optional = true,
        },
        { name = 'line', type = schema.int(), optional = true },
        { name = 'col', type = schema.int(), optional = true },
        {
          name = 'context',
          type = schema.int({ description = 'grep: lines to include before and after each match.' }),
          optional = true,
        },
        {
          name = 'offset',
          type = schema.int({ description = 'Continue from a "… more (offset=N)" line.' }),
          optional = true,
        },
        {
          name = 'budget',
          type = schema.int({ description = 'Characters of output (default 6000).' }),
          optional = true,
        },
        { name = 'show', type = schema.bool(), optional = true },
      }
    ),
    fn = search,
  },
  {
    name = 'ui_pick',
    risk = 'write',
    summary = 'Ask the user to pick one of items (labels) or from a source, in a picker. Returns at once; ui_read the surface later for their choice.',
    params = {
      { name = 'title', type = schema.str() },
      { name = 'items', type = schema.list(schema.str()), optional = true },
      { name = 'source', type = schema.literal({ 'files', 'buffers', 'diagnostics' }), optional = true },
      { name = 'query', type = schema.str(), optional = true },
    },
    fn = ui_pick,
  },
  {
    name = 'ui_draw',
    risk = 'write',
    summary = 'Draw for the user in a float that takes no focus. lines = one picture; frames = a loop (one per interval_ms, default 100). Pass surface to redraw a canvas in place instead of opening another; duration_ms closes it by itself.\nStyle: [name]text[/] with name accent muted title warn error info hint added removed path (or a highlight group, capitalised); \\[ is a literal bracket.\nWidgets, expanded here so you do not write them out: {bar:60:20} (percent, width; {bar:@:20} fills over 20 ticks), {spark:3,5,8}, {spin}, {rule:30}, {rep:▓:8}.\nExample: lines ["[title]build[/] {spin}", "{bar:@:24} [muted]linking[/]"], duration_ms 5000.\nFor motion computed from time, run require("surfaces").canvas({ title = "x", draw = function(ms, tick) return lines end }) with lua.'
      .. component_help(),
    params = {
      { name = 'title', type = schema.str(), optional = true },
      { name = 'surface', type = schema.str(), optional = true },
      { name = 'duration_ms', type = schema.int(), optional = true },
      { name = 'lines', type = schema.list(schema.str()), optional = true },
      { name = 'frames', type = schema.list(schema.list(schema.str())), optional = true },
      { name = 'components', type = schema.list(schema.dict(schema.any())), optional = true },
      { name = 'interval_ms', type = schema.int(), optional = true },
    },
    fn = ui_draw,
  },
  {
    name = 'ui_animate',
    risk = 'write',
    summary = 'Play an animation over the editor, without taking focus. Cheapest: pass preset (fireworks, confetti, sparks, rain, snow, matrix, glitch, typewriter, shimmer, flash, ripple), optionally at [x,y] and duration_ms. Or pass scene { duration_ms, fps, loop, actors: [...] }. Positions are cells or "50%" strings; times are ms.\\nActors (type):\\n sprite: lines|frames, at, anchor "center", to [x,y] + ms + ease + from_ms (glide), x/y [[ms,v,ease?],...] keyframes, blend [[ms,0-100],...] (100 invisible), fade in|out|inout, border, bg.\\n emitter: at, burst N, rate/s, start_ms, stop_ms, life_ms [lo,hi], speed [lo,hi], angle [lo,hi] degrees (0 right, 90 up), gravity, drag, spread, glyphs [..] and hl [..] (walk through a particle\'s life), mixed (random hl), size. With kitty graphics particles are glowing pixels and glyphs are unused; pixels:false in the scene forces glyphs. Pixels sit behind the text, so sprites and code stay readable over them; front:true in the scene puts them on top.\\n shape (real pixels, needs kitty graphics: Ghostty or kitty, not tmux): shape circle|glow|ring|rect|line, at, color (style name or "#rrggbb"), r (radius in rows), w (columns), h (rows), end [x,y] (line), thick (px), round (px), opacity 0-100, anchor "center", show_ms, hide_ms; r, w, h, x, y, x2, y2, opacity also take [[ms,v,ease?],...]; to + ms + ease glides as a sprite does.\\n text (animates the focused window\'s real text, nothing is edited): effect reveal|sweep|glitch|rain, from_ms, ms.\\n camera (moves the real editor): move cursor|scroll|width|height, to ([line,col] or number), from_ms, ms, ease.\\n curtain: color, blend [[ms,0-100],...] (a screen-wide fade).\\nEases: linear, out_cubic, in_out, in_cubic, out_quad, in_out_sine, out_back, out_bounce, out_elastic. Styles in sprite lines as in ui_draw ([accent]x[/], {spin}, {bar:@:10}).\\nExample: {preset:"confetti"} or {scene:{actors:[{type:"sprite",lines:["[accent]★[/]"],at:[0,"50%"],to:["90%","50%"],ms:1200,ease:"out_bounce"},{type:"emitter",at:["90%","50%"],start_ms:1200,burst:30,glyphs:["✦","·"],hl:["warn","muted"]}]}}.\\nIt ends by itself; ui_command close stops it.',
    params = {
      { name = 'preset', type = schema.str(), optional = true },
      { name = 'scene', type = schema.dict(schema.any()), optional = true },
      { name = 'at', type = schema.list(schema.any()), optional = true },
      { name = 'duration_ms', type = schema.int(), optional = true },
      { name = 'loop', type = schema.bool(), optional = true },
      { name = 'title', type = schema.str(), optional = true },
    },
    fn = ui_animate,
  },
  {
    name = 'ui_surfaces',
    risk = 'read',
    summary = 'Open surfaces (pickers, lists, panels, canvases): id, kind, title, state, owner, and the commands each takes.',
    params = {},
    fn = ui_surfaces,
  },
  {
    name = 'ui_read',
    risk = 'read',
    summary = 'What a surface shows, as compact text: its state, query, selection or choice, and items.',
    params = {
      { name = 'surface', type = schema.str() },
      { name = 'budget', type = schema.int(), optional = true },
    },
    fn = ui_read,
  },
  {
    name = 'ui_command',
    risk = 'write',
    summary = 'Drive a surface one step, as the user would with keys (picker: query, move, select; list: cursor, open, add; panel: write; all: close). Waits for loading to finish, then returns what it shows.',
    params = {
      { name = 'surface', type = schema.str() },
      { name = 'command', type = schema.str() },
      { name = 'args', type = schema.dict(schema.any()), optional = true },
      { name = 'wait_ms', type = schema.int(), optional = true },
      { name = 'budget', type = schema.int(), optional = true },
    },
    fn = ui_command,
  },
  {
    name = 'ui_screen',
    risk = 'read',
    summary = 'What the user sees now: every window of the current tab (floats included) with its buffer, visible lines and cursor (marked >), the mode, and open surfaces. Use it to read any UI, such as a vgit view.',
    params = { { name = 'budget', type = schema.int(), optional = true } },
    fn = ui_screen,
  },
  {
    name = 'ui_keys',
    risk = 'exec',
    summary = 'Type keys into the editor, with mappings, as the user would (e.g. "s" in a vgit diff view stages a hunk, "<C-w>j" moves down a window), optionally in window win first. Returns ui_screen afterwards.',
    params = {
      { name = 'keys', type = schema.str() },
      { name = 'win', type = schema.int(), optional = true },
      { name = 'budget', type = schema.int(), optional = true },
    },
    fn = ui_keys,
  },
}
