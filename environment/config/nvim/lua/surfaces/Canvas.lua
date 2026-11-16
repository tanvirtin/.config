local Timer = require('core.Timer')
local Window = require('core.Window')
local console = require('core.console')
local text = require('core.text')
local Surface = require('surfaces.Surface')
local View = require('ui.View')
local LinesComponent = require('ui.components.LinesComponent')
local markup = require('ui.markup')
local catalog = require('ui.pixel.catalog')
local compact = require('compact')
local schema = require('nvim_mcp.schema')

local Canvas = Surface:extend()

Canvas.INTERVAL_MS = 100
Canvas.PAD = ' '

local MOVING = { '{spin}', '{bar:@' }

local function checked(id, kind, props)
  local ok, resolved = pcall(catalog.resolve, kind, props)

  if not ok then error('component ' .. id .. ': ' .. resolved, 0) end

  return resolved
end

local function parse_all(specs)
  local components, ids = {}, {}

  for _, spec in ipairs(specs or {}) do
    if type(spec) ~= 'table' or type(spec.id) ~= 'string' then error('each component needs a string id', 0) end
    if type(spec.type) ~= 'string' then error('component ' .. spec.id .. ' needs a string type', 0) end
    if components[spec.id] then error('duplicate component id ' .. spec.id, 0) end

    local props = {}

    for key, value in pairs(spec) do
      if key ~= 'id' and key ~= 'type' then props[key] = value end
    end

    checked(spec.id, spec.type, props)

    components[spec.id] = { type = spec.type, props = props }
    ids[#ids + 1] = spec.id
  end

  return components, ids
end

local function build(component)
  local module = catalog.get(component.type)

  if module.commands and module.animated and module.animated(catalog.resolve(component.type, component.props)) then
    local animation = catalog.animation(component.type, component.props)

    animation.linger_ms = math.huge

    if animation:chunks(1) then
      component.handle, component.animated = animation, true

      return
    end

    animation:stop()
  end

  component.handle, component.animated = catalog.render(component.type, component.props), false
end

local function release(component)
  local handle = component.handle

  if handle and component.animated then
    handle:stop()
  elseif handle then
    handle.release()
  end

  component.handle = nil
end

local function rows_of(component)
  local handle = component.handle

  if not handle then return {} end
  if not component.animated then return handle.lines end

  local rows = {}

  for row = 1, handle.rows do
    rows[row] = handle:chunks(row) or {}
  end

  return rows
end

local function summarize(id, component)
  local keys = vim.tbl_keys(component.props)
  local parts = { id, component.type }

  table.sort(keys)

  for _, key in ipairs(keys) do
    local value = component.props[key]

    if type(value) == 'table' then value = '[' .. #value .. ' items]' end

    parts[#parts + 1] = key .. '=' .. tostring(value)
  end

  return table.concat(parts, ' ')
end

function Canvas:constructor(opts)
  local instance = Surface.constructor(self, { kind = 'canvas', title = opts.title or 'Canvas', owner = opts.owner })

  instance._frames = opts.frames or { opts.lines or {} }
  instance._draw = opts.draw
  instance._interval = opts.interval_ms or Canvas.INTERVAL_MS
  instance._ttl_ms = opts.duration_ms
  instance._width = opts.width
  instance._height = opts.height
  instance._timer = Timer()
  instance._ttl = Timer()
  instance._tick = 0
  instance._lines = {}
  instance._components, instance._ids = parse_all(opts.components)

  return instance
end

function Canvas:_moves()
  if self._draw or #self._frames > 1 then return true end

  for _, line in ipairs(self._frames[1]) do
    for _, widget in ipairs(MOVING) do
      if line:find(widget, 1, true) then return true end
    end
  end

  return false
end

function Canvas:_frame(tick, elapsed)
  if self._draw then return self._draw(elapsed, tick) end

  return self._frames[tick % #self._frames + 1]
end

function Canvas:_embed()
  return function(id)
    local component = self._components[id]

    if component then return rows_of(component) end
  end
end

function Canvas:_placeholders()
  return function(id)
    local component = self._components[id]

    if component then return { { { '[' .. component.type .. ' ' .. id .. ']' } } } end
  end
end

function Canvas:_size(first)
  local embed = self:_embed()
  local width, height = text.width(self.title) + 4, 1

  for _, frame in ipairs(self._draw and { first } or self._frames) do
    height = math.max(height, #markup.render(frame, 0, '', embed))

    width = math.max(width, markup.width(frame, 0, embed) + 2 * #Canvas.PAD)
  end

  return math.min(self._width or width, Window.screen_width() - 4),
    math.min(self._height or height, math.floor(Window.screen_height() * 0.7))
end

function Canvas:_resize(first)
  local width, height = self:_size(first)

  self._body:with_element(function(element)
    element:set_width(width)
    element:set_height(height)
  end)
end

function Canvas:_paint(lines, tick)
  self._lines = lines

  local shown, highlights = markup.render(lines, tick, Canvas.PAD, self:_embed())

  self._body:set_content(shown, highlights)
end

function Canvas:_step()
  if not self:is_open() then return self:close() end

  self._tick = self._tick + 1

  local ok, lines = pcall(self._frame, self, self._tick, Timer.now() - self._started)

  if not ok then
    self:close()
    console.notify_now(string.format('canvas %s stopped: %s', tostring(self.id), tostring(lines)), 'warn')

    return
  end

  self:_paint(lines, self._tick)
end

function Canvas:_play()
  self._timer:close()

  if not self:_moves() then return end

  self._timer:every(self._interval, function()
    self:_step()
  end)
end

function Canvas:_build_all()
  for _, id in ipairs(self._ids) do
    build(self._components[id])
  end
end

function Canvas:_release_all()
  for _, component in pairs(self._components) do
    release(component)
  end
end

function Canvas:_replace(specs)
  local components, ids = parse_all(specs)

  self:_release_all()
  self._components, self._ids = components, ids
  self:_build_all()
end

function Canvas:_show()
  self._started = Timer.now()
  self:_build_all()

  local first = self:_frame(0, 0)
  local width, height = self:_size(first)

  self._body = LinesComponent({
    lines = {},
    cursorline = false,
    border = 'rounded',
    title = self.title,
    focus = false,
  })
  self._view = View()
  self._view:_render({ component = self._body, mode = 'popup', width = width, height = height })

  for _, key in ipairs({ 'q', '<Esc>' }) do
    self._body:set_keymap('n', key, function()
      self:close()
    end, 'Close')
  end

  self:_paint(first, 0)
  self:set_state('ready')
  self:_play()

  if self._ttl_ms then self._ttl:after(self._ttl_ms, function()
    self:close()
  end) end
end

function Canvas:open()
  local ok, err = pcall(self._show, self)

  if not ok then
    self:close()
    error(err, 0)
  end

  return self
end

Canvas.COMMANDS = {
  draw = {
    summary = 'Replace what it draws with lines, or frames to animate. The float resizes to fit.',
    params = {
      { name = 'lines', type = schema.list(schema.str()), optional = true },
      { name = 'frames', type = schema.list(schema.list(schema.str())), optional = true },
      { name = 'components', type = schema.list(schema.dict(schema.any())), optional = true },
    },
    run = function(self, args)
      if not args.lines and #(args.frames or {}) == 0 then error('pass lines, or frames to animate', 0) end

      if args.components then self:_replace(args.components) end

      self._frames = args.frames or { args.lines }
      self._draw = nil
      self._tick = 0

      self:_resize()
      self:_paint(self._frames[1], 0)
      self:_play()
    end,
  },
  set = {
    summary = 'Change one component\'s props (merged into its current props) and redraw it in place.',
    params = {
      { name = 'id', type = schema.str() },
      { name = 'props', type = schema.dict(schema.any()) },
    },
    run = function(self, args)
      local component = self._components[args.id]

      if not component then
        error(string.format('no component %s (ids: %s)', args.id, table.concat(self._ids, ', ')), 0)
      end

      local props = vim.tbl_extend('force', component.props, args.props)
      local resolved = checked(args.id, component.type, props)

      component.props = props

      if component.animated and catalog.get(component.type).animated(resolved) then
        component.handle:set(props)
      else
        release(component)
        build(component)
      end

      self:_resize(self._lines)
      self:_paint(self._lines, self._tick)
    end,
  },
}

function Canvas:close()
  self._timer:close()
  self._ttl:close()
  self:_release_all()

  if self.state ~= 'closed' then Surface.close(self) end
end

function Canvas:snapshot(budget)
  local shown = markup.render(self._lines, self._tick, Canvas.PAD, self:_placeholders())
  local out = string.format('%s: canvas "%s" [%s]\n', self.id, self.title, self.state)
    .. compact.text(table.concat(shown, '\n'), budget or compact.BUDGET)

  for _, id in ipairs(self._ids) do
    out = out .. '\n' .. summarize(id, self._components[id])
  end

  return out
end

return Canvas
