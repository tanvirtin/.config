local lazy = require('core.lazy')

local fs = lazy('core.fs')
local Timer = lazy('core.Timer')
local event = lazy('core.event')
local Object = lazy('core.Object')
local console = lazy('core.console')
local process = lazy('core.process')
local FileWatch = lazy('core.FileWatch')
local settings = lazy('harness.settings.skills')
local session_store = lazy('harness.session_store')

local SkillSync = Object:extend()

SkillSync.GROUP = 'harness_skills'

function SkillSync:constructor()
  return { _group = nil, _dispose = nil, _stamp = nil, _running = false }
end

function SkillSync:artifacts()
  return fs.expand(settings:get('artifacts'))
end

function SkillSync:stamp()
  local parts = {}

  for _, path in ipairs(fs.glob(fs.joinpath(self:artifacts(), '**', '*.yml'))) do
    parts[#parts + 1] = path .. '=' .. FileWatch.fingerprint(path)
  end

  return table.concat(parts, '|')
end

function SkillSync:sync()
  local command = settings:get('command')

  if self._running or fs.exepath(command[1]) == '' then return self end

  local stamp = self:stamp()

  if stamp == self._stamp then return self end

  self._running = true
  self._stamp = stamp

  process.system(command, { text = true }, function(result)
    Timer.schedule(function()
      self._running = false

      if result.code ~= 0 then console.debug.error('skill sync: ' .. (result.stderr or result.stdout or '')) end
    end)
  end)

  return self
end

function SkillSync:register_events()
  self:cleanup()

  local sync = function()
    self:sync()
  end

  self._group = event.augroup(SkillSync.GROUP)
  self._group.on('FocusGained', sync).on('BufWritePost', sync, { pattern = self:artifacts() .. '/*' })
  self._dispose = session_store.on(session_store.EVENT.start, sync)

  Timer.defer(0, sync)

  return self
end

function SkillSync:cleanup()
  if self._group then self._group.dispose() end
  if self._dispose then self._dispose() end

  self._group, self._dispose = nil, nil
end

return SkillSync
