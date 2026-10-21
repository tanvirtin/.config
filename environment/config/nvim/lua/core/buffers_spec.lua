local buffers = require('core.buffers')

local eq = assert.are.same

describe('core.buffers:', function()
  describe('lines_of', function()
    it('prefers the loaded buffer, so unsaved edits count', function()
      local path = vim.fn.tempname()

      vim.fn.writefile({ 'disk' }, path)

      local buf = vim.fn.bufadd(path)

      vim.fn.bufload(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'edited' })

      eq({ 'edited' }, buffers.lines_of(path))

      vim.api.nvim_buf_delete(buf, { force = true })
      eq({ 'disk' }, buffers.lines_of(path))
      os.remove(path)
    end)

    it('is empty for a missing file', function()
      eq({}, buffers.lines_of(vim.fn.tempname()))
    end)
  end)
end)
