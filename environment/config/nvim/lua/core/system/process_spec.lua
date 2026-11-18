local process = require('core.system.process')

describe('core.system.process:', function()
  it('runs a command and reports its exit', function()
    local result = process.system({ 'sh', '-c', 'printf hi' }, { text = true }):wait()

    assert.are.same(0, result.code)
    assert.are.same('hi', result.stdout)
  end)
end)
