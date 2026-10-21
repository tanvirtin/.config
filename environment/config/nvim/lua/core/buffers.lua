local lazy = require('core.lazy')

local Buffer = lazy('core.Buffer')

local buffers = {}

function buffers.list()
  local bufnrs = vim.api.nvim_list_bufs()
  local result = {}
  for _, bufnr in ipairs(bufnrs) do
    result[#result + 1] = Buffer(bufnr)
  end
  return result
end

function buffers.lines_of(path)
  local bufnr = vim.fn.bufnr(path)

  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) end
  if vim.fn.filereadable(path) == 1 then return vim.fn.readfile(path) end

  return {}
end

function buffers.checktime()
  pcall(vim.cmd.checktime)
end

return buffers
