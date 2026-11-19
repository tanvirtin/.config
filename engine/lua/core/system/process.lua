local process = {}

function process.system(cmd, opts, on_exit)
  return vim.system(cmd, opts, on_exit)
end

return process
