local lsp = {}

function lsp.clients(opts)
  return vim.lsp.get_clients(opts)
end

function lsp.client(id)
  return vim.lsp.get_client_by_id(id)
end

function lsp.request_sync(buf, method, params, timeout)
  return vim.lsp.buf_request_sync(buf, method, params, timeout)
end

function lsp.request_all(buf, method, build_params, handler)
  return vim.lsp.buf_request_all(buf, method, build_params, handler)
end

function lsp.position_params(encoding)
  return vim.lsp.util.make_position_params(0, encoding)
end

function lsp.locations_to_items(locations, encoding)
  return vim.lsp.util.locations_to_items(locations, encoding)
end

function lsp.uri_from_bufnr(buf)
  return vim.uri_from_bufnr(buf)
end

function lsp.uri_to_fname(uri)
  return vim.uri_to_fname(uri)
end

return lsp
