local session_search = {}

session_search.CONSECUTIVE = 5
session_search.WORD_START = 3
session_search.CONTAINS = 40
session_search.DESCRIPTION = 0.5
session_search.CORPUS = 0.25
session_search.CORPUS_MAX = 4000

local function word_start(text, at)
  if at == 1 then return true end

  return not text:sub(at - 1, at - 1):match('%w')
end

function session_search.find(text, query)
  text, query = text:lower(), query:lower()

  if query == '' then return 0, {} end

  local from, to = text:find(query, 1, true)

  if from then
    local positions = {}

    for at = from, to do
      positions[#positions + 1] = at
    end

    local score = session_search.CONTAINS + #query * session_search.CONSECUTIVE - math.min(from, 20) * 0.5

    if word_start(text, from) then score = score + session_search.WORD_START * 2 end

    return score, positions
  end

  local positions, at, score, last = {}, 1, 0, nil

  for i = 1, #query do
    local found = text:find(query:sub(i, i), at, true)

    if not found then return nil end

    positions[#positions + 1] = found
    score = score + 1

    if last and found == last + 1 then score = score + session_search.CONSECUTIVE end
    if word_start(text, found) then score = score + session_search.WORD_START end

    last, at = found, found + 1
  end

  return score, positions
end

function session_search.score(row, query, corpus)
  local label, positions = session_search.find(row.label or '', query)

  if label then return label + 100, positions end

  local description = session_search.find(row.description or '', query)

  if description then return description * session_search.DESCRIPTION + 50, nil end

  local body = corpus and corpus(row)

  if body and body ~= '' then
    local found = session_search.find(body:sub(1, session_search.CORPUS_MAX), query)

    if found then return found * session_search.CORPUS, nil end
  end

  return nil
end

function session_search.rank(rows, query, corpus)
  if query == '' then
    for _, row in ipairs(rows) do
      row.match = nil
    end

    return rows
  end

  local scored = {}

  for index, row in ipairs(rows) do
    local score, positions = session_search.score(row, query, corpus)

    row.match = positions

    if score then scored[#scored + 1] = { row = row, score = score, index = index } end
  end

  table.sort(scored, function(a, b)
    if a.score ~= b.score then return a.score > b.score end

    return a.index < b.index
  end)

  local out = {}

  for i, entry in ipairs(scored) do
    out[i] = entry.row
  end

  return out
end

return session_search
