local capabilities = require('harness.types.capabilities')

local eq = assert.are.same

describe('harness.types.capabilities:', function()
  it('is false for every ability not given as true', function()
    local record = capabilities.new({ load = true, steer = 'yes' })

    eq(true, record.load)
    eq(false, record.steer)
    eq(false, record.fork)
    eq(#capabilities.NAMES, vim.tbl_count(record))
  end)
end)
