local guides = require('ui.guides')
local Buffer = require('core.editor.Buffer')
local compact = require('compact')
local panes = require('core.editor.panes')
local schema = require('nvim_mcp.schema')
local spots = require('nvim_mcp.spots')
local util = require('nvim_mcp.tools.util')

local layout = {}

layout.OWNER = 'agent'
layout.PANES = { 'code', 'peek' }

function layout.owner(ctx)
  return ctx.caller or layout.OWNER
end

local function place(entries)
  local placed, failed, previous = {}, {}, nil

  for _, entry in ipairs(entries) do
    local spot, err = spots.parse(entry.at, previous)
    local ok, buf = false, nil

    if spot then
      ok, buf = pcall(util.resolve, { path = spot.path })
      if not ok then err = tostring(buf) end
    end

    local range

    if ok then
      range, err = spots.resolve(spot, buf)
    end

    if range then
      previous = spot.path
      placed[#placed + 1] = { entry = entry, buf = buf, from = range.from, to = range.to, note = range.note }
    else
      failed[#failed + 1] = string.format('failed: "%s": %s', entry.at, err or 'not found')
    end
  end

  return placed, failed
end

local function show(args, ctx)
  local owner = layout.owner(ctx)
  local placed, failed = place(args.spots)
  local numbered = #placed > 1
  local pane_of, files = {}, 0

  if not args.keep then guides.clear(owner) end

  for _, spot in ipairs(placed) do
    if not pane_of[spot.buf] and files < #layout.PANES then
      files = files + 1
      pane_of[spot.buf] = layout.PANES[files]
      panes.show(owner, util.anchor(ctx.caller), pane_of[spot.buf], Buffer(spot.buf), { line = spot.from })
      util.list(spot.buf)
    end
  end

  local lines = {}

  for step, spot in ipairs(placed) do
    guides.mark(owner, Buffer(spot.buf), {
      from = spot.from,
      to = spot.to,
      label = spot.entry.note,
      step = numbered and step or nil,
    })

    lines[#lines + 1] = string.format(
      '%d. %s %s:%d-%d%s%s',
      step,
      pane_of[spot.buf] or 'painted',
      compact.path(util.buf_label(spot.buf)),
      spot.from,
      spot.to,
      spot.entry.note and ('  ' .. spot.entry.note) or '',
      spot.note and (' (' .. spot.note .. ')') or ''
    )
  end

  vim.list_extend(lines, failed)

  return #lines == 0 and 'nothing to show' or table.concat(lines, '\n')
end

local function hide(args, ctx)
  local owner = layout.owner(ctx)
  local cleared = guides.clear(owner)
  local closed = args.panes == false and 0 or panes.close(owner)

  return string.format(
    'cleared %d guide%s, closed %d pane%s',
    cleared,
    cleared == 1 and '' or 's',
    closed,
    closed == 1 and '' or 's'
  )
end

function layout.describe(owner)
  local lines = {}

  for _, pane in ipairs(panes.list(owner)) do
    local window = pane.window

    lines[#lines + 1] = string.format(
      'pane %s: %s:%d (win %d)',
      pane.name,
      compact.path(util.buf_label(window:get_buffer().bufnr)),
      window:get_cursor()[1],
      window.win_id
    )
  end

  local painted = #guides.list(owner)

  if painted > 0 then lines[#lines + 1] = string.format('guides: %d painted', painted) end

  return lines
end

layout.TOOLS = {
  {
    name = 'show',
    risk = 'read',
    summary = 'Show the user code beside the chat and annotate it, in one call, without taking their focus. Each spot is at = path, path:42, path:42-58, path#symbol (its whole definition), nvim://file/path#L42, or #symbol for the previous spot\'s file. note is drawn above the spot as a short callout: write it as the one-line comment a developer of that codebase would write there. Several spots become numbered steps. The first file opens in pane "code", the second in "peek". Each call replaces your last notes (keep = true adds to them); notes also vanish when the user sends their next prompt.',
    params = {
      {
        name = 'spots',
        type = schema.list(schema.model({
          { name = 'at', type = schema.str() },
          { name = 'note', type = schema.str(), optional = true },
        })),
      },
      { name = 'keep', type = schema.bool(), optional = true },
    },
    fn = show,
  },
  {
    name = 'hide',
    risk = 'read',
    summary = 'Clear your guides and close your panes (panes = false keeps the panes). Never touches the user\'s own windows.',
    params = { { name = 'panes', type = schema.bool(), optional = true } },
    fn = hide,
  },
}

return vim.list_extend(layout, layout.TOOLS)
