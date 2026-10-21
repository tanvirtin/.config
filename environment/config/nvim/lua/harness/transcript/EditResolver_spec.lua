local EditResolver = require('harness.transcript.EditResolver')

local eq = assert.are.same

describe('harness.transcript.EditResolver:', function()
  local file = { 'local a = 1', 'local b = 2', 'return a + b' }

  it('rebuilds the file before an edit that has landed, even from part of a line', function()
    local resolved = EditResolver.resolve(
      { old = 'b = 2', new = 'b = 3' },
      { 'local a = 1', 'local b = 3', 'return a + b' }
    )

    eq('applied', resolved.kind)
    eq(file, resolved.old_lines)
    eq({ 'local a = 1', 'local b = 3', 'return a + b' }, resolved.new_lines)
    assert.is_true(EditResolver.whole(resolved))
  end)

  it('builds the file after an edit that is still waiting to land', function()
    local resolved = EditResolver.resolve({ old = 'local b = 2\n', new = 'local c = 2\n' }, file)

    eq('pending', resolved.kind)
    eq(file, resolved.old_lines)
    eq({ 'local a = 1', 'local c = 2', 'return a + b' }, resolved.new_lines)
  end)

  it('treats a write of the whole file as a new file', function()
    local resolved = EditResolver.resolve({ old = '', new = 'one\ntwo\n' }, { 'one', 'two' })

    eq({ 'created', {}, { 'one', 'two' } }, { resolved.kind, resolved.old_lines, resolved.new_lines })
  end)

  it('prefers a match that covers whole lines over one inside a longer line', function()
    local resolved = EditResolver.resolve(
      { old = '  return 10', new = '  return 11' },
      { '  return 110', '  return 11' }
    )

    eq({ '  return 110', '  return 10' }, resolved.old_lines)
  end)

  it('shows a failed edit as just what was attempted, since it never landed anywhere in the file', function()
    local resolved = EditResolver.resolve({ old = 'a', new = 'b' }, { 'a', 'b' }, { failed = true })

    eq({ 'snippet', { 'a' }, { 'b' } }, { resolved.kind, resolved.old_lines, resolved.new_lines })
  end)

  it('falls back to the snippets when the file has neither side', function()
    local resolved = EditResolver.resolve({ old = 'x\ny\n', new = 'z\n' }, file)

    eq({ 'snippet', { 'x', 'y' }, { 'z' } }, { resolved.kind, resolved.old_lines, resolved.new_lines })
    assert.is_false(EditResolver.whole(resolved))
  end)
end)
