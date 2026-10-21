local register = require('core.register')

local eq = assert.are.same

describe('core.register:', function()
  it('sets a register linewise by default and reads it back', function()
    register.set({ 'a', 'b' }, 'z')

    eq('a\nb\n', register.get('z'))
    eq('V', vim.fn.getregtype('z'))
  end)

  it('names the register the command was given', function()
    eq(vim.v.register, register.current())
  end)
end)
