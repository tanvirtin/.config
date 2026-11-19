local lazy = require('core.lazy')

local asks = lazy('sn.asks')
local async = lazy('sn.async')
local Object = lazy('core.Object')
local console = lazy('core.console')
local settings = lazy('sn.settings')
local ASK = require('sn.types.events').ASK
local presenter = lazy('sn.asks.presenter')
local elicitation = require('sn.types.elicitation')

local FIELD = elicitation.FIELD

local CHOICE = elicitation.CHOICE

local Elicitation = Object:extend()

Elicitation.MAX_KEYS = 9

function Elicitation:_steps_of(request)
  if request.mode ~= elicitation.MODE.form then return {} end

  local companion = elicitation.companions(request)

  return vim.tbl_filter(function(field)
    return not companion[field.key]
  end, request.fields)
end

function Elicitation:_by_key(request)
  local out = {}

  for _, field in ipairs(request.fields) do
    out[field.key] = field
  end

  return out
end

function Elicitation:_defaults(request)
  local picked = {}

  for _, field in ipairs(request.fields) do
    if field.kind == FIELD.multi and type(field.default) == 'table' then
      picked[field.key] = {}

      for _, value in ipairs(field.default) do
        picked[field.key][value] = true
      end
    end
  end

  return picked
end

function Elicitation:constructor(ask)
  local request = ask.request

  return {
    kind = ASK.elicitation,
    session = ask.session,
    request = request,
    future = async.Future(),
    steps = self:_steps_of(request),
    fields = self:_by_key(request),
    step = 1,
    values = {},
    picked = self:_defaults(request),
    writing_key = nil,
    error = nil,
  }
end

function Elicitation:is_open()
  return not self.future.done
end

function Elicitation:current()
  return self.steps[self.step]
end

function Elicitation:writing()
  return self.writing_key and self.fields[self.writing_key] or nil
end

function Elicitation:writing_label()
  local field = self:writing()

  return field and elicitation.name(field) or nil
end

function Elicitation:is_picked(value)
  local field = self:current()

  return field ~= nil and (self.picked[field.key] or {})[value] == true
end

function Elicitation:_box(field, checked)
  if field.kind == FIELD.multi then return checked end
end

function Elicitation:_shown_default(field)
  if field.kind == FIELD.boolean then return field.default and 'yes' or 'no' end

  return tostring(field.default)
end

