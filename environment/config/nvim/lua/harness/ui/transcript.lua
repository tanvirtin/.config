local blocks = require('harness.ui.blocks')
local Document = require('harness.ui.document')
local follow = require('harness.follow')
local links = require('harness.ui.links')

local transcript = {}

transcript.FILETYPE = 'harness'

local views = {}

transcript.TICK_MS = 100

function transcript.render(history, title)
  return blocks.lines(blocks.build(history, title, { outputs = false }))
end

function transcript.view(buf)
  return views[buf or vim.api.nvim_get_current_buf()]
end

local function buffer_for(session)
  for buf, view in pairs(views) do
    if view.session == session and vim.api.nvim_buf_is_valid(buf) then return buf end
  end
end

function transcript.buffer_of(session)
  return buffer_for(session)
end

function transcript.view_of(session)
  local buf = buffer_for(session)

  return buf and views[buf] or nil
end

local function buffer_name(session)
  return string.format('harness://%s %s', session.key, session.title or 'untitled')
end

local last_buf

function transcript.to_bottom(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)), 0 })
  end
end

function transcript.window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if views[vim.api.nvim_win_get_buf(win)] then return win end
  end
end

function transcript.last()
  return last_buf and vim.api.nvim_buf_is_valid(last_buf) and views[last_buf] or nil
end

transcript.WINBAR = '%#UiAccent# i %#UiMuted#write to this session   %#UiAccent#<leader>. %#UiMuted#sessions'

local function last_usage(session)
  for i = #session.history, 1, -1 do
    if session.history[i].kind == 'usage' then return session.history[i] end
  end
end

