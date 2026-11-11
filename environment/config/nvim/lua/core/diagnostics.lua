local diagnostics = {}

function diagnostics.get(buf)
  return vim.diagnostic.get(buf)
end

return diagnostics
