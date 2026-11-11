local compact = require('compact')
local lsp = require('core.lsp')
local sources = require('sources')
local util = require('nvim_mcp.tools.util')

local function diagnostics(args, ctx)
  local buf = (args.path or args.bufnr) and util.resolve(args) or nil
  local items = sources.collect('diagnostics', '', { buf = buf })

  return compact.reply(
    ctx.caller,
    items,
    (compact.locations(items, { empty = 'no diagnostics', offset = args.offset }))
  )
end

local function lsp_clients(args)
  local buf = (args.path or args.bufnr) and util.resolve(args) or nil
  local out = {}

  for _, client in ipairs(lsp.clients({ bufnr = buf })) do
    out[#out + 1] = string.format(
      '%s (id %d)%s',
      client.name,
      client.id,
      client.root_dir and (' root ' .. compact.path(client.root_dir)) or ''
    )
  end

  return #out > 0 and table.concat(out, '\n') or 'no language servers'
end

local function request(buf, method, params)
  if #lsp.clients({ bufnr = buf, method = method }) == 0 then
    util.fail('no language server attached to ' .. util.buf_label(buf) .. ' supports ' .. method)
  end

  local results = {}

  for _, response in pairs(lsp.request_sync(buf, method, params, 5000) or {}) do
    if response.err then util.fail(method .. ': ' .. tostring(response.err.message or response.err)) end
    if response.result ~= nil then results[#results + 1] = response.result end
  end

  return results
end

local function request_at(args, method, extra)
  local buf = util.resolve(args)
  local params = vim.tbl_extend('force', {
    textDocument = { uri = lsp.uri_from_bufnr(buf) },
    position = { line = args.line - 1, character = (args.col or 1) - 1 },
  }, extra or {})

  return request(buf, method, params)
end

local function lsp_hover(args)
  local out = {}

  for _, result in ipairs(request_at(args, 'textDocument/hover')) do
    local contents = result.contents

    if type(contents) == 'table' and contents.value then
      out[#out + 1] = contents.value
    elseif type(contents) == 'string' then
      out[#out + 1] = contents
    end
  end

  return table.concat(out, '\n\n')
end

local AT = util.params(util.TARGET, util.POSITION)
local OFFSET = {
  {
    name = 'offset',
    type = require('nvim_mcp.schema').int({ description = 'Continue from a "… more (offset=N)" line.' }),
    optional = true,
  },
}

return {
  {
    name = 'diagnostics',
    risk = 'read',
    summary = 'LSP and linter diagnostics, errors first, grouped by file with 1-based line:col, for one buffer or every buffer when path and bufnr are omitted.',
    params = util.params(util.TARGET, OFFSET),
    fn = diagnostics,
  },
  {
    name = 'lsp_clients',
    risk = 'read',
    summary = 'Language servers attached to one buffer, or to any buffer when path and bufnr are omitted.',
    params = util.TARGET,
    fn = lsp_clients,
  },
  {
    name = 'lsp_hover',
    risk = 'read',
    summary = 'Hover documentation (type, signature, docs) for the symbol at a position.',
    params = AT,
    fn = lsp_hover,
  },
}
