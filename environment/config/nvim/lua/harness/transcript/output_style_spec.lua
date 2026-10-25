local output_style = require('harness.transcript.output_style')

local eq = assert.are.same

describe('harness.transcript.output_style:', function()
  describe('language', function()
    it('reads the language off the command', function()
      eq('json', output_style.language('curl -s api | jq .', { 'x' }))
      eq('diff', output_style.language('git diff --stat HEAD', { 'x' }))
      eq('diff', output_style.language('git show HEAD~1', { 'x' }))
      eq('lua', output_style.language('cat lua/init.lua', { 'x' }))
      eq('python', output_style.language('cd src && head -n 20 "main.py"', { 'x' }))
      eq('yaml', output_style.language('sed -n 1,20p config.yml', { 'x' }))
    end)

    it('falls back to the content, and to nothing for plain text', function()
      eq('json', output_style.language('curl -s api', { '', '{', '  "a": 1', '}', '' }))
      eq('json', output_style.language(nil, { '[1, 2]' }))
      eq('diff', output_style.language('some-tool', { 'diff --git a/x b/x', '@@ -1 +1 @@' }))
      eq(nil, output_style.language('ls', { 'a.lua', 'b.lua' }))
      eq(nil, output_style.language('echo', { '{ not closed' }))
      eq(nil, output_style.language('cat notes.unknownext', { 'text' }))
    end)

    it('labels a fence with its language under the output family', function()
      eq('output', output_style.label(nil))
      eq('output_json', output_style.label('json'))
      eq('terminal', output_style.label(nil, output_style.TERMINAL))
      eq('terminal_json', output_style.label('json', output_style.TERMINAL))
    end)
  end)

  describe('strip', function()
    it('leaves lines without escapes as the same table', function()
      local lines = { 'a', 'b' }
      local clean, spans = output_style.strip(lines)

      eq(true, clean == lines)
      eq(nil, spans)
    end)

    it('removes colour codes and keeps where each colour applied', function()
      local clean, spans = output_style.strip({ 'ok \27[31mred\27[0m plain', '\27[1;32mbold green\27[m' })

      eq({ 'ok red plain', 'bold green' }, clean)
      eq({
        { 1, 3, 6, 'UiAnsi1' },
        { 2, 0, 10, 'UiAnsi2' },
        { 2, 0, 10, 'UiAnsiBold' },
      }, spans)
    end)

    it('maps bright and 256-colour codes, drops truecolour and cursor movement', function()
      local clean, spans = output_style.strip({ '\27[91mA\27[38;5;4mB\27[38;2;1;2;3mC\27[2K\27[1GD' })

      eq({ 'ABCD' }, clean)
      eq({ { 1, 0, 1, 'UiAnsi9' }, { 1, 1, 2, 'UiAnsi4' } }, spans)
    end)

    it('carries a colour onto the next lines until it is reset', function()
      local clean, spans = output_style.strip({ '\27[33mstart', 'middle', 'end\27[0m', 'after' })

      eq({ 'start', 'middle', 'end', 'after' }, clean)
      eq({ { 1, 0, 5, 'UiAnsi3' }, { 2, 0, 6, 'UiAnsi3' }, { 3, 0, 3, 'UiAnsi3' } }, spans)
    end)
  end)

  describe('rules', function()
    local function whole(line, group)
      eq({ { 0, #line, group } }, output_style.rules(line))
    end

    it('colours error, warning and success lines', function()
      whole('error: no such x', 'UiError')
      whole('FAIL  spec.js', 'UiError')
      whole('Traceback (most recent call last):', 'UiError')
      whole('warning: unused variable', 'UiWarn')
      whole('PASS  all tests', 'UiAdded')
      whole('ok 3 tests', 'UiAdded')
    end)

    it('does not call a summary with no failures an error', function()
      whole('5 passed, 0 failed', 'UiAdded')
      whole('3 passed, 2 failed', 'UiError')
    end)

    it('colours git status letters', function()
      eq({ { 0, 2, 'UiWarn' } }, output_style.rules(' M lua/a.lua'))
      eq({ { 0, 2, 'UiAdded' } }, output_style.rules('?? new.lua'))
      eq({ { 0, 2, 'UiRemoved' } }, output_style.rules('D  gone.lua'))
    end)

    it('marks file:line locations', function()
      local line = 'lua/a.lua:12 error: x'

      eq({ { 0, #line, 'UiError' }, { 0, 12, 'UiPath' } }, output_style.rules(line))
      eq({ { 4, 16, 'UiPath' } }, output_style.rules('see src/x.ts:3:9 here'))
    end)

    it('leaves plain lines alone', function()
      eq({}, output_style.rules('just some words'))
      eq({}, output_style.rules(''))
    end)
  end)
end)