function transcript.winbar(session)
  local parts = { transcript.WINBAR, '%=' }

  if session.external and follow.is_following(session) then parts[#parts + 1] = '%#UiWarn#⇄ external  ' end

  if session:running() then
    parts[#parts + 1] = '%#UiAccent#● running'
  elseif session.state == 'closed' then
    parts[#parts + 1] = '%#UiMuted#○ closed'
  else
    parts[#parts + 1] = '%#UiMuted#○ idle'
  end

  local usage = last_usage(session)

  if usage and usage.used and usage.size and usage.size > 0 then
    parts[#parts + 1] = string.format('%%#UiMuted#  ctx %d%%%%', math.floor(usage.used / usage.size * 100 + 0.5))
  end

  if usage and usage.cost then parts[#parts + 1] = string.format('%%#UiMuted#  $%.2f', usage.cost) end

  return table.concat(parts, '') .. ' '
end

local WINDOW_OPTIONS = {
  wrap = true,
  linebreak = true,
  number = false,
  relativenumber = false,
  conceallevel = 2,
  concealcursor = '',
  foldmethod = 'expr',
  foldexpr = 'v:lua.require\'harness.ui.transcript\'.foldexpr()',
  foldtext = 'v:lua.require\'harness.ui.transcript\'.foldtext()',
  foldlevel = 0,
  foldenable = true,
  fillchars = 'fold: ,eob: ',
}

local function set_winbar(win, session)
  local winbar = transcript.winbar(session)

  if vim.wo[win].winbar ~= winbar then
    vim.api.nvim_set_option_value('winbar', winbar, { scope = 'local', win = win })
  end
end

local FOLD_OPTIONS = { 'foldexpr', 'foldtext', 'foldlevel', 'foldenable', 'foldmethod' }

local function style(win, session)
  set_winbar(win, session)

  for option, value in pairs(WINDOW_OPTIONS) do
    if not option:find('^fold') then vim.api.nvim_set_option_value(option, value, { scope = 'local', win = win }) end
  end

  for _, option in ipairs(FOLD_OPTIONS) do
    if vim.wo[win][option] ~= WINDOW_OPTIONS[option] then
      vim.api.nvim_set_option_value(option, WINDOW_OPTIONS[option], { scope = 'local', win = win })
    end
  end
end

function transcript.foldexpr()
  local view = views[vim.api.nvim_get_current_buf()]

  return view and view.document:fold_level(vim.v.lnum - 1) or '0'
end

function transcript.foldtext()
  local hidden = vim.v.foldend - vim.v.foldstart + 1

  return { { string.format('  ⋯ %d more line%s', hidden, hidden == 1 and '' or 's'), 'UiMuted' } }
end

local function agent_label(session)
  local name = session.agent and session.agent.name or 'agent'

  return name:sub(1, 1):upper() .. name:sub(2)
end

local function turn_started(session)
  for i = #session.history, 1, -1 do
    local kind = session.history[i].kind

    if kind == 'prompt' or kind == 'user' then return session.times[i] end
  end
end

local function target_at(view, win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local document, dir = view.document, view.session.dir
  local kind, text = document.renderer:inline_at(row, col)

  if kind then
    local target = links.resolve(kind, text, dir)
    if target then return target end
  end

  local block = document:block_at(row)

  if not block then return nil end

  if block.kind == blocks.Block.KIND.diff then
    local line = document:diff_line(block, row)
    return links.resolve('link', block.path, dir) and { path = block.path, line = line } or nil
  end

  if block.kind == blocks.Block.KIND.tool and block.locations and block.locations[1] then
    local location = block.locations[1]
    return { path = location.path, line = location.line }
  end
end

function transcript.jump(direction, buf)
  buf = buf or vim.api.nvim_get_current_buf()

  local view = views[buf]

  if not view then return end

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local rows = {}

  for _, block in ipairs(view.document.blocks) do
    if block.kind == blocks.Block.KIND.prompt then rows[#rows + 1] = block.start end
  end

  if direction < 0 then
    for i = #rows, 1, -1 do
      if rows[i] < row then return vim.api.nvim_win_set_cursor(0, { rows[i] + 1, 0 }) end
    end
  else
    for _, candidate in ipairs(rows) do
      if candidate > row then return vim.api.nvim_win_set_cursor(0, { candidate + 1, 0 }) end
    end
  end
end

function transcript.activate(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  local view = views[buf]

  if not view then return false end

  local win = vim.api.nvim_get_current_win()
  local row = vim.api.nvim_win_get_cursor(win)[1]

  if vim.fn.foldclosed(row) ~= -1 then
    vim.cmd('normal! zo')
    return true
  end

  if links.open(target_at(view, win)) then return true end

  if vim.fn.foldlevel(row) > 0 then
    vim.cmd('normal! zc')
    return true
  end

  local block = view.document:block_at(row - 1)

  if block and block.folds and block.folds[1] then
    local fold_row = block.start + block.folds[1][1] + 1

    if vim.fn.foldclosed(fold_row) ~= -1 then
      vim.api.nvim_win_set_cursor(win, { fold_row, 0 })
      vim.cmd('normal! zo')
      vim.api.nvim_win_set_cursor(win, { row, 0 })
    else
      vim.api.nvim_win_set_cursor(win, { fold_row, 0 })
      vim.cmd('normal! zc')
      vim.api.nvim_win_set_cursor(win, { row, 0 })
    end

    return true
  end

  return false
end

function transcript.open_target(buf)
  local view = views[buf or vim.api.nvim_get_current_buf()]

  return view and links.open(target_at(view, vim.api.nvim_get_current_win())) or false
end

function transcript.yank(buf, register)
  buf = buf or vim.api.nvim_get_current_buf()

  local view = views[buf]

  if not view then return nil end

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local block = view.document:block_at(row)

  if not block then return nil end

  local lines = block.lines
  local first, last = blocks.fenced_at(lines, row - block.start + 1)
  local text = vim.list_slice(lines, first or 1, last or #lines)

  if not first and lines[1] and lines[1]:match('^>') then
    text = vim.tbl_map(function(line)
      return (line:gsub('^> ?', ''))
    end, text)
  end

  vim.fn.setreg(register or vim.v.register, text, 'l')

  return text, first ~= nil
end

function transcript.announce_waiting(session, buf)
  local waiting = session:waiting()

  if #waiting == 0 then return end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then return end
  end

  local what = waiting[1].title or waiting[1].tool or 'a tool'

  vim.schedule(function()
    vim.notify(string.format('Harness %s is waiting for your permission: %s', session.key, what), vim.log.levels.WARN)
  end)
end

local function create(session, opts)
  local buf = vim.api.nvim_create_buf(true, true)

  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = transcript.FILETYPE
  pcall(vim.api.nvim_buf_set_name, buf, buffer_name(session))

  local scheduled = false
  local document = Document(buf):attach()
  local timer = vim.uv.new_timer()
  local frame = 1
  local cache = {}
  local dirty = true
  local render

  local function resolve(kind, text)
    local target = links.resolve(kind, text, session.dir)

    return target and { icon = links.icon(target) } or nil
  end

  document.renderer.resolve = resolve

  local function step()
    if not vim.api.nvim_buf_is_valid(buf) then return timer:stop() end

    if not session:running() then
      timer:stop()
      return render()
    end

    frame = frame + 1
    document:tick({ frame = frame })
  end

  local function tick()
    local ok, err = pcall(step)

    if not ok then
      timer:stop()
      vim.notify('Harness: the transcript stopped animating: ' .. tostring(err), vim.log.levels.WARN)
    end
  end

  render = function()
    scheduled = false
    dirty = false

    if not vim.api.nvim_buf_is_valid(buf) then return end

    local last = vim.api.nvim_buf_line_count(buf)
    local wins = vim.fn.win_findbuf(buf)
    local following = vim.tbl_filter(function(win)
      return vim.api.nvim_win_get_cursor(win)[1] >= last
    end, wins)
    local running = session:running()

    document:write(
      blocks.build(
        session.history,
        session.title,
        { times = session.times, dir = session.dir, running = running, cache = cache }
      ),
      {
        running = running,
        frame = frame,
        started = turn_started(session),
        agent = agent_label(session),
        queue = session:queued(),
        waiting = session:waiting(),
      }
    )

    for _, win in ipairs(wins) do
      set_winbar(win, session)
    end

    for _, win in ipairs(following) do
      transcript.to_bottom(win)
    end

    if running and not timer:is_active() then
      timer:start(transcript.TICK_MS, transcript.TICK_MS, vim.schedule_wrap(tick))
    end
  end

  local view = { session = session, source_win = opts.source_win, document = document }

  view.unsubscribe = session:subscribe(function(event)
    if event.kind == 'title' then pcall(vim.api.nvim_buf_set_name, buf, buffer_name(session)) end
    if event.kind == 'reset' then cache = {} end
    if event.kind == 'waiting' then transcript.announce_waiting(session, buf) end
    dirty = true
    if scheduled then return end

    scheduled = true
    vim.schedule(render)
  end)

  for _, key in ipairs({ 'i', 'a', 'o', 'I', 'A', 'O' }) do
    vim.keymap.set('n', key, function()
      require('harness.ui.composer').open(session, { insert = true })
    end, { buffer = buf, desc = 'Write to this session' })
  end

  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, desc = desc })
  end

  map('<C-c>', function()
    require('harness.ui.composer').interrupt(session)
  end, 'Interrupt this session')
  map('<CR>', function()
    if not transcript.activate(buf) then vim.cmd('normal! j') end
  end, 'Open or fold what is under the cursor')
  map('gf', function()
    if not transcript.open_target(buf) then vim.notify('Harness: nothing to open here', vim.log.levels.INFO) end
  end, 'Open the file under the cursor in a new tab')
  map('gy', function()
    local text, code = transcript.yank(buf)

    if text then
      local what = code and 'code block' or 'block'
      vim.notify(string.format('Harness: yanked the %s (%d line%s)', what, #text, #text == 1 and '' or 's'))
    end
  end, 'Yank the code block under the cursor, or the whole block')
  map(']]', function()
    transcript.jump(1, buf)
  end, 'Next turn')
  map('[[', function()
    transcript.jump(-1, buf)
  end, 'Previous turn')

  local group = vim.api.nvim_create_augroup('harness.transcript.' .. buf, { clear = true })

  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    buffer = buf,
    callback = function()
      vim.bo[buf].buflisted = true
      style(vim.api.nvim_get_current_win(), session)

      if document:stale() then
        document:reset()
        dirty = true
      end

      if dirty then
        render()
      else
        document:decorate_visible()
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    buffer = buf,
    callback = function()
      last_buf = buf
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufUnload', 'BufDelete', 'BufWipeout' }, {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      view.unsubscribe()
      follow.stop(session)
      timer:stop()
      if not timer:is_closing() then timer:close() end
      document:dispose()
      views[buf] = nil
      if last_buf == buf then last_buf = nil end
      pcall(vim.api.nvim_del_augroup_by_id, group)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
      end)
    end,
  })

  views[buf] = view
  follow.start(session)
  render()

  return buf
end

function transcript.forget(session)
  local buf = buffer_for(session)

  if buf then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
end

function transcript.open(session, opts)
  opts = opts or {}

  local buf = buffer_for(session) or create(session, opts)

  if opts.source_win then
    views[buf].source_win = opts.source_win
    views[buf].source_buf = opts.source_buf
  end

  if not opts.background then
    vim.api.nvim_win_set_buf(0, buf)
    transcript.to_bottom(vim.api.nvim_get_current_win())
    views[buf].document:decorate_visible()
    last_buf = buf
  end

  return buf
end

return transcript
