local lazy = require('core.lazy')

local fs = lazy('core.fs')
local permission = require('harness.types.permission')
local claude = require('harness.permission_rules.claude')

local permission_rules = {}

permission_rules.FORMATS = { claude = claude }

local function spec_of(agent)
  local spec = type(agent) == 'table' and agent.permission_rules or nil

  if type(spec) ~= 'table' or not permission_rules.FORMATS[spec.format] then return nil end

  return spec
end

function permission_rules.supported(agent)
  return spec_of(agent) ~= nil
end

function permission_rules.paths(agent, dir)
  local spec = spec_of(agent)
  local out = {}

  for _, path in ipairs(spec and spec.paths or {}) do
    local expanded = fs.expand(path)

    if expanded:sub(1, 1) ~= '/' then expanded = fs.joinpath(dir, expanded) end

    out[#out + 1] = fs.normalize(expanded)
  end

  return out
end

local function read(path)
  local lines = fs.read_file(path)

  return lines and table.concat(lines, '\n') or nil
end

function permission_rules.load(agent, dir)
  local spec = spec_of(agent)
  local rules, problems = {}, {}

  if not spec then return rules, problems end

  local format = permission_rules.FORMATS[spec.format]

  for _, path in ipairs(permission_rules.paths(agent, dir)) do
    local text = read(path)

    if text then
      local found, why = format.read(text)

      if found then
        for _, rule in ipairs(found) do
          local tool, content = format.parse(rule.text)

          rules[#rules + 1] = permission.Rule({
            text = rule.text,
            tool = tool,
            content = content,
            behavior = rule.behavior,
            path = path,
            format = spec.format,
          })
        end
      else
        problems[#problems + 1] = string.format('%s: %s', fs.display(path), why)
      end
    end
  end

  return rules, problems
end

function permission_rules.remove(rule)
  local format = permission_rules.FORMATS[rule.format]

  if not format then return nil, 'no format ' .. tostring(rule.format) end

  local text = read(rule.path)

  if not text then return nil, fs.display(rule.path) .. ' is gone' end

  local edited, why = format.remove(text, rule.behavior, rule.text)

  if not edited then return nil, why end

  local _, err = fs.write_file(rule.path, vim.split(edited, '\n', { plain = true }))

  if err then return nil, table.concat(err, '; ') end

  return true
end

return permission_rules
