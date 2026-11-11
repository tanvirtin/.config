local fs = require('core.fs')
local Timer = require('core.Timer')
local Window = require('core.Window')
local lsp = require('core.lsp')

local METHODS = {
  definition = 'textDocument/definition',
  references = 'textDocument/references',
  type_definition = 'textDocument/typeDefinition',
  implementation = 'textDocument/implementation',
}

local function position(opts)
  if opts.buf and opts.line then return opts.buf, opts.line - 1, (opts.col or 1) - 1 end

  local win = Window.get_current()
  local cursor = win:get_cursor()

  return win:get_buffer().bufnr, cursor[1] - 1, cursor[2]
end

return {
  name = 'lsp',
  description = 'LSP locations at a position: opts.method is definition, references, type_definition or implementation.',
  methods = METHODS,
  collect = function(query, opts, emit, done)
    local method = METHODS[opts.method or 'definition']

    if not method then
      Timer.schedule(function()
        done('unknown LSP method: ' .. tostring(opts.method))
      end)
      return function() end
    end

    local buf, row, col = position(opts)

    if #lsp.clients({ bufnr = buf, method = method }) == 0 then
      Timer.schedule(function()
        done('no language server attached to this buffer supports ' .. method)
      end)
      return function() end
    end

    local cancelled = false
    local cancel = lsp.request_all(buf, method, function(client)
      local params = lsp.position_params(client.offset_encoding)

      params.position = { line = row, character = col }
      params.textDocument = { uri = lsp.uri_from_bufnr(buf) }
      if method == METHODS.references then params.context = { includeDeclaration = true } end

      return params
    end, function(results)
      if cancelled then return end

      local items = {}

      for client_id, response in pairs(results or {}) do
        local client = lsp.client(client_id)
        local result = response.result

        if result and client then
          if result.uri or result.targetUri then result = { result } end

          for _, entry in ipairs(lsp.locations_to_items(result, client.offset_encoding)) do
            items[#items + 1] = {
              kind = 'location',
              path = entry.filename,
              line = entry.lnum,
              col = entry.col,
              text = entry.text,
              label = string.format('%s:%d  %s', fs.display(entry.filename), entry.lnum, vim.trim(entry.text or '')),
            }
          end
        end
      end

      if query ~= '' then items = require('sources').filter(items, query) end

      emit(items)
      done()
    end)

    return function()
      cancelled = true
      if type(cancel) == 'function' then pcall(cancel) end
    end
  end,
}
