local lazy = require('core.lazy')

local utils_math = lazy('core.utils.math')
local assertion = lazy('core.assertion')

local date = {}

function date.format(time, format)
  format = format or '%d %b %Y'

  local timestamp = tonumber(time)
  if not timestamp or timestamp == 0 then timestamp = os.time() end

  return os.date(format, timestamp)
end

local function days_from_civil(y, m, d)
  y = m <= 2 and y - 1 or y

  local era = math.floor(y / 400)
  local year_of_era = y - era * 400
  local day_of_year = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
  local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year

  return era * 146097 + day_of_era - 719468
end

function date.from_iso(iso)
  if type(iso) ~= 'string' then return nil end

  local y, m, d, hour, min, sec = iso:match('^(%d+)-(%d+)-(%d+)T(%d+):(%d+):?(%d*)')

  if not y then return nil end

  local days = days_from_civil(tonumber(y), tonumber(m), tonumber(d))

  return days * 86400 + tonumber(hour) * 3600 + tonumber(min) * 60 + (tonumber(sec) or 0)
end

function date.age(current_time, now)
  assertion.assert(current_time)
  local time = os.difftime(now or os.time(), current_time)
  local time_divisions = {
    { 1, 'years' },
    { 12, 'months' },
    { 30, 'days' },
    { 24, 'hours' },
    { 60, 'minutes' },
    { 60, 'seconds' },
  }

  for i = 1, #time_divisions do
    time = time / time_divisions[i][1]
  end

  local counter = 1
  local time_division = time_divisions[counter]
  local time_postfix = time_division[2]

  while time < 1 and counter <= #time_divisions do
    time_division = time_divisions[counter]
    local time_boundary = time_division[1]
    time_postfix = time_division[2]
    time = time * time_boundary
    counter = counter + 1
  end

  local unit = utils_math.round(time)
  local how_long = unit <= 1 and time_postfix:sub(1, #time_postfix - 1) or time_postfix

  return {
    unit = unit,
    how_long = how_long,
    display = string.format('%s %s ago', unit, how_long),
  }
end

return date
