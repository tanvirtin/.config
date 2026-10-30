local lazy = require('core.lazy')

local Component = lazy('ui.Component')
local Element = lazy('ui.elements.Element')
local LayoutSpec = lazy('ui.layout.LayoutSpec')

local LinesComponent = Component({})

function LinesComponent:mount()
  if self._mounted then return end

  self._element = Element({
    buf_options = {
      modifiable = false,
      buflisted = false,
      bufhidden = 'wipe',
      filetype = self.props.filetype,
    },
    win_options = vim.tbl_extend('force', {
      winhl = 'Normal:UiNormal,FloatBorder:UiBorder,CursorLine:UiSelected',
      cursorline = self.props.cursorline ~= false,
      number = false,
      relativenumber = false,
      signcolumn = 'no',
      wrap = self.props.wrap == true,
    }, self.props.win_options or {}),
    win_plot = {
      border = self.props.border,
      title = self.props.border and self.props.title and (' ' .. self.props.title .. ' ') or nil,
      title_pos = self.props.border and self.props.title and 'left' or nil,
      focusable = true,
    },
  })
  self._mounted = true
end

function LinesComponent:get_layout_spec()
  return LayoutSpec.view(self._element, { flex = 1, focus = self.props.focus ~= false })
end

function LinesComponent:on_mount()
  if self.props.lines then self:set_content(self.props.lines, self.props.highlights) end
end

function LinesComponent:set_content(lines, highlights)
  if vim.iter(lines):any(function(line)
    return line:find('\n', 1, true) ~= nil
  end) then
    local split = {}

    for _, line in ipairs(lines) do
      vim.list_extend(split, vim.split(line, '\n', { plain = true }))
    end

    lines, highlights = split, nil
  end

  self.props.lines, self.props.highlights = lines, highlights

  self:with_element(function(element)
    element:set_lines(lines)
    element:clear_extmark_highlights()

    for _, mark in ipairs(highlights or {}) do
      element:place_extmark_highlight({ hl = mark.hl, row = mark.row, col_range = { from = mark.from, to = mark.to } })
    end
  end)
end

function LinesComponent:get_lnum()
  return self:with_element(function(element)
    return element:get_lnum()
  end)
end

function LinesComponent:set_lnum(lnum)
  self:with_element(function(element)
    element:set_lnum(lnum)
  end)
end

function LinesComponent:set_keymap(mode, key, handler, desc)
  self:with_element(function(element)
    element:set_keymap(mode, key, handler, desc)
  end)
end

function LinesComponent:focus()
  self:with_element(function(element)
    element:focus()
  end)
end

function LinesComponent:is_valid()
  return self._element ~= nil and self._element:is_valid()
end

function LinesComponent:unmount()
  if not self._mounted then return end

  if self._element then self._element:unmount() end

  self._mounted = false
end

return LinesComponent
