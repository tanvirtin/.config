local sources = require('sources')

local eq = assert.are.same

local function fixture()
  local root = vim.fs.normalize(vim.fn.tempname())

  vim.fn.mkdir(root .. '/lua/app', 'p')
  vim.fn.writefile(
    { 'local M = {}', 'function M.greet(name)', '  return "hi " .. name', 'end', 'return M' },
    root .. '/lua/app/greet.lua'
  )
  vim.fn.writefile({ 'require("app.greet").greet("you")' }, root .. '/main.lua')
  vim.fn.writefile({ 'ignored.lua' }, root .. '/.gitignore')
  vim.fn.writefile({ 'greet' }, root .. '/ignored.lua')
  vim.fn.mkdir(root .. '/.git', 'p')

  return root
end

local function labels(items)
  local out = vim.tbl_map(function(item)
    return item.label
  end, items)

  table.sort(out)

  return out
end

describe('sources:', function()
  local root

  before_each(function()
    root = fixture()
  end)

  it('lists the built-in sources', function()
    eq({ 'buffers', 'diagnostics', 'files', 'grep', 'lsp' }, sources.names())
  end)

  describe('files', function()
    it('lists files with .gitignore respected and .git left out', function()
      local items, err = sources.collect('files', '', { cwd = root })

      eq(nil, err)
      eq({ '.gitignore', 'lua/app/greet.lua', 'main.lua' }, labels(items))
      eq(
        root .. '/main.lua',
        vim.tbl_filter(function(i)
          return i.label == 'main.lua'
        end, items)[1].path
      )
    end)

    it('fuzzy-matches the path when given a query', function()
      local items = sources.collect('files', 'grt', { cwd = root })

      eq({ 'lua/app/greet.lua' }, labels(items))
    end)
  end)

  describe('grep', function()
    it('finds matching lines with 1-based positions', function()
      local items, err = sources.collect('grep', 'greet', { cwd = root })

      eq(nil, err)
      eq(2, #items)

      table.sort(items, function(a, b)
        return a.path < b.path
      end)

      eq({ root .. '/lua/app/greet.lua', 2, 12 }, { items[1].path, items[1].line, items[1].col })
      eq('function M.greet(name)', items[1].text)
      eq('match', items[1].kind)
    end)

    it('returns nothing for an empty query, and nothing for no match', function()
      eq({}, (sources.collect('grep', '', { cwd = root })))
      eq({}, (sources.collect('grep', 'zzz_not_here', { cwd = root })))
    end)
  end)

  describe('diagnostics', function()
    it('lists diagnostics errors first', function()
      local buf = vim.api.nvim_create_buf(true, false)
      local ns = vim.api.nvim_create_namespace('sources_spec')

      vim.api.nvim_buf_set_name(buf, root .. '/main.lua')
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'b' })
      vim.diagnostic.set(ns, buf, {
        { lnum = 1, col = 0, message = 'just a hint', severity = vim.diagnostic.severity.HINT },
        { lnum = 0, col = 2, message = 'broken', severity = vim.diagnostic.severity.ERROR, source = 'lua_ls' },
      })

      local items = sources.collect('diagnostics', '', { buf = buf })

      eq(2, #items)
      eq({ 1, 3, 'ERROR broken [lua_ls]' }, { items[1].line, items[1].col, items[1].text })
      eq('HINT just a hint', items[2].text)

      vim.diagnostic.reset(ns, buf)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('buffers', function()
    it('lists listed buffers and marks unsaved ones', function()
      vim.cmd('edit ' .. root .. '/main.lua')
      vim.api.nvim_buf_set_lines(0, 0, 0, false, { '-- new' })

      local items = sources.collect('buffers', 'main')

      eq('main.lua [+]', vim.fn.fnamemodify(items[1].label, ':t'))
      eq('unsaved changes', items[1].text)

      vim.cmd('bwipeout!')
    end)
  end)

  describe('lsp', function()
    it('reports a buffer without a language server', function()
      local _, err = sources.collect('lsp', '', { method = 'references' })

      assert.is_truthy(err:find('no language server', 1, true))
    end)

    it('reports an unknown method', function()
      local _, err = sources.collect('lsp', '', { method = 'nope' })

      eq('unknown LSP method: nope', err)
    end)
  end)

  it('reports an unknown source', function()
    local items, err = sources.collect('nope')

    eq({}, items)
    eq('unknown source: nope', err)
  end)

  it('stops a source that runs past the timeout and keeps what arrived', function()
    sources.register({
      name = 'slow_spec',
      collect = function(_, _, emit)
        emit({ { label = 'early' } })
        return function() end
      end,
    })

    local items, err = sources.collect('slow_spec', '', {}, 50)

    eq({ { label = 'early' } }, items)
    assert.is_truthy(err:find('timed out', 1, true))
  end)
end)
