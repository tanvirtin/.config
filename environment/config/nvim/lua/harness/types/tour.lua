local fs = require('core.fs')
local dataclass = require('core.dataclass')

local tour = {}

tour.MAX_STEPS = 60

tour.Step = dataclass.define('TourStep', {
  path = { type = 'string', required = true },
  line = { type = 'number', required = true },
  end_line = { type = 'number', required = true },
  title = { type = 'string' },
  note = { type = 'string', default = '' },
})

tour.Tour = dataclass.define('Tour', {
  title = { type = 'string', required = true },
  summary = { type = 'string' },
  steps = { type = 'table', required = true },
  source = { type = 'string' },
})

local function absolute(path, dir)
  local first = path:sub(1, 1)

  if first == '~' or first == '$' then path = fs.expand(path) end

  if path:sub(1, 1) == '/' then return fs.normalize(path) end

  return fs.normalize(fs.joinpath(dir or fs.cwd(), path))
end

function tour.step(fields, dir)
  if type(fields.path) ~= 'string' or fields.path == '' then return nil, 'a step needs a path' end

  local line = math.max(math.floor(tonumber(fields.line) or 1), 1)
  local path = absolute(fields.path, dir)

  if not fs.exists(path) or fs.is_dir(path) then return nil, 'no file ' .. fields.path end

  return tour.Step({
    path = path,
    line = line,
    end_line = math.max(math.floor(tonumber(fields.end_line) or line), line),
    title = type(fields.title) == 'string' and fields.title ~= '' and fields.title or nil,
    note = type(fields.note) == 'string' and fields.note or '',
  })
end

function tour.parse(args, dir)
  if type(args) ~= 'table' or type(args.steps) ~= 'table' or #args.steps == 0 then
    return nil, 'a tour needs at least one step'
  end

  if #args.steps > tour.MAX_STEPS then
    return nil, string.format('a tour holds at most %d steps; split it in two', tour.MAX_STEPS)
  end

  local steps = {}

  for index, fields in ipairs(args.steps) do
    local step, err = tour.step(fields, dir)

    if not step then return nil, string.format('step %d: %s', index, err) end

    steps[index] = step
  end

  return tour.Tour({
    title = type(args.title) == 'string' and args.title ~= '' and args.title or 'Tour',
    summary = type(args.summary) == 'string' and args.summary ~= '' and args.summary or nil,
    steps = steps,
    source = type(args.source) == 'string' and args.source or nil,
  })
end

return tour
