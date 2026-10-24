local fs = require('core.fs')
local Timer = require('core.Timer')
local settings = require('harness.settings.skills')
local SkillSync = require('harness.features.SkillSync')

local eq = assert.are.same

describe('harness.features.SkillSync:', function()
  local dir, log, saved

  local function runs()
    return #(fs.read_file(log) or {})
  end

  local function sync_until(count)
    return Timer.wait(5000, function()
      return runs() >= count
    end, 10)
  end

  before_each(function()
    saved = vim.deepcopy(settings.data)
    dir = vim.fn.tempname()
    log = dir .. '.log'
    vim.fn.mkdir(dir .. '/skills', 'p')
    vim.fn.writefile({ 'description: a' }, dir .. '/skills/a.yml')
    settings:assign({ artifacts = dir, command = { 'sh', '-c', 'echo x >> ' .. log } })
  end)

  after_each(function()
    settings.data = saved
    vim.fn.delete(dir, 'rf')
    vim.fn.delete(log)
  end)

  it('exports once for an unchanged tree and again when an artifact changes', function()
    local feature = SkillSync()

    feature:sync()
    eq(true, sync_until(1))
    feature:sync()
    Timer.wait(100, function()
      return false
    end, 10)
    eq(1, runs())

    vim.fn.writefile({ 'description: b, longer' }, dir .. '/skills/a.yml')
    feature:sync()
    eq(true, sync_until(2))
  end)

  it('does nothing when the command is not installed', function()
    settings:assign({ command = { 'tin-not-installed-xyz' } })
    SkillSync():sync()
    eq(0, runs())
  end)

  it('registers once and cleans up', function()
    local feature = SkillSync():register_events()

    feature:cleanup()
    feature:cleanup()
  end)
end)
