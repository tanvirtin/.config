local quickfix = {}

function quickfix.set(items, opts)
  opts = opts or {}

  local entries = {}

  for _, item in ipairs(items) do
    entries[#entries + 1] = {
      filename = item.path,
      lnum = item.line or 1,
      col = item.col or 1,
      text = item.text or '',
    }
  end

  vim.fn.setqflist({}, ' ', { title = opts.title, items = entries })

  if opts.open then vim.cmd('copen') end

  return #entries
end

function quickfix.get()
  local list = vim.fn.getqflist({ title = 1, items = 1 })
  local items = {}

  for _, entry in ipairs(list.items or {}) do
    items[#items + 1] = {
      path = vim.api.nvim_buf_get_name(entry.bufnr),
      line = entry.lnum,
      col = entry.col,
      text = entry.text,
    }
  end

  return { title = list.title, items = items }
end

return quickfix
