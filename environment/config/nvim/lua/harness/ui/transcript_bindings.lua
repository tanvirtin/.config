local lazy = require('core.lazy')
local Window = require('core.Window')
local keymap = require('core.keymap')
local edits = lazy('harness.ui.edits')
local console = require('core.console')
local objects = lazy('harness.ui.objects')
local motions = lazy('harness.ui.motions')
local settings = require('harness.settings')
local code_blocks = lazy('harness.ui.code_blocks')

local bindings = {}

local MOTIONS = {
  { 'tool', 'tool call' },
  { 'edit', 'edit' },
  { 'waiting', 'request waiting for you' },
  { 'failed', 'failed tool call' },
}

local OBJECTS = {
  { 'turn', 'turn', 'The turn: your prompt and everything after it', 'The replies of the turn' },
  { 'message', 'message', 'The message with its marker', 'The message' },
  { 'tool', 'tool', 'The tool call with its header', 'The output of the tool call' },
}

local function motion_bindings(view, keys)
  local out = {}

  for _, entry in ipairs(MOTIONS) do
    for _, direction in ipairs({ { 'next', 1, 'Next' }, { 'previous', -1, 'Previous' } }) do
      out[#out + 1] = {
        keys[entry[1] .. '_' .. direction[1]],
        function()
          view.report(motions.jump(view, entry[1], direction[2]))
        end,
        direction[3] .. ' ' .. entry[2],
        { mode = { 'n', 'x' } },
      }
    end
  end

  return out
end

local function object_bindings(view, keys)
  local out = {}

  for _, entry in ipairs(OBJECTS) do
    out[#out + 1] = {
      keys[entry[1] .. '_inner'],
      function()
        view.report(objects.select(view, entry[2], false))
      end,
      entry[4],
      { mode = { 'o', 'x' } },
    }
    out[#out + 1] = {
      keys[entry[1] .. '_around'],
      function()
        view.report(objects.select(view, entry[2], true))
      end,
      entry[3],
      { mode = { 'o', 'x' } },
    }
  end

  return out
end

local function fold_bindings(view, keys)
  return {
    {
      keys.fold_tools,
      function()
        view.report(view:fold_tools(true))
      end,
      'Fold the output of every tool call',
    },
    {
      keys.unfold_tools,
      function()
        view.report(view:fold_tools(false))
      end,
      'Unfold the output of every tool call',
    },
    {
      keys.help,
      function()
        view:show_help()
      end,
      'List every key of this session',
    },
  }
end

function bindings.bindings(view)
  local session, report = view.session, view.report
  local keys = settings.keymaps:get('transcript')

  local list = {
    {
      keys.interrupt,
      function()
        if view.composer then view.composer.interrupt(session) end
      end,
      'Interrupt this session',
    },
    {
      keys.activate,
      function()
        if not view:activate() then Window.get_current():normal('j') end
      end,
      'Open or fold what is under the cursor',
    },
    {
      keys.bottom,
      function()
        local count = keymap.count()
        local window = Window.get_current()

        if count > 1 then return window:normal(count .. 'G') end

        view:land(window)
      end,
      'Go to the end, leaving room under the newest line',
    },
    {
      keys.open,
      function()
        local handled, ok = view:run_block_action('open')
        if not handled then ok = view:open_target() end
        if not ok then console.notify_now('Harness: nothing to open here', 'info') end
      end,
      'Open the file under the cursor in a new tab',
    },
    {
      keys.yank,
      function()
        local text, what = view:yank()

        if text then
          what = what or 'block'

          console.notify_now(string.format('Harness: yanked the %s (%d line%s)', what, #text, #text == 1 and '' or 's'))
        end
      end,
      'Yank the code block under the cursor, or the whole block',
    },
    {
      keys.next_turn,
      function()
        view:jump(1)
      end,
      'Next turn',
    },
    {
      keys.previous_turn,
      function()
        view:jump(-1)
      end,
      'Previous turn',
    },
    {
      keys.cycle_mode,
      function()
        session:cycle_mode()
      end,
      'Next session mode',
    },
    {
      keys.plan,
      function()
        view:toggle_plan()
      end,
      'Show or hide the plan',
    },
    {
      keys.permissions,
      function()
        view:show_permissions()
      end,
      'Show this session\'s permissions: grants, saved rules and decisions',
    },
    {
      keys.diff,
      function()
        local handled, ok, why = view:run_block_action('diff')
        if not handled then
          ok, why = edits.show_edit(view)
        end
        report(ok, why)
      end,
      'Open the edit under the cursor in vgit',
    },
    {
      keys.git_diff,
      function()
        report(view:git_diff())
      end,
      'Open the git diff of the file under the cursor in vgit',
    },
    {
      keys.changes,
      function()
        report(edits.show_changes(view))
      end,
      'Open every file this session changed in vgit',
    },
    {
      keys.block_next,
      function()
        report(code_blocks.jump(view, 1))
      end,
      'Next code block',
      { mode = { 'n', 'x' } },
    },
    {
      keys.block_previous,
      function()
        report(code_blocks.jump(view, -1))
      end,
      'Previous code block',
      { mode = { 'n', 'x' } },
    },
    {
      keys.block_inner,
      function()
        code_blocks.select(view, false)
      end,
      'Inside the code block',
      { mode = { 'o', 'x' } },
    },
    {
      keys.block_around,
      function()
        code_blocks.select(view, true)
      end,
      'The code block with its fences',
      { mode = { 'o', 'x' } },
    },
    {
      keys.insert,
      function()
        report(code_blocks.insert(view))
      end,
      'Insert the code block below the cursor in your code',
    },
    {
      keys.apply,
      function()
        report(code_blocks.apply(view))
      end,
      'Ask the agent to apply the code block to your code',
    },
    {
      keys.revert,
      function()
        report(edits.revert(view))
      end,
      'Revert the edit under the cursor, or this turn\'s edits, after a preview in vgit',
    },
    {
      keys.quickfix,
      function()
        report(edits.quickfix(view, edits.SCOPE.turn))
      end,
      'Send this turn\'s edits to the quickfix list',
    },
    {
      keys.quickfix_session,
      function()
        report(edits.quickfix(view, edits.SCOPE.session))
      end,
      'Send every edit of this session to the quickfix list',
    },
    {
      keys.fork,
      function()
        report(view:fork())
      end,
      'Fork the session from the reply under the cursor (or the one before this prompt)',
    },
    {
      keys.model,
      function()
        view:pick_model()
      end,
      'Session model',
    },
  }

  vim.list_extend(list, motion_bindings(view, keys))
  vim.list_extend(list, object_bindings(view, keys))
  vim.list_extend(list, fold_bindings(view, keys))

  return list
end

return bindings
