local graphics = require('core.graphics')

local eq = assert.are.same

describe('core.graphics:', function()
  before_each(function()
    graphics.reset()
  end)

  it('is unsupported where no terminal answers, such as a headless editor', function()
    eq(false, graphics.supported())
  end)

  it('hands out a fresh image id each time', function()
    local first = graphics.id()

    eq(first + 1, graphics.id())
    assert.is_true(first > graphics.BASE)
  end)

  it('sends pixels through a temporary file, placed at a cell, without moving the cursor', function()
    local sequence = graphics.sequence(7, 'abcdefgh', 2, 1, { row = 3, col = 5, cols = 4, rows = 2, z = -1 })
    local control, payload = sequence:match('\27_G([^;]*);([^\27]*)\27\\')
    local path = vim.base64.decode(payload)

    eq('a=T,i=7,p=1,f=32,s=2,v=1,t=t,c=4,r=2,z=-1,C=1,q=2', control)
    assert.is_truthy(path:find('tty-graphics-protocol', 1, true))
    eq({ 'abcdefgh' }, vim.fn.readfile(path))
    assert.is_truthy(sequence:find('\27[3;5H', 1, true))
    eq('\27[?2026h\0277', sequence:sub(1, 10))
    eq('\0278\27[?2026l', sequence:sub(-10))
  end)

  it('frees the image it replaces in the same update', function()
    local sequence = graphics.sequence(8, 'abcd', 1, 1, { row = 1, col = 1, cols = 1, rows = 1 }, 7)

    assert.is_truthy(sequence:find('\27_Ga=d,d=I,i=7,q=2\27\\', 1, true))
  end)

  it('places an uploaded image on a virtual placement', function()
    local control = graphics.upload_sequence(7, 'abcdefgh', 2, 1, 4, 2):match('\27_G([^;]*);')

    eq('a=T,U=1,i=7,f=32,s=2,v=1,t=t,c=4,r=2,q=2', control)
  end)

  it('uploads without its own synchronized update, which would end the editor frame it lands in', function()
    local sequence = graphics.upload_sequence(7, 'abcdefgh', 2, 1, 4, 2)

    eq('\27_G', sequence:sub(1, 3))
    eq(nil, sequence:find('2026', 1, true))
  end)

  it('places every upload again, so an animated image keeps resolving its placeholder', function()
    local first = graphics.upload_sequence(7, 'abcdefgh', 2, 1, 4, 2):match('\27_G([^;]*);')
    local second = graphics.upload_sequence(7, 'abcdefgh', 2, 1, 4, 2):match('\27_G([^;]*);')

    eq(first, second)
    eq('a=T,U=1,i=7,f=32,s=2,v=1,t=t,c=4,r=2,q=2', second)
  end)
end)
