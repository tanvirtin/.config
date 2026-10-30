local schema = require('nvim_mcp.schema')

local api = {}

local HANDLE_TYPES = { Buffer = true, Window = true, Tabpage = true }

local EXEC = {
  nvim_command = true,
  nvim_exec = true,
  nvim_exec2 = true,
  nvim_cmd = true,
  nvim_input = true,
  nvim_input_mouse = true,
  nvim_feedkeys = true,
  nvim_exec_lua = true,
  nvim_call_function = true,
  nvim_call_dict_function = true,
  nvim_eval = true,
  nvim_paste = true,
}

local TAG = '%*(nvim_[%w_]+)%(%)%*'

local READ_PATTERNS = { '_get_', '_list_', '_is_', '_line_count', '_changedtick', '_strwidth', '_parse_', '_has_' }

function api.schema_type(api_type)
  if HANDLE_TYPES[api_type] or api_type == 'LuaRef' or api_type == 'Integer' then return schema.int() end
  if api_type == 'Float' then return schema.float() end
  if api_type == 'Boolean' then return schema.bool() end
  if api_type == 'String' then return schema.str() end
  if api_type == 'Dict' then return schema.dict(schema.any()) end

  local inner = api_type:match('^ArrayOf%((%w+)')

  if inner then return schema.list(api.schema_type(inner)) end

  return schema.any()
end

local function is_container(api_type)
  return api_type == 'Dict' or api_type == 'Array' or api_type:match('^ArrayOf') ~= nil
end

function api.parse_docs(text)
  local docs = {}
  local lines = {}

  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    lines[#lines + 1] = line
  end

  local i = 1

  while i <= #lines do
    local name = lines[i]:match(TAG)

    if name then
      local j = i + 1

      while j <= #lines and not lines[j]:match('^%s+%S') and not lines[j]:match(TAG) do
        j = j + 1
      end

      local paragraph = {}

      while j <= #lines and lines[j]:match('^%s+%S') and not lines[j]:match(TAG) do
        local body = lines[j]:gsub('^%s+', '')

        if #paragraph == 0 and body:match('^{') then body = body:match('^[^)]*%)%s*(.*)$') or '' end

        if body ~= '' then paragraph[#paragraph + 1] = body end
        j = j + 1
      end

      local summary = table.concat(paragraph, ' ')

      if #summary > 300 then summary = summary:sub(1, 297) .. '...' end

      docs[name] = summary
      i = j
    else
      i = i + 1
    end
  end

  return docs
end

function api.risk(name)
  if EXEC[name] then return 'exec' end

  for _, pattern in ipairs(READ_PATTERNS) do
    if name:find(pattern, 1, true) then return 'read' end
  end

  return 'write'
end

function api.entries(functions, docs)
  docs = docs or {}
  local out = {}

  for _, fn in ipairs(functions or {}) do
    if fn.name:sub(1, 5) == 'nvim_' then
      local params = {}

      for index, p in ipairs(fn.parameters or {}) do
        local api_type, name = p[1], p[2]

        params[index] = {
          name = name,
          api_type = api_type,
          type = api.schema_type(api_type),
          optional = is_container(api_type),
        }
      end

      local names = vim.tbl_map(function(p)
        return p.name
      end, params)

      out[#out + 1] = {
        name = fn.name,
        kind = 'rpc',
        params = params,
        risk = api.risk(fn.name),
        summary = docs[fn.name] or ('Neovim API function ' .. fn.name .. '(' .. table.concat(names, ', ') .. ')'),
      }
    end
  end

  table.sort(out, function(a, b)
    return a.name < b.name
  end)

  return out
end

function api.positional_args(entry, args)
  local ok, value = schema.validate(schema.model(entry.params), args or {})

  if not ok then
    local names = vim.tbl_map(function(p)
      return p.name
    end, entry.params)

    return nil,
      string.format(
        'invalid arguments for %s: %s (parameters: %s)',
        entry.name,
        schema.format_errors(value),
        table.concat(names, ', ')
      )
  end

  local out = {}

  for index, p in ipairs(entry.params) do
    local arg = value[p.name]

    if arg == nil then arg = is_container(p.api_type) and {} or 0 end

    if p.api_type == 'Dict' and next(arg) == nil then arg = vim.empty_dict() end

    out[index] = arg
  end

  return out
end

return api
