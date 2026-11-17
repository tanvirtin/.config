local Buffer = require('core.Buffer')
local motion = require('ui.motion')
local text = require('core.text')
local highlight = require('core.highlight')
local layer = require('ui.design.layer')

local TextFx = {}

TextFx.__index = TextFx

TextFx.NAMESPACE = 'ui_anim_text'
TextFx.GLITCH = { '▒', '░', '#', '%', '$', '@', '?', '/', '\\', '▚', '▞' }
TextFx.RAIN = { 'ｱ', 'ｲ', 'ｳ', 'ｴ', 'ｵ', 'ｶ', 'ｷ', '0', '1', '7', '*', ':' }
TextFx.EFFECTS = { 'reveal', 'sweep', 'glitch', 'rain' }
TextFx.BAND = 12

local function overlay(buffer, namespace, row, col, glyph, group)
  buffer:set_extmark(namespace, row, 0, {
    virt_text = { { glyph, group } },
    virt_text_pos = 'overlay',
    virt_text_win_col = col,
    priority = layer.of('animation'),
    hl_mode = 'replace',
  })
end

local function visible(window, buffer)
  local top, bottom = window:get_visible_range()
  local last = buffer:get_line_count()
  local lines = buffer:get_lines(top, math.min(bottom, last))

  return top, lines
end

local EFFECT = {}

function EFFECT.reveal(ctx)
  local total = 0

  for _, line in ipairs(ctx.lines) do
    total = total + text.width(line) + 1
  end

  local shown = math.floor(total * ctx.progress)

  for index, line in ipairs(ctx.lines) do
    local width = text.width(line)
    local left = math.max(0, math.min(width, shown))

    if left < width then
      overlay(ctx.buffer, ctx.namespace, ctx.top + index - 1, left, (' '):rep(width - left), 'Normal')
    end

    shown = shown - width - 1
  end
end

function EFFECT.sweep(ctx)
  local span = ctx.width + #ctx.lines * 2 + TextFx.BAND * 2
  local head = ctx.progress * span - TextFx.BAND

  for index, line in ipairs(ctx.lines) do
    local width = text.width(line)
    local center = head - (index - 1) * 2

    local from = math.max(0, math.floor(center - TextFx.BAND / 2))
    local to = math.min(width, math.ceil(center + TextFx.BAND / 2))

    if to > from then
      local reach = math.abs(center - (from + to) / 2) / (TextFx.BAND / 2)
      local group = reach < 0.4 and 'UiGlint' or 'UiGlintSoft'

      ctx.buffer:set_extmark(ctx.namespace, ctx.top + index - 1, from, {
        end_col = to,
        hl_group = highlight.exists(group) and group or 'UiAccent',
        priority = layer.of('animation'),
      })
    end
  end
end

function EFFECT.glitch(ctx)
  local strength = math.sin(math.pi * ctx.progress)
  local count = math.floor(ctx.width * #ctx.lines * 0.06 * strength)

  for _ = 1, count do
    local row = math.random(#ctx.lines)
    local width = text.width(ctx.lines[row])

    if width > 0 then
      overlay(
        ctx.buffer,
        ctx.namespace,
        ctx.top + row - 1,
        math.random(0, width - 1),
        TextFx.GLITCH[math.random(#TextFx.GLITCH)],
        math.random() < 0.5 and 'UiError' or 'UiAccent'
      )
    end
  end
end

function EFFECT.rain(ctx)
  local columns = math.max(1, math.floor(ctx.width / 3))
  local rows = #ctx.lines

  for column = 1, columns do
    local x = math.floor((column - 1) * ctx.width / columns + (column * 7) % 3)
    local speed = 6 + (column * 5) % 9
    local head = (ctx.ms / 1000 * speed + column * 13) % (rows + 10)
    local fade = 1 - motion.clamp((ctx.progress - 0.75) / 0.25)

    for tail = 0, 7 do
      local row = math.floor(head) - tail

      if row >= 0 and row < rows and (tail < 7 * fade or tail == 0 and fade > 0) then
        local group = tail == 0 and 'UiGlint' or tail < 3 and 'UiAdded' or 'UiMuted'

        overlay(
          ctx.buffer,
          ctx.namespace,
          ctx.top + row,
          x,
          TextFx.RAIN[(row * 5 + column * 3 + math.floor(ctx.ms / 80)) % #TextFx.RAIN + 1],
          highlight.exists(group) and group or 'UiAccent'
        )
      end
    end
  end
end

function TextFx.new(spec, window)
  return setmetatable({
    effect = spec.effect,
    from_ms = spec.from_ms or 0,
    ms = spec.ms or 1500,
    window = window,
    buffer = window:get_buffer(),
    namespace = Buffer.namespace(TextFx.NAMESPACE),
  }, TextFx)
end

function TextFx:duration()
  return self.from_ms + self.ms
end

function TextFx:_clear()
  if self.buffer:is_valid() then self.buffer:clear_namespace(self.namespace) end
end

function TextFx:update(ms)
  if not self.window:is_valid() or not self.buffer:is_valid() then return end

  self:_clear()

  local progress = motion.clamp((ms - self.from_ms) / self.ms)

  if (ms < self.from_ms and self.effect ~= 'reveal') or ms > self:duration() then return end

  local top, lines = visible(self.window, self.buffer)
  local width = 0

  for _, line in ipairs(lines) do
    width = math.max(width, text.width(line))
  end

  EFFECT[self.effect]({
    buffer = self.buffer,
    namespace = self.namespace,
    lines = lines,
    top = top,
    width = math.max(width, 1),
    progress = progress,
    ms = ms,
  })
end

function TextFx:destroy()
  self:_clear()
end

return TextFx
