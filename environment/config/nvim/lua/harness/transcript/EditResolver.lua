local EditResolver = {}

EditResolver.KIND = { applied = 'applied', pending = 'pending', created = 'created', snippet = 'snippet' }

local function lines_of(text)
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

EditResolver.lines_of = lines_of

local function aligned(text, at, length)
  local before = at == 1 or text:sub(at - 1, at - 1) == '\n'
  local after = at + length > #text or text:sub(at + length, at + length) == '\n'

  return before and after
end

local function locate(text, needle)
  local first, from = nil, 1

  while true do
    local at = text:find(needle, from, true)

    if not at then return first end
    if aligned(text, at, #needle) then return at end

    first = first or at
    from = at + 1
  end
end

EditResolver.locate = locate

function EditResolver.replace(text, from, length, with)
  return text:sub(1, from - 1) .. with .. text:sub(from + length)
end

function EditResolver.resolve(diff, file, opts)
  local old, new = (diff.old or ''):gsub('\n$', ''), (diff.new or ''):gsub('\n$', '')
  local text = table.concat(file or {}, '\n')

  if opts and opts.failed then
    return { kind = EditResolver.KIND.snippet, old_lines = lines_of(old), new_lines = lines_of(new) }
  end

  if new ~= '' then
    local at = locate(text, new)

    if at then
      if old == '' and at == 1 and #new >= #text then
        return { kind = EditResolver.KIND.created, old_lines = {}, new_lines = lines_of(text) }
      end

      return {
        kind = EditResolver.KIND.applied,
        old_lines = lines_of(EditResolver.replace(text, at, #new, old)),
        new_lines = file,
      }
    end
  end

  if old ~= '' then
    local at = locate(text, old)

    if at then
      return {
        kind = EditResolver.KIND.pending,
        old_lines = file,
        new_lines = lines_of(EditResolver.replace(text, at, #old, new)),
      }
    end
  end

  return { kind = EditResolver.KIND.snippet, old_lines = lines_of(old), new_lines = lines_of(new) }
end

function EditResolver.whole(resolved)
  return resolved.kind ~= EditResolver.KIND.snippet
end

return EditResolver
