local lazy = require('core.lazy')
local vgit = lazy('harness.vgit')
local hub = require('harness.hub')
local fences = lazy('core.fences')
local async = lazy('harness.async')
local Timer = require('core.Timer')
local console = lazy('core.console')
local Window = require('core.Window')
local register = lazy('core.register')
local edits = lazy('harness.ui.edits')
local links = require('harness.ui.links')
local Renderer = lazy('ui.markdown.Renderer')
local display = lazy('harness.ui.display_api')
local theme = lazy('harness.transcript.theme')
local hit_test = require('harness.ui.hit_test')
local Block = require('harness.transcript.Block')
local actions = require('harness.transcript.actions')

local commands = {}

commands.FILE_CATEGORY = {
  [Block.CATEGORY.read] = true,
  [Block.CATEGORY.edit] = true,
  [Block.CATEGORY.delete] = true,
  [Block.CATEGORY.move] = true,
}

actions.bind('diff', function(view)
  return edits.show_edit(view)
end)

function commands.target_at(view, window)
  local cursor = window:get_cursor()
  local row, col = cursor[1] - 1, cursor[2]
  local document, dir = view.document, view.session.dir
  local kind, text = document.renderer:inline_at(row, col)

  if kind then
    local target = links.resolve(kind, text, dir)

    if target then return target end
  end

  local block = document:block_at(row)

  if not block then return nil end

  if block.kind == Block.KIND.diff then
    local line = Block.file_line(block, row)
    local target = links.resolve(Renderer.INLINE.link, block.path, dir)

    if target then return { path = target.path, line = line } end
  end

  if block.kind == Block.KIND.tool then
    local location = block.locations and block.locations[1]

    if location then
      local target = links.resolve(Renderer.INLINE.link, location.path, dir)

      if target then return { path = target.path, line = location.line or target.line } end
    end

    if commands.FILE_CATEGORY[block.category] and block.argument then
      return links.resolve(Renderer.INLINE.link, block.argument, dir)
    end
  end
end

function commands.jump(view, direction)
  local window = Window.get_current()
  local row = window:get_cursor()[1] - 1
  local rows = {}

  for _, block in ipairs(view.document.blocks) do
    if block.kind == Block.KIND.prompt then rows[#rows + 1] = block.start end
  end

  if direction < 0 then
    for i = #rows, 1, -1 do
      if rows[i] < row then return window:set_cursor({ rows[i] + 1, 0 }) end
    end
  else
    for _, candidate in ipairs(rows) do
      if candidate > row then return window:set_cursor({ candidate + 1, 0 }) end
    end
  end
end

function commands.toggle_at(view, window, fold_row, row)
  window:set_cursor({ fold_row, 0 })
  window:normal(window:fold_closed(fold_row) and 'zo' or 'zc')
  window:set_cursor({ row, 0 })

  return view
end

function commands.activate(view)
  local window = Window.get_current()
  local row = window:get_cursor()[1]

  if window:fold_closed(row) then
    window:normal('zo')
    return true
  end

  if links.open(view:_target_at(window)) then return true end

  if window:fold_level(row) > 0 then
    window:normal('zc')
    return true
  end

  local block = view.document:block_at(row - 1)

  if block and block.grouped then
    view:_toggle_at(window, block.finish + 1, row)
    return true
  end

  if block and block.kind == Block.KIND.collapsed then
    view:expand()
    window:set_cursor({ 1, 0 })
    return true
  end

  if block and block.folds and block.folds[1] then
    view:_toggle_at(window, block.start + block.folds[1][1] + 1, row)
    return true
  end

  return false
end

function commands.open_target(view)
  return links.open(view:_target_at(Window.get_current())) or false
end

function commands.run_block_action(view, key)
  local window = Window.get_current()
  local block = view.document:block_at(window:get_cursor()[1] - 1)

  return actions.run(view, block, key)
end

function commands.path_at(view)
  local target = view:_target_at(Window.get_current())

  return target and target.path or nil
end

function commands.git_diff(view)
  local path = view:path_at()

  if not path then return false, 'no file here' end

  return vgit.git_diff(path)
end

function commands.fork_point(view, row)
  local blocks = view.document.blocks
  local block = view.document:block_at(row)

  if not block then return nil end

  local from = block.kind == Block.KIND.prompt and block.index - 1 or block.index

  for i = from, 1, -1 do
    local candidate = blocks[i]

    if candidate and candidate.kind == Block.KIND.message and not candidate.depth and candidate.message_id ~= nil then
      return candidate.message_id
    end
  end
end

function commands.fork(view)
  local session = view.session

  if not session:can('fork') then return false, 'this agent cannot fork sessions' end

  local at_message = session:can('fork_at_message')
  local message_id = at_message and view:fork_point(Window.get_current():get_cursor()[1] - 1)

  if not at_message then
    console.notify_now('Harness: this agent forks a whole session; forking from the latest message')
  elseif not message_id then
    console.notify_now('Harness: no reply before this point; forking from the latest message')
  end

  hub.fork(session, message_id):on_complete(function(err, forked)
    Timer.schedule(function()
      if err then return console.notify_now('Harness: could not fork: ' .. tostring(err), 'warn') end

      display.open(forked)
    end)
  end)
  async.drain()

  return true
end

function commands.yank_token(view, block)
  local window = Window.get_current()
  local row = window:get_cursor()[1] - 1
  local col = window:get_cursor()[2]
  local hit = hit_test.at(block, row, col)

  if hit and hit.text then
    register.set(hit.text)

    return hit.text, hit.kind or 'token'
  end
end

function commands.yank_block(view, block, name)
  if not block then return nil end

  local row = Window.get_current():get_cursor()[1] - 1

  if block.kind == Block.KIND.diff and block.edit then
    local patch = vgit.patch_text(block.edit)

    register.set(patch, name)

    return patch, 'patch'
  end

  local lines = block.lines
  local first, last = fences.fenced_at(lines, row - block.start + 1)
  local text = vim.list_slice(lines, first or 1, last or #lines)

  if not first and lines[1] and lines[1]:match('^>') then
    text = vim.tbl_map(function(line)
      return (line:gsub('^> ?', ''))
    end, text)
  end

  register.set(text, name)

  return text, first and 'code block' or 'block'
end

function commands.yank(view, name)
  local row = Window.get_current():get_cursor()[1] - 1
  local block = view.document:block_at(row)
  local handled, text, code = view:run_block_action('yank')

  if handled then return text, code end

  return view:yank_block(block, name)
end

function commands.describe_choice(view, choice, current)
  local mark = choice.value == current and theme.CURRENT_ICON or '  '

  return mark .. (choice.name or choice.value) .. (choice.description and ('  ' .. choice.description) or '')
end

function commands.pick_model(view)
  local session = view.session
  local option = session:option('model')

  if not option or (option.kind and option.kind ~= 'select') then
    return console.notify_now('Harness: this agent offers no model option', 'info')
  end

  console.select(option.choices, {
    prompt = option.name or 'Model',
    format_item = function(choice)
      return view:_describe_choice(choice, option.current)
    end,
  }, function(choice)
    if choice then session:set_option(option.id, choice.value) end
  end)
end

return commands
