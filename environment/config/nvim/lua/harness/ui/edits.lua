local lazy = require('core.lazy')

local vgit = lazy('harness.vgit')
local Window = lazy('core.Window')
local core_text = lazy('core.text')
local buffers = lazy('core.buffers')
local console = lazy('core.console')
local quickfix = lazy('core.quickfix')
local settings = lazy('harness.settings')
local EditLog = lazy('harness.edits.EditLog')
local Block = lazy('harness.transcript.Block')

local edits = {}

edits.SCOPE = { edit = 'edit', turn = 'turn', session = 'session' }

local function cursor_block(view)
  return view.document:block_at(Window.get_current():get_cursor()[1] - 1)
end

function edits.at(view)
  local block = view and cursor_block(view)

  if not block or not block.id then return nil end

  local files = {}

  for _, candidate in ipairs(view.document.blocks) do
    if candidate.kind == Block.KIND.diff and candidate.id == block.id and candidate.edit then
      files[#files + 1] = candidate.edit
    end
  end

  return #files > 0 and files or nil, block.id
end

function edits.show_edit(view)
  local files = edits.at(view)

  if not files then return false, 'no edit here' end

  return vgit.show(files)
end

function edits.show_changes(view)
  if not view then return false, 'no session here' end

  local files = view.edits:changes(view.session.history)

  if #files == 0 then return false, 'this session has not changed any file' end

  return vgit.show(files)
end

local function opens_turn(block)
  return block.kind == Block.KIND.prompt and not block.steered and block.event ~= nil
end

function edits.turn_range(view)
  local blocks, block = view.document.blocks, cursor_block(view)

  if not block then return nil end

  local first

  for i = block.index, 1, -1 do
    if opens_turn(blocks[i]) then
      first = blocks[i]
      break
    end
  end

  if not first then return nil end

  for i = first.index + 1, #blocks do
    if opens_turn(blocks[i]) then return first.event, blocks[i].event - 1 end
  end

  return first.event, #view.session.history
end

function edits.scoped(view, scope)
  local history = view.session.history

  if scope == edits.SCOPE.session then return EditLog.tools(history) end

  if scope == edits.SCOPE.edit then
    local _, id = edits.at(view)

    return vim.tbl_filter(function(edit)
      return edit.id == id
    end, id and EditLog.tools(history) or {})
  end

  local from, to = edits.turn_range(view)

  return from and EditLog.tools(history, from, to) or {}
end

function edits.scope_at(view)
  return edits.at(view) and edits.SCOPE.edit or edits.SCOPE.turn
end

function edits.apply(files)
  local kept = 0

  for _, file in ipairs(files) do
    local buffer = buffers.load(file.filename)
    local unsaved = buffer:is_modified()

    buffer:break_undo()
    buffer:set_lines(file.new_lines)

    if unsaved then
      kept = kept + 1
    else
      buffer:save()
    end
  end

  return kept
end

local function describe(plan, confirm)
  local text = string.format('%s reverts %s', confirm, core_text.plural(plan.undone, 'change'))

  return #plan.skipped > 0 and string.format('%s, skips %d', text, #plan.skipped) or text
end

function edits.revert(view, scope)
  if not view then return false, 'no session here' end

  scope = scope or edits.scope_at(view)

  local chosen = edits.scoped(view, scope)

  if #chosen == 0 then return false, 'no ' .. scope .. ' edits to revert here' end

  buffers.checktime()

  local plan = view.edits:revert_plan(chosen)

  if #plan.files == 0 then
    return false, #plan.skipped > 0 and ('nothing to revert: ' .. plan.skipped[1].reason) or 'nothing to revert'
  end

  local confirm = settings.keymaps:get('transcript').revert_confirm
  local ok, why = vgit.show(plan.files, {
    keymaps = {
      {
        mode = 'n',
        key = confirm,
        handler = function(diff_view)
          local kept = edits.apply(plan.files)

          diff_view:destroy()
          console.notify_now(
            'Harness: reverted'
              .. (kept > 0 and string.format('; %s left unsaved', core_text.plural(kept, 'buffer')) or '')
          )
        end,
      },
    },
  })

  if not ok then return false, why end

  console.notify_now('Harness: ' .. describe(plan, confirm))

  return true
end

function edits.quickfix(view, scope)
  if not view then return false, 'no session here' end

  scope = scope or edits.SCOPE.turn

  local items = view.edits:locations(view.session.history, edits.scoped(view, scope))

  if #items == 0 then return false, 'no ' .. scope .. ' edits to list here' end

  quickfix.set(items, { title = string.format('Harness %s: %s edits', view.session.key, scope), open = true })

  return true
end

return edits
