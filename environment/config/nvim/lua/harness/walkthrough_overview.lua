local fs = require('core.fs')
local walkthrough_scope = require('harness.walkthrough_scope')

local walkthrough_overview = {}

walkthrough_overview.MAX_FILES = 3
walkthrough_overview.MAX_MESSAGE = 90
walkthrough_overview.FINDING = { issue = '⚠', suggestion = '✎', nitpick = '·' }
walkthrough_overview.MARK = { understood = '✓', seen = '·', current = '▸', unseen = ' ', uncovered = '○' }

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

function walkthrough_overview.by_file(hunks)
  local groups, by_path = {}, {}

  for _, hunk in ipairs(hunks) do
    local group = by_path[hunk.path]

    if not group then
      group = { path = hunk.path, hunks = {} }
      by_path[hunk.path] = group
      groups[#groups + 1] = group
    end

    group.hunks[#group.hunks + 1] = hunk
  end

  return groups
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

  local understood = 0

  for _, step in ipairs(walkthrough.steps) do
    if step.understood then understood = understood + 1 end
  end

  add(string.format('%d of %d understood', understood, #walkthrough.steps))

  if walkthrough.summary then
    add('')
    vim.list_extend(lines, vim.split(walkthrough.summary, '\n', { plain = true }))
  end

  add('')
  add(scope and '|   | Step | Files | Change |' or '|   | Step | Files |')
  add(scope and '|---|---|---|---|' or '|---|---|---|')

  for index, step in ipairs(walkthrough.steps) do
    local mark = step.understood and walkthrough_overview.MARK.understood
      or index == state.index and walkthrough_overview.MARK.current
      or (seen[index] and walkthrough_overview.MARK.seen or walkthrough_overview.MARK.unseen)
    local title =
      string.format('%d. %s%s', index, step.title or fs.basename(step.path), step.supporting and ' · supporting' or '')
    local row = { mark, cell(title), cell(files(step)) }

    if scope then row[#row + 1] = change(scope, step) end

    add('| ' .. table.concat(row, ' | ') .. ' |', { index = index })
  end

  local findings = {}

  for _, step in ipairs(walkthrough.steps) do
    vim.list_extend(findings, step.findings or {})
  end

  if #findings > 0 then
    local counts = {}

    for _, finding in ipairs(findings) do
      counts[finding.kind] = (counts[finding.kind] or 0) + 1
    end

    local parts = {}

    for _, kind in ipairs({ 'issue', 'suggestion', 'nitpick' }) do
      if counts[kind] then
        parts[#parts + 1] = string.format('%d %s%s', counts[kind], kind, counts[kind] == 1 and '' or 's')
      end
    end

    add('')
    add(string.format('## Findings · %s', table.concat(parts, ', ')))

    for _, finding in ipairs(findings) do
      local message = finding.message

      if #message > walkthrough_overview.MAX_MESSAGE then
        message = message:sub(1, walkthrough_overview.MAX_MESSAGE) .. '…'
      end

      add(
        string.format(
          '- %s %s · %s:%d%s · %s',
          walkthrough_overview.FINDING[finding.kind] or '•',
          finding.kind,
          fs.basename(finding.path),
          finding.line,
          finding.fix and ' · fix' or '',
          message
        ),
        { finding = finding }
      )
    end
  end

  local uncovered = walkthrough.uncovered or {}

  if #uncovered > 0 then
    local groups = walkthrough_overview.by_file(uncovered)

    add('')
    add(string.format('## Not covered · %d in %d', #uncovered, #groups) .. (#groups == 1 and ' file' or ' files'))

    for _, group in ipairs(groups) do
      add(
        string.format(
          '- %s %s · %d hunk%s · %s',
          walkthrough_overview.MARK.uncovered,
          group.path,
          #group.hunks,
          #group.hunks == 1 and '' or 's',
          walkthrough_scope.runs(group.hunks)
        ),
        { hunk = group.hunks[1] }
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
