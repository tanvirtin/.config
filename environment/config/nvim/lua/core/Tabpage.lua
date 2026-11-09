local event = require('core.event')
local Buffer = require('core.Buffer')
local Object = require('core.Object')
local Window = require('core.Window')

local Tabpage = Object:extend()

Tabpage.NAME = 'name'

local opened = 0

function Tabpage:constructor(handle)
  return { handle = handle or vim.api.nvim_get_current_tabpage(), owned = {}, closers = {}, group = nil }
end

function Tabpage.current()
  return Tabpage(vim.api.nvim_get_current_tabpage())
end

function Tabpage.count()
  return #vim.api.nvim_list_tabpages()
end

function Tabpage.open(opts)
  opts = opts or {}

  vim.cmd('tabnew')

  local tab = Tabpage.current()
  local blank = tab:window():get_buffer()

  blank:set_option('bufhidden', 'wipe')

  if opts.name then tab:set_name(opts.name) end

  return tab
end

function Tabpage:is_valid()
  return vim.api.nvim_tabpage_is_valid(self.handle)
end

function Tabpage:is_current()
  return self:is_valid() and vim.api.nvim_get_current_tabpage() == self.handle
end

function Tabpage:is_same(other)
  return other ~= nil and other.handle == self.handle
end

function Tabpage:number()
  return vim.api.nvim_tabpage_get_number(self.handle)
end

function Tabpage:focus()
  if self:is_valid() and not self:is_current() then vim.api.nvim_set_current_tabpage(self.handle) end

  return self
end

function Tabpage:window()
  return Window(vim.api.nvim_tabpage_get_win(self.handle))
end

function Tabpage:windows()
  if not self:is_valid() then return {} end

  return vim.tbl_map(Window, vim.api.nvim_tabpage_list_wins(self.handle))
end

function Tabpage:contains(window)
  return window ~= nil and window:is_valid() and window:get_tab() == self.handle
end

function Tabpage:set_name(name)
  vim.api.nvim_tabpage_set_var(self.handle, Tabpage.NAME, name)

  return self
end

function Tabpage:get_name()
  local ok, name = pcall(vim.api.nvim_tabpage_get_var, self.handle, Tabpage.NAME)

  return ok and name or nil
end

function Tabpage:own(buffer)
  self.owned[buffer.bufnr] = true

  return buffer
end

function Tabpage:_release()
  for bufnr in pairs(self.owned) do
    if Buffer.exists(bufnr) and #vim.fn.win_findbuf(bufnr) == 0 then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end

  self.owned = {}

  if self.group then
    self.group.dispose()
    self.group = nil
  end
end

function Tabpage:_settle()
  if self:is_valid() then return end

  local closers = self.closers

  self.closers = {}
  self:_release()

  for _, closer in ipairs(closers) do
    closer(self)
  end
end

function Tabpage:on_close(callback)
  self.closers[#self.closers + 1] = callback

  if not self.group then
    opened = opened + 1
    self.group = event.augroup('core.tabpage.' .. self.handle .. '.' .. opened)
    self.group.on('TabClosed', function()
      self:_settle()
    end)
  end

  return self
end

function Tabpage:close()
  if not self:is_valid() then return false end

  if Tabpage.count() == 1 then
    self:_release()
    return false
  end

  local ok = pcall(vim.cmd, self:number() .. 'tabclose')

  if ok then self:_settle() end

  return ok
end

return Tabpage
