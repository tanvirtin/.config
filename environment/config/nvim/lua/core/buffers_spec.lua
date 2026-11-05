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

    it('never reads a buffer whose name only contains the path', function()
      local path = vim.fn.tempname() .. '.lua'

      vim.fn.writefile({ 'disk' }, path)

      local buf = vim.fn.bufadd(path .. '.bak')

      vim.fn.bufload(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'other' })

      eq({ 'disk' }, buffers.lines_of(path))

      vim.api.nvim_buf_delete(buf, { force = true })
      os.remove(path)
    end)
  end)

  describe('find', function()
    it('finds the buffer named by a path, and nothing for others', function()
      local path = vim.fn.tempname()
      local buf = vim.fn.bufadd(path)

      eq(buf, buffers.find(path).bufnr)
      assert.is_nil(buffers.find(path .. 'x'))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('load', function()
    it('loads a file into a listed buffer, ready to edit', function()
      local path = vim.fn.tempname()

      vim.fn.writefile({ 'on disk' }, path)

      local buffer = buffers.load(path)

      eq({ 'on disk' }, buffer:get_lines())
      eq(true, vim.bo[buffer.bufnr].buflisted)
      vim.api.nvim_buf_delete(buffer.bufnr, { force = true })
      os.remove(path)
    end)
  end)

  describe('listed', function()
    it('describes the listed buffers, marking unsaved ones', function()
      local path = vim.fn.tempname()

      vim.fn.writefile({ 'a' }, path)

      local buffer = buffers.load(path)

      local function mine()
        for _, info in ipairs(buffers.listed()) do
          if info.bufnr == buffer.bufnr then return info end
        end
      end

      eq({ vim.fn.resolve(path), false }, { vim.fn.resolve(mine().name), mine().changed })

      vim.api.nvim_buf_set_lines(buffer.bufnr, 0, -1, false, { 'b' })
      eq(true, mine().changed)

      vim.api.nvim_buf_delete(buffer.bufnr, { force = true })
      assert.is_nil(mine())
      os.remove(path)
    end)
  end)

  describe('add', function()
    it('makes a buffer for a path without listing it', function()
      local path = vim.fn.tempname()
      local buffer = buffers.add(path)

      eq(false, buffer:is_listed())
      eq(vim.fn.resolve(path), vim.fn.resolve(buffer:get_name()))

      buffer:delete()
    end)
  end)
end)
