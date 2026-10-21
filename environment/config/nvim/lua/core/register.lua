local register = {}

function register.current()
  return vim.v.register
end

function register.set(lines, name, kind)
  vim.fn.setreg(name or vim.v.register, lines, kind or 'l')
end

function register.get(name)
  return vim.fn.getreg(name or vim.v.register)
end

return register
