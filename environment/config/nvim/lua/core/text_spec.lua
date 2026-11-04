local text = require('core.text')

local eq = assert.are.same

describe('core.text:', function()
  describe('fuzzy', function()
    it('keeps only the items whose key matches the query', function()
      local items = { { name = 'buffer_edit' }, { name = 'git_diff' }, { name = 'buffer_read' } }

      local found = text.fuzzy(items, 'gitdif', function(item)
        return item.name
      end)

      eq(
        { 'git_diff' },
        vim.tbl_map(function(item)
          return item.name
        end, found)
      )
    end)
  end)
end)
