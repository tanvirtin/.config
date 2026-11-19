local edit_text = {}

function edit_text.lines_of(text)
  if text == '' then return {} end

  local lines, from = {}, 1

  text = text:gsub('\n$', '')

  while true do
    local at = text:find('\n', from, true)

    if not at then break end

    lines[#lines + 1] = text:sub(from, at - 1)
    from = at + 1
  end

  lines[#lines + 1] = text:sub(from)

  return lines
end

function edit_text.aligned(text, at, length)
  local before = at == 1 or text:sub(at - 1, at - 1) == '\n'
  local after = at + length > #text or text:sub(at + length, at + length) == '\n'

  return before and after
end

function edit_text.locate(text, needle)
  local first, from = nil, 1

  while true do
    local at = text:find(needle, from, true)

    if not at then return first end
    if edit_text.aligned(text, at, #needle) then return at end

    first = first or at
    from = at + 1
  end
end

function edit_text.replace(text, from, length, with)
  return text:sub(1, from - 1) .. with .. text:sub(from + length)
end

function edit_text.trimmed(text)
  return ((text or ''):gsub('\n$', ''))
end

return edit_text
