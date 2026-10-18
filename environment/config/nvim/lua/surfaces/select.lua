local select = {}

function select.ui_select(items, opts, on_choice)
  opts = opts or {}

  local format = opts.format_item or tostring
  local answered = false

  local function answer(item, index)
    if answered then return end

    answered = true
    on_choice(item, index)
  end

  local entries = {}

  for index, item in ipairs(items) do
    entries[index] = { label = format(item), value = index }
  end

  local picker = require('surfaces').pick({
    title = opts.prompt and vim.trim(opts.prompt:gsub(':%s*$', '')) or 'Select',
    items = entries,
    hints = { { '<CR>', 'choose' }, { '<C-n>/<C-p>', 'move' }, { '<Esc>', 'dismiss' } },
    on_select = function(entry)
      answer(items[entry.value], entry.value)
    end,
  })

  picker:on('close', function()
    if picker:chosen() == nil then vim.schedule(function()
      answer(nil, nil)
    end) end
  end)

  return picker
end

function select.setup()
  vim.ui.select = select.ui_select
end

return select
