local script = require('nvim_mcp.script')

local eq = assert.are.same

local function settle(ms)
  vim.wait(ms or 50, function()
    return false
  end)
end

describe('nvim_mcp.script:', function()
  local notified

  before_each(function()
    script.clear()
    settle()
    vim.cmd('silent! tabonly!')
    vim.cmd('enew!')
    notified = {}
    vim.notify = function(message)
      notified[#notified + 1] = message
    end
  end)

  describe('run', function()
    it('runs a multi-line script and returns printed output and values', function()
      eq('built\n2\n{ 1, 2 }', script.run('local t = { 1, 2 }\nprint("built", #t)\nreturn t'))
    end)

    it('raises with a traceback into the script', function()
      local ok, err = pcall(script.run, 'local function inner()\n  error("bad")\nend\ninner()')

      eq(false, ok)
      assert.is_truthy(err:find('script:2: bad', 1, true))
      assert.is_truthy(err:find('stack traceback:', 1, true))
      assert.is_falsy(err:find('script.lua', 1, true))
    end)

    it('stops a runaway script', function()
      local ok, err = pcall(script.run, 'while true do end', 50)

      eq(false, ok)
      assert.is_truthy(err:find('^script timed out after 50 ms'))
      assert.is_truthy(err:find('script:1: in main chunk', 1, true))
      assert.is_falsy(err:find('script.lua', 1, true))
    end)

    it('keeps globals between scripts without touching _G', function()
      script.run('helper = function(x) return x * 2 end')

      eq('42', script.run('return helper(21)'))
      eq(nil, rawget(_G, 'helper'))
    end)
  end)

  describe('guards', function()
    it('disables an autocmd on its first error and reports it once', function()
      script.run([[
        vim.api.nvim_create_autocmd('User', {
          pattern = 'HarnessSpec',
          callback = function()
            vim.api.nvim_buf_set_extmark(0, vim.api.nvim_create_namespace('x'), 0, 999, { virt_text = { { 'x' } } })
          end,
        })
      ]])

      vim.api.nvim_exec_autocmds('User', { pattern = 'HarnessSpec' })
      vim.api.nvim_exec_autocmds('User', { pattern = 'HarnessSpec' })
      settle()

      eq(1, #notified)
      assert.is_truthy(notified[1]:find('an autocmd', 1, true))
      eq(0, #vim.api.nvim_get_autocmds({ event = 'User', pattern = 'HarnessSpec' }))
    end)

    it('hands callback errors back to the agent with the next script', function()
      script.run([[vim.keymap.set('n', '<F9>', function() error('boom') end)]])
      vim.api.nvim_feedkeys(vim.keycode('<F9>'), 'x', false)

      local out = script.run('return 1')

      assert.is_truthy(out:find('Earlier script callbacks failed and were disabled', 1, true))
      assert.is_truthy(out:find('boom', 1, true))
      eq('1', script.run('return 1'))
    end)

    it('stops a repeating timer whose callback errors', function()
      script.run([[
        ticks = 0
        local timer = vim.uv.new_timer()
        timer:start(0, 5, function()
          ticks = ticks + 1
          error('tick')
        end)
      ]])
      settle(100)

      eq('1', script.run('return ticks'):match('(%d+)$'))
      eq(1, #notified)
    end)

    it('keeps working callbacks working', function()
      script.run([[
        count = 0
        vim.api.nvim_create_autocmd('User', { pattern = 'HarnessOk', callback = function() count = count + 1 end })
      ]])

      vim.api.nvim_exec_autocmds('User', { pattern = 'HarnessOk' })
      vim.api.nvim_exec_autocmds('User', { pattern = 'HarnessOk' })

      eq('2', script.run('return count'))
      eq(0, #notified)
    end)
  end)

  describe('clear', function()
    it('removes what scripts created and the scratch globals', function()
      local wins = #vim.api.nvim_list_wins()

      script.run([[
        leftover = true
        local ns = vim.api.nvim_create_namespace('harness_spec')
        vim.api.nvim_buf_set_extmark(0, ns, 0, 0, { virt_text = { { 'note' } } })
        vim.api.nvim_create_autocmd('User', { pattern = 'HarnessClear', callback = function() end })
        vim.keymap.set('n', '<F8>', function() end)
        vim.api.nvim_create_user_command('HarnessSpecCommand', function() end, {})
        vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, { relative = 'editor', row = 0, col = 0, width = 5, height = 1 })
      ]])

      eq(5, script.clear())

      eq(wins, #vim.api.nvim_list_wins())
      eq({}, vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('harness_spec'), 0, -1, {}))
      eq(0, #vim.api.nvim_get_autocmds({ event = 'User', pattern = 'HarnessClear' }))
      eq('', vim.fn.maparg('<F8>', 'n'))
      eq(nil, vim.api.nvim_get_commands({}).HarnessSpecCommand)
      eq('nil', script.run('return leftover'))
    end)
  end)
end)
