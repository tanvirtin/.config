local connection = {}

connection.METHODS = {
  'capabilities',
  'new_session',
  'load_session',
  'fork_session',
  'list_sessions',
  'close_session',
  'delete_session',
  'prompt',
  'steer',
  'cancel',
  'set_option',
  'use_model',
  'attach',
  'detach',
  'close',
}

function connection.missing(candidate)
  local out = {}

  for _, name in ipairs(connection.METHODS) do
    if type(candidate) ~= 'table' or type(candidate[name]) ~= 'function' then out[#out + 1] = name end
  end

  return out
end

return connection
