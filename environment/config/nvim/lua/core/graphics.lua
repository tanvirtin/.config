local graphics = {}

graphics.BASE = 0x5A0000
graphics.PROBE_MS = 300

local supported
local directory
local images = 0
local files = 0

local function apc(control, payload)
  return '\27_G' .. control .. (payload and (';' .. payload) or '') .. '\27\\'
end

local function file(bytes)
  if not directory then
    directory = vim.fn.tempname()
    vim.fn.mkdir(directory, 'p')
  end

  files = files + 1

  local path = string.format('%s/tty-graphics-protocol-%d', directory, files)
  local handle = assert(io.open(path, 'wb'))

  handle:write(bytes)
  handle:close()

  return vim.base64.encode(path)
end

local function probe()
  if not (vim.tty and vim.tty.query_apc and vim.api.nvim_ui_send) then return false end
  if #vim.api.nvim_list_uis() == 0 then return false end

  local id, answer = graphics.id(), nil
  local query = apc(string.format('a=q,i=%d,f=32,s=1,v=1,t=t', id), file('\0\0\0\0'))

  vim.tty.query_apc(query, { timeout = graphics.PROBE_MS }, function(response)
    local status = response:match('^\27_G[^;]*i=' .. id .. '[^;]*;(.-)%s*$')

    if not status then return false end

    answer = status == 'OK'

    return true
  end)

  vim.wait(graphics.PROBE_MS + 50, function()
    return answer ~= nil
  end, 10)

  return answer == true
end

function graphics.id()
  images = images + 1

  return graphics.BASE + images
end

function graphics.supported()
  if supported == nil then
    local ok, result = pcall(probe)

    supported = ok and result
  end

  return supported
end

function graphics.reset()
  supported = nil
end

function graphics.sequence(id, bytes, width, height, place, replaced)
  local control = string.format(
    'a=T,i=%d,p=1,f=32,s=%d,v=%d,t=t,c=%d,r=%d,z=%d,C=1,q=2',
    id,
    width,
    height,
    place.cols,
    place.rows,
    place.z or 0
  )

  return table.concat({
    '\27[?2026h\0277',
    string.format('\27[%d;%dH', place.row, place.col),
    apc(control, file(bytes)),
    replaced and apc(string.format('a=d,d=I,i=%d,q=2', replaced)) or '',
    '\0278\27[?2026l',
  })
end

function graphics.draw(id, bytes, width, height, place, replaced)
  vim.api.nvim_ui_send(graphics.sequence(id, bytes, width, height, place, replaced))
end

local DIACRITICS = {
  0x0305,
  0x030D,
  0x030E,
  0x0310,
  0x0312,
  0x033D,
  0x033E,
  0x033F,
  0x0346,
  0x034A,
  0x034B,
  0x034C,
  0x0350,
  0x0351,
  0x0352,
  0x0357,
  0x035B,
  0x0363,
  0x0364,
  0x0365,
  0x0366,
  0x0367,
  0x0368,
  0x0369,
  0x036A,
  0x036B,
  0x036C,
  0x036D,
  0x036E,
  0x036F,
  0x0483,
  0x0484,
}

graphics.PLACEHOLDER = 0x10EEEE
graphics.MAX_CELLS = #DIACRITICS

function graphics.upload_sequence(id, bytes, width, height, cols, rows)
  local control = string.format('a=T,U=1,i=%d,f=32,s=%d,v=%d,t=t,c=%d,r=%d,q=2', id, width, height, cols, rows)

  return apc(control, file(bytes))
end

function graphics.upload(id, bytes, width, height, cols, rows)
  vim.api.nvim_ui_send(graphics.upload_sequence(id, bytes, width, height, cols, rows))
end

function graphics.cells(cols, rows)
  if cols > graphics.MAX_CELLS or rows > graphics.MAX_CELLS then
    error(string.format('an image in cells is at most %d wide and tall', graphics.MAX_CELLS), 0)
  end

  local char = vim.fn.nr2char
  local lines = {}

  for row = 1, rows do
    local cells = {}

    for col = 1, cols do
      cells[col] = char(graphics.PLACEHOLDER) .. char(DIACRITICS[row]) .. char(DIACRITICS[col])
    end

    lines[row] = table.concat(cells)
  end

  return lines
end

function graphics.delete(id)
  vim.api.nvim_ui_send(apc(string.format('a=d,d=I,i=%d,q=2', id)))
end

return graphics
