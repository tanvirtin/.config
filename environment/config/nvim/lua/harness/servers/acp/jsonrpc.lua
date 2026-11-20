local jsonrpc = {}

jsonrpc.METHOD_NOT_FOUND = -32601
jsonrpc.INTERNAL_ERROR = -32603

local VERSION = '2.0'

function jsonrpc.request(id, method, params)
  local message = { jsonrpc = VERSION, id = id, method = method }

  if params ~= nil then message.params = params end

  return message
end

function jsonrpc.notification(method, params)
  local message = { jsonrpc = VERSION, method = method }

  if params ~= nil then message.params = params end

  return message
end

function jsonrpc.result(id, result)
  return {
    jsonrpc = VERSION,
    id = id,
    result = result == nil and vim.empty_dict() or result,
  }
end

function jsonrpc.error(id, code, message)
  return { jsonrpc = VERSION, id = id, error = { code = code, message = message } }
end

function jsonrpc.is_request(message)
  return message.method ~= nil and message.id ~= nil
end

function jsonrpc.is_response(message)
  return message.method == nil and message.id ~= nil
end

function jsonrpc.encode(message)
  return vim.json.encode(message)
end

function jsonrpc.decode(text)
  return vim.json.decode(text)
end

return jsonrpc
