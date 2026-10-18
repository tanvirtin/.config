local async = require('harness.async')
local permissions = require('harness.permissions')

local eq = assert.are.same

local function request(tool, input)
  return { tool = tool, params = { toolCall = { toolCallId = 't1', rawInput = input } } }
end

describe('harness.permissions:', function()
  describe('tier', function()
    it('reads the tier of editor tools and raw API tools', function()
      eq('read', permissions.tier('mcp__nvim__buffer_read'))
      eq('write', permissions.tier('mcp__nvim__buffer_edit'))
      eq('exec', permissions.tier('mcp__nvim__lua'))
      eq('read', permissions.tier('mcp__nvim__nvim_buf_get_lines'))
      eq('write', permissions.tier('mcp__nvim__nvim_buf_set_lines'))
      eq('exec', permissions.tier('mcp__nvim__nvim_exec_lua'))
    end)

    it('treats unknown names from this server as exec', function()
      eq('exec', permissions.tier('mcp__nvim__mystery'))
    end)

    it('returns nil for tools that are not this editor\'s', function()
      eq(nil, permissions.tier('Bash'))
      eq(nil, permissions.tier('mcp__other__buffer_read'))
      eq(nil, permissions.tier(nil))
    end)
  end)

  describe('new', function()
    it('allows read and write tools without asking', function()
      local approve = permissions.new({
        ask = function()
          error('should not ask')
        end,
      })

      eq('allow_once', approve(request('mcp__nvim__buffer_read')))
      eq('allow_once', approve(request('mcp__nvim__buffer_edit')))
    end)

    it('allows every tool of this editor with auto_allow, but still asks for others', function()
      local asked = {}
      local approve = permissions.new({
        auto_allow = true,
        ask = function(req)
          asked[#asked + 1] = req.tool
          return 'reject_once'
        end,
      })

      eq('allow_once', approve(request('mcp__nvim__lua')))
      eq('allow_once', approve(request('mcp__nvim__nvim_exec_lua')))
      eq('reject_once', approve(request('Bash')))
      eq({ 'Bash' }, asked)
    end)

    it('refuses exec and foreign tools when it cannot ask', function()
      local approve = permissions.new()

      eq('reject_once', approve(request('mcp__nvim__lua')))
      eq('reject_once', approve(request('Bash')))
    end)

    it('asks for exec tools and passes the answer through', function()
      local asked
      local approve = permissions.new({
        ask = function(req)
          asked = req.tool
          return 'reject_once'
        end,
      })

      eq('reject_once', approve(request('mcp__nvim__ex')))
      eq('mcp__nvim__ex', asked)
    end)

    it('remembers allow_always for the session and sends allow_once', function()
      local asks = 0
      local approve = permissions.new({
        ask = function()
          asks = asks + 1
          return 'allow_always'
        end,
      })

      eq('allow_once', approve(request('mcp__nvim__lua')))
      eq('allow_once', approve(request('mcp__nvim__lua')))
      eq(1, asks)

      approve(request('mcp__nvim__ex'))
      eq(2, asks)
    end)

    it('keeps sessions apart', function()
      local function always()
        return 'allow_always'
      end

      permissions.new({ ask = always })(request('mcp__nvim__lua'))

      eq('reject_once', permissions.new()(request('mcp__nvim__lua')))
    end)

    it('resolves an asynchronous answer', function()
      local answer = async.Future.new()
      local approve = permissions.new({
        ask = function()
          return answer
        end,
      })

      local decided = approve(request('mcp__nvim__lua'))

      answer:set_result('allow_always')
      async.drain()

      eq('allow_once', decided.result)
      eq('allow_once', approve(request('mcp__nvim__lua')))
    end)
  end)

  describe('describe', function()
    it('shows the code or command the tool will run', function()
      eq('mcp__nvim__lua: print(1)', permissions.describe(request('mcp__nvim__lua', { code = 'print(1)' })))
      eq('Bash: ls', permissions.describe(request('Bash', { command = 'ls' })))
      eq('X', permissions.describe(request('X')))
    end)

    it('fits in one line: the first line of code, the file a write targets', function()
      eq(
        'mcp__nvim__lua: local a = 1 (+2 lines)',
        permissions.describe(request('mcp__nvim__lua', { code = 'local a = 1\nlocal b = 2\nreturn a' }))
      )
      eq(
        'Write: notes/todo.md (3 lines)',
        permissions.describe(request('Write', { file_path = 'notes/todo.md', content = '- a\n- b\n- c' }))
      )
      eq(
        'Write notes/todo.md (2 lines)',
        permissions.describe(request('Write notes/todo.md', { file_path = 'notes/todo.md', content = 'a\nb' }))
      )
      eq('X', permissions.describe(request('X', vim.NIL)))
    end)

    it('caps long input', function()
      local text = permissions.describe(request('mcp__nvim__lua', { code = string.rep('x', 1000) }))

      assert.is_true(vim.fn.strchars(text) <= 160)
      assert.is_falsy(text:find('\n', 1, true))
    end)
  end)
end)
