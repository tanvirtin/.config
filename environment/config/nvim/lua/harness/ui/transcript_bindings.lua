local lazy = require('core.lazy')
local Window = require('core.Window')
local keymap = require('core.keymap')
local edits = lazy('harness.ui.edits')
local console = require('core.console')
local settings = require('harness.settings')
local code_blocks = lazy('harness.ui.code_blocks')

local bindings = {}

function bindings.bindings(view)
  local session, report = view.session, view.report
  local keys = settings.keymaps:get('transcript')

  return {
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
end

return bindings
