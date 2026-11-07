local fs = require('core.fs')
local walkthrough_scope = require('harness.walkthrough_scope')

local walkthrough_overview = {}

walkthrough_overview.MAX_FILES = 3
walkthrough_overview.MARK = { seen = '✓', current = '▸', unseen = ' ', uncovered = '○' }

local function cell(text)
  return (text:gsub('|', '\\|'))
end

local function ranges(step)
  return step.ranges and #step.ranges > 0 and step.ranges or { step }
end

local function files(step)
  local names, seen = {}, {}

  for _, range in ipairs(ranges(step)) do
    local name = fs.basename(range.path)

    if not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end

  local shown = vim.list_slice(names, 1, walkthrough_overview.MAX_FILES)
  local more = #names - #shown

  return table.concat(shown, ', ') .. (more > 0 and string.format(' +%d', more) or '')
end

local function change(scope, step)
  local added, removed = 0, 0

  for _, hunk in ipairs(walkthrough_scope.covered(scope, step)) do
    added, removed = added + hunk.added, removed + hunk.removed
  end

  return string.format('+%d -%d', added, removed)
end

local function header(scope)
  local added, removed, count = 0, 0, 0

  for _, file in ipairs(scope.files) do
    for _, hunk in ipairs(file.hunks) do
      added, removed, count = added + hunk.added, removed + hunk.removed, count + 1
    end
  end

  return string.format(
    '`%s..%s` · %d commit%s · %d file%s · %d hunk%s · +%d -%d',
    scope.base:sub(1, 7),
    scope.head:sub(1, 7),
    #scope.commits,
    #scope.commits == 1 and '' or 's',
    #scope.files,
    #scope.files == 1 and '' or 's',
    count,
    count == 1 and '' or 's',
    added,
    removed
  )
end

function walkthrough_overview.render(walkthrough, state)
  state = state or {}

  local scope = walkthrough.scope
  local seen = state.seen or {}
  local lines, targets = { '# ' .. walkthrough.title }, {}

  local function add(line, target)
    lines[#lines + 1] = line

    if target then targets[#lines] = target end
  end

  if scope then add(header(scope)) end

  if walkthrough.summary then
    add('')
    vim.list_extend(lines, vim.split(walkthrough.summary, '\n', { plain = true }))
  end

  add('')
  add(scope and '|   | Step | Files | Change |' or '|   | Step | Files |')
  add(scope and '|---|---|---|---|' or '|---|---|---|')

  for index, step in ipairs(walkthrough.steps) do
    local mark = index == state.index and walkthrough_overview.MARK.current
      or (seen[index] and walkthrough_overview.MARK.seen or walkthrough_overview.MARK.unseen)
    local title =
      string.format('%d. %s%s', index, step.title or fs.basename(step.path), step.supporting and ' · supporting' or '')
    local row = { mark, cell(title), cell(files(step)) }

    if scope then row[#row + 1] = change(scope, step) end

    add('| ' .. table.concat(row, ' | ') .. ' |', { index = index })
  end

  local uncovered = walkthrough.uncovered or {}

  if #uncovered > 0 then
    add('')
    add('## Not covered')

    for _, hunk in ipairs(uncovered) do
      add(
        string.format(
          '- %s %s %s:%d-%d',
          walkthrough_overview.MARK.uncovered,
          hunk.id or '',
          hunk.path,
          hunk.first,
          hunk.last
        ),
        { hunk = hunk }
      )
    end
  end

  if state.keys then
    add('')
    add(string.format('`%s` open · `%s` start · `%s` end', state.keys.open, state.keys.next, state.keys.stop))
  end

  return { lines = lines, targets = targets }
end

function walkthrough_overview.first_target(view)
  local first

  for row in pairs(view.targets) do
    first = math.min(first or row, row)
  end

  return first
end

return walkthrough_overview
