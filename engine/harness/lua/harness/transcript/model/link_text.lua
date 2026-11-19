local link_text = {}

local FENCE = '^[>%s]*([`~][`~][`~])'

local function link_at(line, i)
  if line:sub(i - 1, i - 1) == '!' or line:sub(i - 1, i - 1) == '\\' then return nil end

  local label, target, finish = line:match('^%[([^%]]+)%]%(<([^>]+)>%)()', i)

  if not label then
    label, target, finish = line:match('^%[([^%]]+)%]%(([^%s%)]+)%)()', i)
  end

  if not label then return nil end

  return label, target, finish
end

local function strip_line(line, row, links)
  local out, length, i = {}, 0, 1

  local function append(text)
    out[#out + 1] = text
    length = length + #text
  end

  while i <= #line do
    local c = line:sub(i, i)

    if c == '`' then
      local ticks = line:match('^`+', i)
      local close = line:find(ticks, i + #ticks, true)
      local stop = close and (close + #ticks - 1) or #line

      append(line:sub(i, stop))
      i = stop + 1
    elseif c == '[' then
      local label, target, finish = link_at(line, i)

      if label then
        links[#links + 1] = { row = row, col = length, end_col = length + #label, target = target, label = label }
        append(label)
        i = finish
      else
        append(c)
        i = i + 1
      end
    else
      local stop = line:find('[`%[]', i) or (#line + 1)

      append(line:sub(i, stop - 1))
      i = stop
    end
  end

  return table.concat(out)
end

function link_text.strip(lines)
  local out, links, fence = {}, {}, nil

  for row, line in ipairs(lines) do
    local marker = line:match(FENCE)

    if marker and (not fence or marker:sub(1, 1) == fence) then
      fence = not fence and marker:sub(1, 1) or nil
      out[row] = line
    elseif fence or not line:find('[', 1, true) then
      out[row] = line
    else
      out[row] = strip_line(line, row, links)
    end
  end

  return out, links
end

function link_text.restore(lines, links)
  local out = vim.list_slice(lines)
  local by_row = {}

  for _, link in ipairs(links or {}) do
    by_row[link.row] = by_row[link.row] or {}
    table.insert(by_row[link.row], 1, link)
  end

  for row, list in pairs(by_row) do
    local line = out[row]

    table.sort(list, function(a, b)
      return a.col > b.col
    end)

    for _, link in ipairs(list) do
      line = line:sub(1, link.col) .. '[' .. link.label .. '](' .. link.target .. ')' .. line:sub(link.end_col + 1)
    end

    out[row] = line
  end

  return out
end

function link_text.at(links, row, col)
  for _, link in ipairs(links or {}) do
    if link.row == row and col >= link.col and col < link.end_col then return link end
  end
end

return link_text
