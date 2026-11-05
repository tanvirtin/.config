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

function buffers.listed()
  local result = {}

  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    result[#result + 1] = {
      bufnr = info.bufnr,
      name = info.name,
      line = info.lnum,
      changed = info.changed == 1,
      lastused = info.lastused,
    }
  end

  return result
end

function buffers.add(path)
  return Buffer(vim.fn.bufadd(path))
end

function buffers.load(path)
  local bufnr = vim.fn.bufadd(path)

  vim.fn.bufload(bufnr)
  vim.bo[bufnr].buflisted = true

  return Buffer(bufnr)
end

function buffers.find(path)
  local target = vim.fs.normalize(path)
  local real = vim.fn.resolve(target)

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)

    if name ~= '' and (name == target or vim.fn.resolve(name) == real) then return Buffer(bufnr) end
  end
end

function buffers.lines_of(path)
  local buffer = buffers.find(path)

  if buffer and buffer:is_loaded() then return buffer:get_lines() end
  if vim.fn.filereadable(path) == 1 then return vim.fn.readfile(path) end

  return {}
end

function buffers.checktime()
  pcall(vim.cmd.checktime)
end

return buffers
