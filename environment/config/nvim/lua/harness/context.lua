local context = {}

context.TAG = 'editor-context'

local function display_path(buf)
  local name = vim.api.nvim_buf_get_name(buf)

  return name ~= '' and vim.fn.fnamemodify(name, ':~:.') or '[No Name]'
end

function context.capture(win, range)
  local buf = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local parts = {
    string.format('The user is in %s (bufnr %d), line %d, col %d.', display_path(buf), buf, cursor[1], cursor[2] + 1),
  }

  if range then parts[#parts + 1] = string.format('They selected lines %d-%d.', range[1], range[2]) end

  parts[#parts + 1] = 'Editor tools default to this buffer when path and bufnr are omitted.'

  return string.format('<%s>%s</%s>', context.TAG, table.concat(parts, ' '), context.TAG)
end

function context.capture_buffer(buf, range)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then return context.capture(win, range) end
  end

  local mark = vim.api.nvim_buf_get_mark(buf, '"')
  local line, col = mark[1] > 0 and mark[1] or 1, mark[2]
  local parts = {
    string.format('The user is in %s (bufnr %d), line %d, col %d.', display_path(buf), buf, line, col + 1),
  }

  if range then parts[#parts + 1] = string.format('They selected lines %d-%d.', range[1], range[2]) end

  parts[#parts + 1] = 'Editor tools default to this buffer when path and bufnr are omitted.'

  return string.format('<%s>%s</%s>', context.TAG, table.concat(parts, ' '), context.TAG)
end

function context.strip(text)
  local tag = vim.pesc(context.TAG)
  local pattern = '<' .. tag .. '>.-</' .. tag .. '>%s*'

  return (text:gsub(pattern, ''))
end

return context
