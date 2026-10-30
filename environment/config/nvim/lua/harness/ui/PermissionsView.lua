local lazy = require('core.lazy')

local fs = lazy('core.fs')
local View = require('ui.View')
local Timer = lazy('core.Timer')
local compact = require('compact')
local console = lazy('core.console')
local schema = require('nvim_mcp.schema')
local settings = lazy('harness.settings')
local dataclass = require('core.dataclass')
local Surface = require('surfaces.Surface')
local theme = lazy('harness.transcript.theme')
local events = require('harness.types.events')
local permission = require('harness.types.permission')
local permission_rules = lazy('harness.permission_rules')
local LinesComponent = require('ui.components.LinesComponent')

local PermissionsView = Surface:extend()

PermissionsView.ROW = dataclass.enum({ 'grant', 'rule' })

PermissionsView.DECISIONS_SHOWN = 20

PermissionsView.WIDTH = 160

PermissionsView.REFRESH = {
  [events.NOTICE.permissions] = true,
  [events.NOTICE.waiting] = true,
  [events.NOTICE.config] = true,
  [events.KIND.mode] = true,
  [events.KIND.config] = true,
}

PermissionsView.DECISION_LABELS = {
  [permission.DECISION.allow_once] = 'allowed',
  [permission.DECISION.allow_always] = 'always',
  [permission.DECISION.reject_once] = 'refused',
  [permission.DECISION.reject_always] = 'never',
  [permission.DECISION.cancelled] = 'cancelled',
}

function PermissionsView:constructor(session)
  local instance = Surface.constructor(self, { kind = 'permissions', title = 'Permissions · ' .. session.key })

  instance.session = session
  instance._rows = {}

  return instance
end

function PermissionsView.model(session)
  local rules, problems = permission_rules.load(session.agent, session.dir)
  local mode = session:mode()

  return {
    mode = mode and (mode.name or mode.id) or nil,
    waiting = session:waiting(),
    grants = session.permissions:grants(),
    supported = permission_rules.supported(session.agent),
    rules = rules,
    problems = problems,
    decisions = session.permissions:decisions(),
  }
end

local function ago(time)
  local spent = time and theme.duration(math.max(Timer.now() - time, 0)) or ''

  return spent ~= '' and (spent .. ' ago') or 'just now'
end

local function cut(text)
  return compact.line(text, PermissionsView.WIDTH)
end

