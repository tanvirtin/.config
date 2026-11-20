local hl = require('ui.hl')
local glitch = require('ui.glitch')
local motion = require('ui.motion')
local Timer = require('core.Timer')
local design = require('ui.design')
local Object = require('core.Object')
local layer = require('ui.design.layer')
local settings = require('harness.settings')
local Buffer = require('core.editor.Buffer')
local theme = require('harness.transcript.theme')

local Fades = Object:extend()

Fades.NAMESPACE = Buffer.namespace('harness.fade')
Fades.PRIORITY = layer.of('highlight')
Fades.EFFECT_PRIORITY = layer.of('effect')
Fades.MAX = 8
Fades.TUNE = 0.6
Fades.TUNE_STATIC = 'medium'

function Fades:constructor(buffer, view)
  return { buffer = buffer, view = view, chunks = {}, high = -1, seen = {} }
end

local function line_at(buffer, row)
  return buffer:get_lines(row, row + 1)[1] or ''
end

function Fades:observe()
  local view = self.view
  local touched = view.document.touched

  if theme.reduced() or not touched or not view.session:running() or view.session:loading() then return false end

  local from, to = touched.from, touched.to

  self.seen = self.seen or {}

  local col = self:grown(from)
  local fading = self:touch(from, to, Timer.now(), nil, col)

  self:remember(from, to)

  return fading
end

function Fades:grown(row)
  local previous = self.seen[row]

  if not previous or previous == '' then return nil end

  local line = line_at(self.buffer, row)

  if #line > #previous and line:sub(1, #previous) == previous then return #previous end
end

function Fades:remember(from, to)
  self.seen = {}

  for index, line in ipairs(self.buffer:get_lines(from, to + 1)) do
    self.seen[from + index - 1] = line
  end
end

function Fades:reveal(row)
  if theme.reduced() then return false end

  local document = self.view.document
  local block = document:block_at(row - 1)

  for _, fold in ipairs(block and block.folds or {}) do
    local from, to = block.start + fold[1], block.start + fold[2]

    if row - 1 >= from and row - 1 <= to then return self:touch(from, to, Timer.now(), true) end
  end

  return false
end

function Fades:group(row)
  local view = self.view
  local block = view and view.document:block_at(row)

  return block and block.kind == 'thought' and 'UiThoughtStream' or 'UiFade'
end

function Fades:drop(from, to)
  local kept = {}

  for _, chunk in ipairs(self.chunks) do
    if chunk.to < from or chunk.from > to then kept[#kept + 1] = chunk end
  end

  self.chunks = kept
end

function Fades:touch(from, to, now, any_size, col)
  local limit = settings.transcript:get('fade_rows')

  if settings.transcript:get('fade_ms') <= 0 or (not any_size and to - from + 1 > limit) then return false end

  if col then
    self:drop(from, to)
  elseif not any_size then
    from = math.max(from, self.high + 1)

    if from > to then return false end
  end

  self.high = math.max(self.high, to)

  table.insert(self.chunks, { from = from, to = to, col = col, group = self:group(from), started = now })

  while #self.chunks > Fades.MAX do
    table.remove(self.chunks, 1)
  end

  return true
end

function Fades:tune(chunk, progress, now)
  if chunk.group ~= 'UiThoughtStream' or progress >= Fades.TUNE then return end

  local density = design.static.density(Fades.TUNE_STATIC, 1 - progress / Fades.TUNE)
  local seed = design.static.seed(now)

  for row = chunk.from, chunk.to do
    local line = line_at(self.buffer, row)
    local from = row == chunk.from and chunk.col or #(line:match('^[%s>]*') or '')

    for _, cell in ipairs(glitch.cols(line, density, seed + row, from)) do
      self.buffer:set_extmark(Fades.NAMESPACE, row, cell[1], {
        virt_text = { { cell[2], 'UiThoughtFade2' } },
        virt_text_pos = 'overlay',
        priority = Fades.PRIORITY,
      })
    end
  end
end

function Fades:step(now)
  local ms = settings.transcript:get('fade_ms')
  local alive = {}

  self.buffer:clear_namespace(Fades.NAMESPACE)

  for _, chunk in ipairs(self.chunks) do
    local progress = (now - chunk.started) / ms

    if progress < 1 then
      local index = motion.steps(hl.FADE_STEPS - 1, motion.ease.out_cubic(progress))
      local col = chunk.col

      if col and col > 0 then col = math.min(col, #line_at(self.buffer, chunk.from)) end

      self.buffer:set_extmark(Fades.NAMESPACE, chunk.from, col or 0, {
        end_row = chunk.to + 1,
        end_col = 0,
        hl_group = (chunk.group or 'UiFade') .. index,
        priority = Fades.EFFECT_PRIORITY,
      })
      self:tune(chunk, progress, now)
      alive[#alive + 1] = chunk
    end
  end

  self.chunks = alive

  return #alive > 0
end

return Fades
