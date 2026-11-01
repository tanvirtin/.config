local tone = {}

tone.ACCENT = 'Accent'
tone.WARN = 'Warn'
tone.ERROR = 'Error'
tone.INFO = 'Info'

tone.ALL = { tone.ACCENT, tone.WARN, tone.ERROR, tone.INFO }

tone.SOURCE = {
  [tone.ACCENT] = 'UiAccent',
  [tone.WARN] = 'UiWarn',
  [tone.ERROR] = 'UiError',
  [tone.INFO] = 'UiInfo',
}

local function known(name)
  assert(tone.SOURCE[name], 'unknown tone: ' .. tostring(name))

  return name
end

function tone.surface(name)
  return 'UiSurface' .. known(name)
end

function tone.rail(name)
  return 'UiRail' .. known(name)
end

function tone.flash(name, step)
  return 'UiFlash' .. known(name) .. step
end

function tone.pulse(name, index)
  return 'UiPulse' .. (name and known(name) or '') .. index
end

return tone
