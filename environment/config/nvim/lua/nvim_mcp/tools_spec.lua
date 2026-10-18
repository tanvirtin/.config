local tools = require('nvim_mcp.tools')

local eq = assert.are.same

local function run(name, args)
  return tools.run(name, args or {})
end

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

describe('nvim_mcp.tools:', function()
  local buf

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('enew!')
    buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'local x = 1', 'local y = x', 'return y' })
    vim.bo[buf].modified = false
    tools.set_focus(nil)
  end)

  it('gives every entry a tier, a summary and a runner', function()
    for _, entry in ipairs(tools.entries()) do
      assert.is_truthy(({ read = true, write = true, exec = true })[entry.risk], entry.name)
      assert.is_truthy(entry.summary ~= '', entry.name)
      eq('editor', entry.kind)
      eq(entry.risk, tools.risk(entry.name))
    end

    eq(nil, tools.risk('nvim_buf_get_lines'))
  end)

  describe('arguments', function()
    it('rejects an unknown argument instead of ignoring it', function()
      local ok, err = pcall(run, 'buffer_read', { buffer = buf })

      eq(false, ok)
      assert.is_truthy(err:find('invalid arguments for buffer_read', 1, true))
    end)

    it('rejects a missing required argument', function()
      local ok = pcall(run, 'buffer_edit', { old_string = 'x' })

      eq(false, ok)
    end)

    it('raises on an unknown tool', function()
      local ok, err = pcall(run, 'nope')

      eq(false, ok)
      eq('unknown editor tool: nope', err)
    end)
  end)

  describe('focus', function()
    it('targets the focused window, not the current one', function()
      local win = vim.api.nvim_get_current_win()

      tools.set_focus(win)
      vim.cmd('tabnew')

      assert.is_truthy(run('editor_state'):find('bufnr ' .. buf .. ',', 1, true))
      assert.is_truthy(run('buffer_read'):find('local x = 1', 1, true))
    end)

    it('falls back to the current window when the focus is gone', function()
      vim.cmd('tabnew')
      local win = vim.api.nvim_get_current_win()

      tools.set_focus(win)
      vim.cmd('tabclose')

      assert.is_truthy(run('editor_state'):find('bufnr ' .. buf .. ',', 1, true))
    end)
  end)

  describe('editor_state', function()
    it('reports the cursor 1-based and every listed buffer', function()
      vim.api.nvim_win_set_cursor(0, { 2, 3 })

      local state = run('editor_state')

      assert.is_truthy(state:find('cursor 2:4 of 3 lines', 1, true))
      assert.is_truthy(state:find('^cwd '))
      assert.is_truthy(state:find('\ntabs %(%* focus%):\n  1: win %d+ '))
    end)
  end)

  describe('buffer_read', function()
    it('numbers lines 1-based and inclusive', function()
      local out = run('buffer_read', { bufnr = buf, start_line = 2, end_line = 3 })

      assert.is_truthy(out:find('lines 2-3 of 3', 1, true))
      assert.is_truthy(out:find('     2\tlocal y = x', 1, true))
      assert.is_truthy(out:find('     3\treturn y', 1, true))
      assert.is_falsy(out:find('local x = 1', 1, true))
    end)

    it('says when the buffer has unsaved changes', function()
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'changed' })

      assert.is_truthy(run('buffer_read', { bufnr = buf }):find('unsaved changes', 1, true))
    end)

    it('loads a file by path', function()
      local path = debug.getinfo(1, 'S').source:sub(2)

      assert.is_truthy(
        run('buffer_read', { path = path, end_line = 1 }):find('local tools = require(\'nvim_mcp.tools\')', 1, true)
      )
    end)

    it('fails on a path that does not exist', function()
      local ok, err = pcall(run, 'buffer_read', { path = '/nonexistent/harness.lua' })

      eq(false, ok)
      assert.is_truthy(err:find('no buffer or file', 1, true))
    end)
  end)

  describe('buffer_edit', function()
    it('replaces a unique match as one undo step and leaves the buffer unsaved', function()
      local result = run('buffer_edit', { bufnr = buf, old_string = 'local y = x', new_string = 'local y = x + 1' })

      eq({ 'local x = 1', 'local y = x + 1', 'return y' }, lines(buf))
      eq(1, result.replacements)
      eq(2, result.start_line)
      eq(true, vim.bo[buf].modified)

      vim.api.nvim_buf_call(buf, function()
        vim.cmd('silent undo')
      end)

      eq({ 'local x = 1', 'local y = x', 'return y' }, lines(buf))
    end)

    it('edits across lines', function()
      run('buffer_edit', { bufnr = buf, old_string = 'x = 1\nlocal y', new_string = 'x = 2\nlocal z' })

      eq({ 'local x = 2', 'local z = x', 'return y' }, lines(buf))
    end)

    it('refuses an ambiguous match unless replace_all', function()
      local ok, err = pcall(run, 'buffer_edit', { bufnr = buf, old_string = 'local', new_string = 'var' })

      eq(false, ok)
      assert.is_truthy(err:find('matches 2 times', 1, true))

      eq(
        2,
        run('buffer_edit', { bufnr = buf, old_string = 'local', new_string = 'var', replace_all = true }).replacements
      )
      eq({ 'var x = 1', 'var y = x', 'return y' }, lines(buf))
    end)

    it('treats the strings literally, not as patterns', function()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a.b(%1)' })

      run('buffer_edit', { bufnr = buf, old_string = '.b(%1)', new_string = '%2' })

      eq({ 'a%2' }, lines(buf))
    end)

    it('fails when old_string is missing', function()
      local ok, err = pcall(run, 'buffer_edit', { bufnr = buf, old_string = 'nope', new_string = 'x' })

      eq(false, ok)
      assert.is_truthy(err:find('old_string not found', 1, true))
    end)
  end)

  describe('buffer_write', function()
    it('replaces the whole buffer without a trailing empty line', function()
      run('buffer_write', { bufnr = buf, content = 'one\ntwo\n' })

      eq({ 'one', 'two' }, lines(buf))
      eq(true, vim.bo[buf].modified)
    end)

    it('creates a buffer for a new path without saving it', function()
      local path = vim.fn.tempname() .. '/new.lua'
      local result = run('buffer_write', { path = path, content = 'return 1' })

      eq({ 'return 1' }, lines(result.bufnr))
      eq(nil, vim.uv.fs_stat(path))
    end)
  end)

  describe('buffer_save', function()
    it('writes the buffer to disk, creating directories', function()
      local path = vim.fn.tempname() .. '/dir/saved.lua'

      run('buffer_write', { path = path, content = 'return 2' })
      run('buffer_save', { path = path })

      eq({ 'return 2' }, vim.fn.readfile(path))
    end)
  end)

  describe('open and cursor_set', function()
    it('opens a file in a new tab at a line and focuses it', function()
      local tabs = #vim.api.nvim_list_tabpages()
      local path = debug.getinfo(1, 'S').source:sub(2)

      local result = run('open', { path = path, line = 3 })

      eq(tabs + 1, #vim.api.nvim_list_tabpages())
      eq(3, vim.api.nvim_win_get_cursor(result.win)[1])
      assert.is_truthy(run('editor_state'):find('bufnr ' .. result.bufnr .. ',', 1, true))
    end)

    it('moves the cursor 1-based', function()
      run('cursor_set', { line = 2, col = 3 })

      eq({ 2, 2 }, vim.api.nvim_win_get_cursor(0))
    end)
  end)

  describe('diagnostics and lsp', function()
    it('reports diagnostics 1-based', function()
      vim.diagnostic.set(vim.api.nvim_create_namespace('tools_spec'), buf, {
        { lnum = 1, col = 2, message = 'boom', severity = vim.diagnostic.severity.ERROR },
      })

      local out = run('diagnostics', { bufnr = buf })

      assert.is_truthy(out:find('  2:3: ERROR boom', 1, true))
    end)

    it('fails clearly when no language server is attached', function()
      local ok, err = pcall(run, 'lsp_definition', { bufnr = buf, line = 1 })

      eq(false, ok)
      assert.is_truthy(err:find('no language server attached', 1, true))
    end)

    it('converts LSP locations to 1-based positions', function()
      eq(
        { { path = '/a.lua', line = 3, col = 5 } },
        tools.locations({
          uri = 'file:///a.lua',
          range = { start = { line = 2, character = 4 }, ['end'] = { line = 2, character = 6 } },
        })
      )
      eq(1, #tools.locations({
        { targetUri = 'file:///b.lua', targetSelectionRange = { start = { line = 0, character = 0 } } },
      }))
    end)
  end)

  describe('fs_find', function()
    it('finds a file by name under a path', function()
      local dir = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
      local out = run('fs_find', { names = { 'tools_spec.lua' }, path = dir, type = 'file' })

      assert.is_truthy(out[1]:find('tools_spec.lua', 1, true))
    end)
  end)

  describe('exec', function()
    before_each(function()
      require('nvim_mcp.script').reset()
    end)

    it('runs a multi-line script and returns printed output and values', function()
      local code = table.concat({
        'local items = {}',
        'for i = 1, 2 do',
        '  items[#items + 1] = i',
        'end',
        'print("built", #items)',
        'return items',
      }, '\n')

      eq('built\n2\n{ 1, 2 }', run('lua', { code = code }))
      eq('', run('lua', { code = 'local _ = 1' }))
    end)

    it('reports a runtime error with a traceback into the script', function()
      local ok, err = pcall(run, 'lua', { code = 'local function inner()\n  error("bad")\nend\ninner()' })

      eq(false, ok)
      assert.is_truthy(err:find('script:2: bad', 1, true))
      assert.is_truthy(err:find('stack traceback:', 1, true))
      assert.is_falsy(err:find('nvim_mcp/tools', 1, true))
    end)

    it('reports a syntax error', function()
      local ok, err = pcall(run, 'lua', { code = 'return (' })

      eq(false, ok)
      assert.is_truthy(err:find('syntax error: script:1', 1, true))
    end)

    it('keeps globals between scripts without touching _G', function()
      run('lua', { code = 'helper = function(x) return x * 2 end' })

      eq('42', run('lua', { code = 'return helper(21)' }))
      eq(nil, rawget(_G, 'helper'))
      eq(true, run('lua', { code = 'return vim ~= nil' }) == 'true')
    end)

    it('leaves the real print alone', function()
      local original = print

      run('lua', { code = 'print("x")' })
      pcall(run, 'lua', { code = 'print("x") error("y")' })

      eq(original, print)
    end)

    it('stops a runaway script at its timeout', function()
      local ok, err = pcall(run, 'lua', { code = 'while true do end', timeout_ms = 50 })

      eq(false, ok)
      assert.is_truthy(err:find('script timed out after 50 ms', 1, true))
      eq('1', run('lua', { code = 'return 1' }))
    end)

    it('runs an Ex command and returns its output', function()
      eq('42', run('ex', { command = 'echo 42' }))
    end)
  end)
  describe('registry', function()
    local function entry(name, fn)
      return {
        name = name,
        risk = 'read',
        summary = 'test tool',
        params = { { name = 'n', type = require('nvim_mcp.schema').int(), optional = true } },
        fn = fn or function(args, ctx)
          return { n = args.n, caller = ctx.caller }
        end,
      }
    end

    after_each(function()
      tools.unregister('spec')
    end)

    it('lists the built-in toolsets in order', function()
      local names = vim.tbl_map(function(e)
        return e.name
      end, tools.entries())

      eq('editor_state', names[1])
      eq('ex', names[#names])
    end)

    it('runs a registered tool with validated arguments and the caller', function()
      tools.register('spec', { entry('spec_echo') })

      eq({ n = 3, caller = 'h4' }, tools.run('spec_echo', { n = '3' }, 'h4'))
      eq({ n = nil, caller = nil }, tools.run('spec_echo', {}, ''))
      eq('read', tools.risk('spec_echo'))
    end)

    it('replaces a toolset of the same name and removes it', function()
      tools.register('spec', { entry('spec_one') })
      tools.register('spec', { entry('spec_two') })

      eq(nil, tools.risk('spec_one'))
      eq('read', tools.risk('spec_two'))

      tools.unregister('spec')

      eq(nil, tools.risk('spec_two'))
    end)

    it('refuses malformed tools and names another toolset has', function()
      local bad = entry('spec_bad')
      bad.risk = 'maybe'

      eq(false, pcall(tools.register, 'spec', { bad }))
      eq(false, pcall(tools.register, 'spec', { entry('buffer_read') }))
      eq(false, pcall(tools.register, 'spec', { entry('nvim_spec') }))
      eq(false, pcall(tools.register, 'spec', { entry('spec_x'), entry('spec_x') }))
    end)

    it('gives the server definitions it can receive over RPC', function()
      tools.register('spec', { entry('spec_echo') })

      local found

      for _, definition in ipairs(tools.definitions()) do
        eq(nil, definition.fn)
        if definition.name == 'spec_echo' then found = definition end
      end

      eq(
        { name = 'spec_echo', kind = 'editor', risk = 'read', summary = 'test tool', params = entry('x').params },
        found
      )
      eq(found, vim.mpack.decode(vim.mpack.encode(found)))
    end)
  end)
end)
