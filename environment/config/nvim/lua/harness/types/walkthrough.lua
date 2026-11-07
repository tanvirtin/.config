local fs = require('core.fs')
local dataclass = require('core.dataclass')

local walkthrough = {}

walkthrough.MAX_STEPS = 60

walkthrough.MAX_RANGES = 12

walkthrough.Range = dataclass.define('WalkthroughRange', {
  path = { type = 'string', required = true },
  line = { type = 'number', required = true },
  end_line = { type = 'number', required = true },
})

walkthrough.Step = dataclass.define('WalkthroughStep', {
  path = { type = 'string', required = true },
  line = { type = 'number', required = true },
  end_line = { type = 'number', required = true },
  ranges = { type = 'table', required = true },
  title = { type = 'string' },
  note = { type = 'string', default = '' },
  supporting = { type = 'boolean', default = false },
  understood = { type = 'boolean', default = false },
})

walkthrough.Walkthrough = dataclass.define('Walkthrough', {
  title = { type = 'string', required = true },
  summary = { type = 'string' },
  steps = { type = 'table', required = true },
  source = { type = 'string' },
  rev = { type = 'string' },
  base = { type = 'string' },
  root = { type = 'string' },
  scope = { type = 'table' },
  uncovered = { type = 'table' },
})

function walkthrough.absolute(path, dir)
  local first = path:sub(1, 1)

  if first == '~' or first == '$' then path = fs.expand(path) end

  if path:sub(1, 1) == '/' then return fs.normalize(path) end

  return fs.normalize(fs.joinpath(dir or fs.cwd(), path))
end

function walkthrough.range(fields, dir, check)
  if type(fields.path) ~= 'string' or fields.path == '' then return nil, 'a step needs a path' end

  local line = math.max(math.floor(tonumber(fields.line) or 1), 1)
  local path = walkthrough.absolute(fields.path, dir)

  local found = check and check(path) or (not check and fs.exists(path) and not fs.is_dir(path))

  if not found then return nil, 'no file ' .. fields.path end

  return walkthrough.Range({
    path = path,
    line = line,
    end_line = math.max(math.floor(tonumber(fields.end_line) or line), line),
  })
end

function walkthrough.step(fields, dir, check)
  local given = type(fields.ranges) == 'table' and #fields.ranges > 0 and fields.ranges or { fields }

  if #given > walkthrough.MAX_RANGES then
    return nil, string.format('a step holds at most %d ranges; split it into more steps', walkthrough.MAX_RANGES)
  end

  local ranges = {}

  for index, spec in ipairs(given) do
    local range, err = walkthrough.range({
      path = spec.path or fields.path,
      line = spec.line,
      end_line = spec.end_line,
    }, dir, check)

    if not range then return nil, #given > 1 and string.format('range %d: %s', index, err) or err end

    ranges[index] = range
  end

  local first = ranges[1]

  return walkthrough.Step({
    path = first.path,
    line = first.line,
    end_line = first.end_line,
    ranges = ranges,
    title = type(fields.title) == 'string' and fields.title ~= '' and fields.title or nil,
    note = type(fields.note) == 'string' and fields.note or '',
    supporting = fields.supporting == true,
  })
end

function walkthrough.ordered(steps)
  local core, supporting = {}, {}

  for _, step in ipairs(steps) do
    local into = step.supporting and supporting or core

    into[#into + 1] = step
  end

  return vim.list_extend(core, supporting)
end

function walkthrough.parse(args, dir, opts)
  if type(args) ~= 'table' or type(args.steps) ~= 'table' or #args.steps == 0 then
    return nil, 'a walkthrough needs at least one step'
  end

  if #args.steps > walkthrough.MAX_STEPS then
    return nil, string.format('a walkthrough holds at most %d steps; split it in two', walkthrough.MAX_STEPS)
  end

  local steps = {}

  for index, fields in ipairs(args.steps) do
    local step, err = walkthrough.step(fields, dir, opts and opts.check)

    if not step then return nil, string.format('step %d: %s', index, err) end

    steps[index] = step
  end

  return walkthrough.Walkthrough({
    title = type(args.title) == 'string' and args.title ~= '' and args.title or 'Walkthrough',
    summary = type(args.summary) == 'string' and args.summary ~= '' and args.summary or nil,
    steps = walkthrough.ordered(steps),
    source = type(args.source) == 'string' and args.source or nil,
    rev = opts and opts.rev or nil,
    base = opts and opts.base or nil,
    root = opts and opts.root or nil,
    scope = opts and opts.scope or nil,
  })
end

return walkthrough
