local context = require('harness.context')

local eq = assert.are.same

describe('harness.context:', function()
  before_each(function()
    vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three' })
    vim.api.nvim_win_set_cursor(0, { 2, 1 })
  end)

  it('says where the user is, in an editor-context tag', function()
    local text = context.capture(vim.api.nvim_get_current_win()).where

    assert.is_truthy(text:find('^<editor%-context>'))
    assert.is_truthy(text:find('%[No Name%] %(bufnr ' .. vim.api.nvim_get_current_buf() .. '%), line 2, col 2'))
    assert.is_truthy(text:find('</editor%-context>$'))
  end)

  it('mentions a selected range', function()
    assert.is_truthy(
      context.capture(vim.api.nvim_get_current_win(), { 2, 3 }).where:find('selected lines 2-3', 1, true)
    )
  end)

  it('attaches the selected lines with where they came from', function()
    local path = vim.fn.tempname() .. '.lua'

    vim.api.nvim_buf_set_name(0, path)
    vim.bo.filetype = 'lua'

    local attachment = context.capture(vim.api.nvim_get_current_win(), { 2, 3 }).attachments[1]

    eq({ 'two', 'three' }, attachment.lines)
    eq({ 2, 3 }, attachment.range)
    eq('lua', attachment.language)
    eq(vim.fn.resolve(path), vim.fn.resolve(attachment.path))
    assert.is_truthy(attachment.label:find(':2%-3$'))
    eq({}, context.capture(vim.api.nvim_get_current_win()).attachments)
  end)

  describe('tokens', function()
    local dir, cwd

    before_each(function()
      cwd = vim.fn.getcwd()
      dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir .. '/sub', 'p')
      vim.fn.writefile({ 'one', 'two', 'three' }, dir .. '/a.lua')
      vim.cmd.cd(dir)
    end)

    after_each(function()
      vim.cmd.cd(cwd)
      vim.fn.delete(dir, 'rf')
    end)

    it('writes a path relative to the editor, quoted when it has spaces', function()
      eq('@a.lua:2-3', context.token(dir .. '/a.lua', { 2, 3 }))
      eq('@a.lua:2', context.token(dir .. '/a.lua', { 2, 2 }))
      eq('@"my dir/b.lua":1', context.token(dir .. '/my dir/b.lua', { 1, 1 }))
    end)

    it('reads the token from where the editor stands before the session dir', function()
      vim.fn.writefile({ 'decoy', 'decoy', 'decoy' }, dir .. '/sub/a.lua')

      local attachments = context.resolve_tokens('see @a.lua:2-3.', dir .. '/sub')

      eq(1, #attachments)
      eq({ 'two', 'three' }, attachments[1].lines)
      eq('@a.lua:2-3', attachments[1].token)
    end)

    it('falls back to the session dir', function()
      vim.fn.writefile({ 'only here' }, dir .. '/sub/b.lua')

      eq({ 'only here' }, context.resolve_tokens('@b.lua:1', dir .. '/sub')[1].lines)
    end)

    it('takes unsaved edits from an open buffer', function()
      local buf = vim.fn.bufadd(dir .. '/a.lua')

      vim.fn.bufload(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'edited', 'lines' })

      eq({ 'edited', 'lines' }, context.resolve_tokens('@a.lua:1-2', dir)[1].lines)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('resolves a quoted path with spaces', function()
      vim.fn.mkdir(dir .. '/my dir', 'p')
      vim.fn.writefile({ 'spaced' }, dir .. '/my dir/b.lua')

      local attachments = context.resolve_tokens('fix @"my dir/b.lua":1 now', dir)

      eq({ 'spaced' }, attachments[1].lines)
      eq('@"my dir/b.lua":1', attachments[1].token)
    end)

    it('reports a token it cannot resolve and ignores prose', function()
      local attachments, problems = context.resolve_tokens('@a.lua:9 and @nope.lua:1 to @someone, user@x', dir)

      eq({}, attachments)
      eq({
        '@a.lua:9 is past the end of the file, so it was sent as text',
        '@nope.lua:1 does not name a file, so it was sent as text',
      }, problems)
    end)

    it('sends at most the first lines of a long reference, and says so', function()
      local attachments, problems = context.resolve_tokens('@a.lua', dir, { max_lines = 2 })

      eq({ 'one', 'two' }, attachments[1].lines)
      eq({ 1, 2 }, attachments[1].range)
      eq({ '@a.lua has 3 lines; only the first 2 were sent' }, problems)
    end)

    it('takes a path without lines as the whole file, and leaves other words alone', function()
      vim.fn.writefile({ 'x' }, dir .. '/someone')

      local attachments, problems = context.resolve_tokens('read @a.lua, ask @nobody, mail me@someone', dir)

      eq(1, #attachments)
      eq({ 'one', 'two', 'three' }, attachments[1].lines)
      eq({ 1, 3 }, attachments[1].range)
      eq({}, problems)

      vim.fn.mkdir(dir .. '/my dir', 'p')
      vim.fn.writefile({ 'a', 'b' }, dir .. '/my dir/b.lua')

      eq({ 'a', 'b' }, context.resolve_tokens('see @"my dir/b.lua" here', dir)[1].lines)
    end)

    it('takes back the file an agent wrote into its echo of a prompt', function()
      local echoed = table.concat({
        'tour it, start with @a.lua',
        '[' .. dir .. '/a.lua:1]',
        'one',
        'two',
        'three',
        ' and explain it',
        'then @a.lua:2-2',
        '[' .. dir .. '/a.lua:2]',
        'two',
        'three',
      }, '\n')

      eq('tour it, start with @a.lua and explain it\nthen @a.lua:2-2\nthree', context.strip_echoed(echoed))
      eq('plain [text]', context.strip_echoed('plain [text]'))
    end)

    it('finds where each reference sits in a line', function()
      eq({
        { token = '@a.lua:2', start = 5, finish = 12 },
        { token = '@"my dir/b.lua"', start = 18, finish = 32 },
      }, context.tokens('see @a.lua:2, or @"my dir/b.lua" (me@x)'))
      eq(true, context.names_file('@a.lua', dir))
      eq(false, context.names_file('@nope.lua', dir))
    end)

    it('puts each file a message names on its context, and says what it could not', function()
      local where, problems = context.attach_tokens(nil, 'see @a.lua:1 and @nope.lua:1', dir)

      eq({ 'one' }, where.attachments[1].lines)
      eq(1, #where.attachments)
      eq(1, #problems)
    end)

    it('resolves a repeated token once', function()
      eq(1, #context.resolve_tokens('@a.lua:1 and @a.lua:1', dir))
    end)
  end)

  it('strips the tag from a replayed prompt', function()
    local text = context.capture(vim.api.nvim_get_current_win()).where .. '\n\nrename x'

    eq('rename x', context.strip(text))
    eq('plain', context.strip('plain'))
  end)
end)