function Elicitation:_extras(field)
  local extras = {}

  if field.kind == FIELD.text or field.kind == FIELD.number or field.kind == FIELD.integer then
    extras[#extras + 1] = { action = CHOICE.write, target = field.key, label = 'Write an answer…' }
  end

  if field.other then
    extras[#extras + 1] = {
      action = CHOICE.write,
      target = field.other,
      label = 'Other…',
      checked = self:_box(field, self.values[field.other] ~= nil),
    }
  end

  if field.default ~= nil and field.kind ~= FIELD.multi then
    extras[#extras + 1] = { action = CHOICE.default, label = 'Use the default (' .. self:_shown_default(field) .. ')' }
  end

  if field.kind == FIELD.multi then
    extras[#extras + 1] = { action = CHOICE.done, label = 'Done' }
  elseif not field.required then
    extras[#extras + 1] = { action = CHOICE.skip, label = 'Skip' }
  end

  return extras
end

function Elicitation:_options(field)
  if field.kind == FIELD.boolean then
    return {
      { value = true, label = 'Yes' },
      { value = false, label = 'No' },
    }
  end

  return field.options
end

function Elicitation:choices()
  local choices = {}

  local function add(spec)
    spec.key = tostring(#choices + 1)
    choices[#choices + 1] = elicitation.Choice(spec)
  end

  if self.request.mode == elicitation.MODE.url then
    add({ action = CHOICE.open, label = 'Open in the browser' })
    return choices
  end

  local field = self:current()

  if not field then return choices end

  local extras = self:_extras(field)
  local options = self:_options(field)
  local room = Elicitation.MAX_KEYS - #extras
  local shown = #options > room and room - 1 or #options
  local multi = field.kind == FIELD.multi

  for i = 1, shown do
    local option = options[i]

    add({
      action = multi and CHOICE.toggle or CHOICE.set,
      value = option.value,
      label = option.label,
      description = option.description,
      checked = self:_box(field, self:is_picked(option.value)),
    })
  end

  if shown < #options then add({ action = CHOICE.pick, label = string.format('More (%d)…', #options - shown) }) end

  for _, extra in ipairs(extras) do
    add(extra)
  end

  return choices
end

function Elicitation:choice(key)
  if not self:is_open() or self:writing() then return nil end

  if key == settings.keymaps:get('transcript').decline then
    return elicitation.Choice({ key = key, action = CHOICE.decline, label = 'Decline' })
  end

  for _, choice in ipairs(self:choices()) do
    if choice.key == key then return choice end
  end
end

function Elicitation:answer(key)
  local chosen = self:choice(key)

  if not chosen then return false end

  self.error = nil

  local field = self:current()
  local action = chosen.action

  if action == CHOICE.decline then
    self:decline()
  elseif action == CHOICE.open then
    console.open_url(self.request.url)
    self:_settle(elicitation.accept())
  elseif action == CHOICE.set or action == CHOICE.toggle then
    self:pick(chosen.value)
  elseif action == CHOICE.default then
    self.values[field.key] = field.default
    self:_advance()
  elseif action == CHOICE.skip then
    self.values[field.key] = nil
    self:_advance()
  elseif action == CHOICE.done then
    self:_done(field)
  elseif action == CHOICE.write then
    self.writing_key = chosen.target
  end

  return action
end

function Elicitation:pick(value)
  local field = self:current()

  if not field or not self:is_open() then return false end

  if field.kind ~= FIELD.multi then
    self.values[field.key] = value
    if field.other then self.values[field.other] = nil end
    self:_advance()
    return true
  end

  local picked = self.picked[field.key] or {}

  if not picked[value] and field.max and self:_count(field) >= field.max then
    self.error = string.format('pick at most %d', field.max)
    return false
  end

  picked[value] = not picked[value] or nil
  self.picked[field.key] = picked

  return true
end

function Elicitation:options()
  local field = self:current()

  return field and self:_options(field) or {}
end

function Elicitation:_count(field)
  local count = 0

  for _ in pairs(self.picked[field.key] or {}) do
    count = count + 1
  end

  return count + (field.other and self.values[field.other] ~= nil and 1 or 0)
end

function Elicitation:_done(field)
  local least = field.min or (field.required and 1) or 0

  if self:_count(field) < least then
    self.error = string.format('pick at least %d', least)
    return
  end

  local picked, list = self.picked[field.key] or {}, {}

  for _, option in ipairs(field.options) do
    if picked[option.value] then list[#list + 1] = option.value end
  end

  self.values[field.key] = list
  self:_advance()
end

function Elicitation:_length(text)
  local _, count = text:gsub('[^\128-\191]', '')

  return count
end

function Elicitation:_parse(field, text)
  if field.kind == FIELD.number or field.kind == FIELD.integer then
    local number = tonumber(text)

    if not number then return nil, 'write a number' end
    if field.kind == FIELD.integer and number ~= math.floor(number) then return nil, 'write a whole number' end
    if field.min and number < field.min then return nil, string.format('write at least %s', field.min) end
    if field.max and number > field.max then return nil, string.format('write at most %s', field.max) end

    return number
  end

  if field.min and self:_length(text) < field.min then
    return nil, string.format('write at least %d characters', field.min)
  end
  if field.max and self:_length(text) > field.max then
    return nil, string.format('write at most %d characters', field.max)
  end

  return text
end

function Elicitation:submit_text(text)
  local field = self:writing()

  if not field or not self:is_open() then return nil, 'nothing is waiting for an answer' end

  local value, why = self:_parse(field, vim.trim(text))

  if value == nil then return nil, why end

  self.writing_key = nil
  self.error = nil
  self.values[field.key] = value

  local owner = self:current()

  if owner and owner.other == field.key and owner.kind == FIELD.multi then return true end
  if owner and owner.other == field.key then self.values[owner.key] = nil end

  self:_advance()

  return true
end

function Elicitation:stop_writing()
  self.writing_key = nil

  return self
end

function Elicitation:_advance()
  self.step = self.step + 1

  if self.step > #self.steps then self:_settle(elicitation.accept(self:content())) end
end

function Elicitation:content()
  local content = {}

  for key, value in pairs(self.values) do
    content[key] = value
  end

  return content
end

function Elicitation:_settle(answer)
  if self.future.done then return end

  self.writing_key = nil
  self.future:set_result(answer)
  async.drain()
end

function Elicitation:decline()
  self:_settle(elicitation.decline())

  return self
end

function Elicitation:dismiss()
  self:_settle(elicitation.cancel())

  return self
end

function Elicitation:view()
  local field = self:current()
  local writing = self:writing_label()

  return elicitation.View({
    message = self.request.message,
    url = self.request.url,
    label = field and elicitation.label(field) or nil,
    step = self.step,
    count = #self.steps,
    choices = writing and {} or self:choices(),
    writing = writing,
    error = self.error,
  })
end

function Elicitation.ask(ask)
  return presenter.present(ask.session, Elicitation(ask))
end

function Elicitation.select(prompt)
  local field = prompt:current()

  if not field then return end

  local multi = field.kind == FIELD.multi

  console.select(prompt:options(), {
    prompt = field.title or field.description or prompt.request.message,
    format_item = function(option)
      local checked = multi and (prompt:is_picked(option.value) and '[x] ' or '[ ] ') or ''

      return checked .. option.label .. (option.description and (' — ' .. option.description) or '')
    end,
  }, function(option)
    if option and prompt:is_open() then prompt:pick(option.value) end
    asks.changed(prompt.session)
  end)
end

function Elicitation.follow(view, prompt, action)
  if action == CHOICE.write and view.composer then
    view.composer.open(view.session, { insert = true, display = view.display, answer = prompt })
  elseif action == CHOICE.pick then
    Elicitation.select(prompt)
  end

  asks.changed(view.session)
end

return Elicitation