function PermissionsView.render(model)
  local lines, highlights, rows = {}, {}, {}

  local function add(text, hl, row)
    lines[#lines + 1] = text
    if hl then highlights[#highlights + 1] = { row = #lines - 1, from = 0, to = #lines[#lines], hl = hl } end
    if row then rows[#lines] = row end
  end

  local function heading(text, count)
    if #lines > 0 then add('') end
    add(string.format('%s (%d)', text, count), 'UiTitle')
  end

  add('Mode: ' .. (model.mode or 'the agent has none'), 'UiAccent')

  heading('Waiting for you', #model.waiting)
  for _, ask in ipairs(model.waiting) do
    add('  ◆ ' .. cut(ask.title or ask.tool or 'a question'), 'UiWarn')
  end

  heading('Allowed for this session', #model.grants)
  for _, grant in ipairs(model.grants) do
    add(
      string.format('  ✓ %s  · %s', grant.tool, ago(grant.time)),
      nil,
      { kind = PermissionsView.ROW.grant, grant = grant }
    )
  end
  if #model.grants == 0 then add('  none: "always" answers the agent keeps are saved below', 'UiMuted') end

  heading('Saved by the agent', #model.rules)
  for _, rule in ipairs(model.rules) do
    add(
      string.format('  %-5s %s  · %s', rule.behavior, cut(rule.text), fs.display(rule.path)),
      rule.behavior == permission.BEHAVIOR.deny and 'UiError' or nil,
      { kind = PermissionsView.ROW.rule, rule = rule }
    )
  end
  if not model.supported then add('  this agent does not say where it saves its rules', 'UiMuted') end
  for _, problem in ipairs(model.problems) do
    add('  ! ' .. cut(problem), 'UiWarn')
  end

  local shown = math.min(#model.decisions, PermissionsView.DECISIONS_SHOWN)

  heading('Decisions', #model.decisions)
  for i = #model.decisions, #model.decisions - shown + 1, -1 do
    local entry = model.decisions[i]
    local label = PermissionsView.DECISION_LABELS[entry.kind] or entry.kind

    add(
      string.format(
        '  %-9s %s%s  · %s',
        label,
        cut(entry.title or entry.tool),
        entry.label and ('  ' .. cut(entry.label)) or '',
        ago(entry.time)
      ),
      permission.allows(entry.kind) and nil or 'UiMuted'
    )
  end

  add('')
  add('d revoke or delete · <S-Tab> mode · r refresh · q close', 'UiMuted')

  return lines, highlights, rows
end

function PermissionsView:refresh()
  local lines, highlights, rows = PermissionsView.render(PermissionsView.model(self.session))

  self._rows = rows

  if self._body and self._body:is_valid() then self._body:set_content(lines, highlights) end

  return lines
end

function PermissionsView:row()
  return self._body and self._rows[self._body:get_lnum()] or nil
end

function PermissionsView:revoke(tool)
  return self.session.permissions:revoke(tool)
end

function PermissionsView:delete(rule, confirmed)
  local function remove()
    local ok, why = permission_rules.remove(rule)

    if not ok then console.notify_now('Harness: could not delete ' .. rule.text .. ': ' .. tostring(why), 'warn') end

    self:refresh()

    return ok, why
  end

  if confirmed then return remove() end

  console.select({ 'Delete', 'Keep' }, {
    prompt = string.format('Delete %s "%s" from %s?', rule.behavior, rule.text, fs.display(rule.path)),
  }, function(choice)
    if choice == 'Delete' then remove() end
  end)
end

function PermissionsView:act()
  local row = self:row()

  if not row then return false end

  if row.kind == PermissionsView.ROW.grant then
    self:revoke(row.grant.tool)
  else
    self:delete(row.rule)
  end

  return true
end

function PermissionsView:open()
  local lines = self:refresh()
  local keys = settings.keymaps:get('transcript')

  self._body = LinesComponent({ lines = lines, filetype = 'harness_permissions', wrap = false, border = 'rounded' })
  self._view = View()
  self._view:_render({
    component = self._body,
    mode = 'popup',
    width = '70vw',
    height = math.min(#lines + 2, 30),
  })
  self:refresh()

  self._body:set_keymap('n', 'd', function()
    self:act()
  end, 'Revoke the grant, or delete the saved rule, under the cursor')
  self._body:set_keymap('n', 'r', function()
    self:refresh()
  end, 'Refresh')
  self._body:set_keymap('n', keys.cycle_mode, function()
    self.session:cycle_mode()
  end, 'Next session mode')

  for _, key in ipairs({ 'q', '<Esc>' }) do
    self._body:set_keymap('n', key, function()
      self:close()
    end, 'Close')
  end

  self._unsubscribe = self.session:subscribe(function(event)
    if PermissionsView.REFRESH[event.kind] and self:is_open() then self:refresh() end
  end)

  self:set_state('ready')

  return self
end

function PermissionsView:close()
  if self._unsubscribe then self._unsubscribe() end
  self._unsubscribe = nil

  Surface.close(self)
end

PermissionsView.COMMANDS = {
  revoke = {
    summary = 'Take back a tool allowed for this session, so the user is asked again.',
    params = { { name = 'tool', type = schema.str() } },
    run = function(self, args)
      if not self:revoke(args.tool) then error(args.tool .. ' is not allowed for this session', 0) end
      self:refresh()
    end,
  },
  refresh = {
    summary = 'Read the permissions again.',
    params = {},
    run = function(self)
      self:refresh()
    end,
  },
}

function PermissionsView:snapshot(budget)
  local lines = PermissionsView.render(PermissionsView.model(self.session))

  return string.format('%s: permissions of session %s [%s]\n', self.id, self.session.key, self.state)
    .. compact.text(table.concat(lines, '\n'), budget or compact.BUDGET)
end

return PermissionsView
