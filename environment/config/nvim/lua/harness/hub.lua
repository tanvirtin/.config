local Session = require('harness.Session')
local SessionHub = require('harness.SessionHub')

local default = SessionHub():register_events()

local hub = { SENT = Session.SENT }

function hub.configure(overrides)
  return default:configure(overrides)
end

function hub.dir()
  return default:dir()
end

function hub.editor_server(key)
  return default:editor_server(key)
end

function hub.workspace(dir)
  return default:workspace(dir)
end

function hub.admit(session)
  return default:admit(session)
end

function hub.running()
  return default:running()
end

function hub.admit_waiting()
  return default:admit_waiting()
end

function hub.start(opts)
  return default:start(opts)
end

function hub.starting(key)
  return default:starting(key)
end

function hub.load(opts)
  return default:load(opts)
end

function hub.fork(session, message_id)
  return default:fork(session, message_id)
end

function hub.list(dir, agent_name)
  return default:list(dir, agent_name)
end

function hub.delete(opts)
  return default:delete(opts)
end

function hub.prompt(session, text, context)
  return default:prompt(session, text, context)
end

function hub.send(session, text, context, opts)
  return default:send(session, text, context, opts)
end

function hub.reload(session)
  return default:reload(session)
end

function hub.session(key)
  return default:session(key)
end

function hub.sessions(dir)
  return default:sessions(dir)
end

function hub.discard(session)
  return default:discard(session)
end

function hub.close(key)
  return default:close(key)
end

function hub.shutdown()
  return default:shutdown()
end

return setmetatable(hub, {
  __index = function(_, key)
    if key == 'config' then return default.config end
  end,
  __newindex = function(table, key, value)
    if key == 'config' then
      default.config = value
    else
      rawset(table, key, value)
    end
  end,
})
