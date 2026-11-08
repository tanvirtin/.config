local diagnostic = {}

diagnostic.SEVERITY = vim.diagnostic.severity

function diagnostic.set(namespace, bufnr, items)
  vim.diagnostic.set(namespace, bufnr, items)
end

function diagnostic.reset(namespace, bufnr)
  vim.diagnostic.reset(namespace, bufnr)
end

function diagnostic.get(namespace, bufnr)
  return vim.diagnostic.get(bufnr, { namespace = namespace })
end

return diagnostic
