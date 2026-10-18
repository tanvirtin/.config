local Surface = require('surfaces.Surface')
local View = require('ui.View')
local LinesComponent = require('ui.components.LinesComponent')
local compact = require('compact')
local schema = require('nvim_mcp.schema')

local Panel = Surface:extend()

function Panel:constructor(opts)
  local instance = Surface.constructor(self, { kind = 'panel', title = opts.title or 'Panel', owner = opts.owner })

  instance._lines = opts.lines or vim.split(opts.markdown or '', '\n', { plain = true })
  instance._filetype = opts.filetype or 'markdown'
  instance._width = opts.width or '70vw'
  instance._height = opts.height

  return instance
end

function Panel:_content()
  return vim.list_extend({ '# ' .. self.title, '' }, vim.deepcopy(self._lines))
end

function Panel:open()
  local lines = self:_content()

  self._body = LinesComponent({
    lines = lines,
    filetype = self._filetype,
    wrap = true,
    cursorline = false,
    border = 'rounded',
  })
  self._view = View()
  self._view:_render({
    component = self._body,
    mode = 'popup',
    width = self._width,
    height = self._height or math.min(#lines + 2, math.floor(vim.o.lines * 0.7)),
  })

  for _, key in ipairs({ 'q', '<Esc>' }) do
    self._body:set_keymap('n', key, function()
      self:close()
    end, 'Close')
  end

  self:set_state('ready')

  return self
end

Panel.COMMANDS = {
  write = {
    summary = 'Replace the text with markdown, or add it at the end with append.',
    params = {
      { name = 'markdown', type = schema.str() },
      { name = 'append', type = schema.bool(), optional = true },
    },
    run = function(self, args)
      local lines = vim.split(args.markdown, '\n', { plain = true })

      self._lines = args.append and vim.list_extend(self._lines, lines) or lines
      self._body:set_content(self:_content())
    end,
  },
}

function Panel:snapshot(budget)
  return string.format('%s: panel "%s" [%s]\n', self.id, self.title, self.state)
    .. compact.text(table.concat(self._lines, '\n'), budget or compact.BUDGET)
end

return Panel
