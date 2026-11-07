local lsp = {}

function lsp.supports(bufnr, method)
  return #vim.lsp.get_clients({ bufnr = bufnr, method = method }) > 0
end

function lsp.uri(bufnr)
  return vim.uri_from_bufnr(bufnr)
end

function lsp.path(uri)
  return vim.uri_to_fname(uri)
end

function lsp.request(bufnr, method, params, done)
  vim.lsp.buf_request_all(bufnr, method, params, function(responses)
    local results, err = {}, nil

    for _, response in pairs(responses or {}) do
      if response.err then err = response.err.message or tostring(response.err) end
      if type(response.result) == 'table' then vim.list_extend(results, response.result) end
    end

    done(results, err)
  end)
end

return lsp
