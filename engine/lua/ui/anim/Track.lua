local motion = require('ui.motion')

local Track = {}

Track.__index = Track

local function key_of(raw)
  local at, value, ease = raw[1], raw[2], raw[3]

  if type(at) ~= 'number' or type(value) ~= 'number' then
    error('a keyframe is [ms, value] or [ms, value, ease], with numbers', 0)
  end

  if ease ~= nil and not motion.ease[ease] then
    error(string.format('unknown ease %s (%s)', tostring(ease), table.concat(Track.eases(), ', ')), 0)
  end

  return { at = at, value = value, ease = motion.ease[ease or 'linear'] }
end

function Track.eases()
  local names = vim.tbl_keys(motion.ease)

  table.sort(names)

  return names
end

function Track.new(raw, opts)
  if type(raw) ~= 'table' or #raw == 0 then error('a track needs at least one keyframe', 0) end

  local keys = vim.tbl_map(key_of, raw)

  table.sort(keys, function(a, b)
    return a.at < b.at
  end)

  return setmetatable({ keys = keys, loop = opts and opts.loop or false }, Track)
end

function Track:duration()
  return self.keys[#self.keys].at
end

function Track:at(ms)
  local keys, last = self.keys, self.keys[#self.keys]

  if self.loop and last.at > 0 then ms = ms % last.at end
  if ms <= keys[1].at then return keys[1].value end
  if ms >= last.at then return last.value end

  for i = 2, #keys do
    local to = keys[i]

    if ms <= to.at then
      local from = keys[i - 1]
      local span = to.at - from.at

      return motion.lerp(from.value, to.value, to.ease(span > 0 and (ms - from.at) / span or 1))
    end
  end

  return last.value
end

return Track
