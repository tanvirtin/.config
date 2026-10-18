local compact = require('compact')
local context = require('harness.context')

local transcript = {}

local views = {}

local diff_text = (vim.text and vim.text.diff) or vim.diff

local function diff_block(diff)
  local old, new = diff.old, diff.new

  if old ~= '' and old:sub(-1) ~= '\n' then old = old .. '\n' end
  if new ~= '' and new:sub(-1) ~= '\n' then new = new .. '\n' end

  local block = { '```diff', '--- ' .. tostring(diff.path) }

  vim.list_extend(block, vim.split(vim.trim(diff_text(old, new, { ctxlen = 2 }) or ''), '\n', { plain = true }))
  block[#block + 1] = '```'

  return block
end

local PLAN_MARK = { completed = 'x', in_progress = '~' }

local function plan_block(entries)
  local block = { '**plan**' }

  for _, entry in ipairs(entries) do
    block[#block + 1] = string.format('- [%s] %s', PLAN_MARK[entry.status] or ' ', entry.content)
  end

  return block
end

function transcript.render(history, title)
  local lines = { '# ' .. compact.line(title or 'Harness', 200), '' }
  local in_text = false
  local diffs_shown = {}

  local function text(chunk)
    local parts = vim.split(chunk, '\n', { plain = true })

    if in_text then
      lines[#lines] = lines[#lines] .. parts[1]
    else
      lines[#lines + 1] = parts[1]
    end

    for i = 2, #parts do
      lines[#lines + 1] = parts[i]
    end

    in_text = true
  end

  local function block(items)
    if in_text then lines[#lines + 1] = '' end

    for _, item in ipairs(items) do
      vim.list_extend(lines, vim.split(item, '\n', { plain = true }))
    end

    lines[#lines + 1] = ''
    in_text = false
  end

  local function quote(prompt)
    local quoted = {}

    for _, line in ipairs(vim.split(vim.trim(context.strip(prompt)), '\n', { plain = true })) do
      quoted[#quoted + 1] = '> ' .. line
    end

    block(quoted)
  end

  local function show_diffs(event)
    if diffs_shown[event.id] then return end

    for _, diff in ipairs(event.diffs) do
      diffs_shown[event.id] = true
      block(diff_block(diff))
    end
  end

  local RENDER = {
    prompt = function(event)
      quote(event.text)
    end,
    user = function(event)
      quote(event.text)
    end,
    message = function(event)
      text(event.text)
    end,
    tool_call = function(event)
      block({ '`-> ' .. compact.line(event.title or event.name or 'tool', 200) .. '`' })
      show_diffs(event)
    end,
    tool_update = function(event)
      if event.status == 'failed' then
        block({ '*failed:* `' .. compact.line(event.title or event.name or event.id, 200) .. '`' })
      end

      show_diffs(event)
    end,
    plan = function(event)
      block(plan_block(event.entries))
    end,
    permission = function(event)
      if not event.allowed then block({ '*refused:* `' .. compact.line(event.tool, 200) .. '`' }) end
    end,
    stop = function(event)
      block({ '*' .. tostring(event.reason) .. '*' })
    end,
    error = function(event)
      block({ '**error:** ' .. event.message })
    end,
  }

  for _, event in ipairs(history) do
    if RENDER[event.kind] then RENDER[event.kind](event) end
  end

  local out = {}

  for _, line in ipairs(lines) do
    vim.list_extend(out, vim.split(line, '\n', { plain = true }))
  end

  return out
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

local WINDOW_OPTIONS =
  { wrap = true, linebreak = true, number = false, relativenumber = false, winbar = transcript.WINBAR }

local function style(win)
  for option, value in pairs(WINDOW_OPTIONS) do
    vim.api.nvim_set_option_value(option, value, { scope = 'local', win = win })
  end
end

local function create(session, opts)
  local buf = vim.api.nvim_create_buf(true, true)

  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].filetype = 'markdown'
  pcall(vim.api.nvim_buf_set_name, buf, buffer_name(session))

  local scheduled = false

  local function render()
    scheduled = false

    if not vim.api.nvim_buf_is_valid(buf) then return end

    local last = vim.api.nvim_buf_line_count(buf)
    local following = vim.tbl_filter(function(win)
      return vim.api.nvim_win_get_cursor(win)[1] >= last
    end, vim.fn.win_findbuf(buf))

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, transcript.render(session.history, session.title))
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false

    for _, win in ipairs(following) do
      transcript.to_bottom(win)
    end
  end

  local view = { session = session, source_win = opts.source_win }

  view.unsubscribe = session:subscribe(function(event)
    if event.kind == 'title' then pcall(vim.api.nvim_buf_set_name, buf, buffer_name(session)) end
    if scheduled then return end

    scheduled = true
    vim.schedule(render)
  end)

  for _, key in ipairs({ 'i', 'a', 'o', 'I', 'A', 'O' }) do
    vim.keymap.set('n', key, function()
      require('harness.ui.composer').open(session, { insert = true })
    end, { buffer = buf, desc = 'Write to this session' })
  end

  local group = vim.api.nvim_create_augroup('harness.transcript.' .. buf, { clear = true })

  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    buffer = buf,
    callback = function()
      vim.bo[buf].buflisted = true
      style(vim.api.nvim_get_current_win())
      render()
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    buffer = buf,
    callback = function()
      last_buf = buf
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      view.unsubscribe()
      views[buf] = nil
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  views[buf] = view
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
    last_buf = buf
  end

  return buf
end

return transcript
