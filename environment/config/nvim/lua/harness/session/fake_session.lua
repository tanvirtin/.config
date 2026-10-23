local async = require('harness.async')

local fake = {}

function fake.session(opts)
  opts = opts or {}

  local session = {
    id = 's1',
    state = 'idle',
    reloading = false,
    options = {},
    commands = {},
    history = {},
    notified = {},
    emitted = {},
    prompted = {},
    connection = opts.connection or {},
    approve = opts.approve,
  }

  function session:_notify(event)
    self.notified[#self.notified + 1] = event.kind
  end

  function session:_emit(event)
    self.emitted[#self.emitted + 1] = event
    self.history[#self.history + 1] = event
  end

  function session:_record_permission() end

  function session:idle()
    return self.state == 'idle'
  end

  function session:can(name)
    local connection = self.connection

    return type(connection.capabilities) == 'function' and connection:capabilities()[name] == true
      or (opts.can or {})[name] == true
  end

  function session:running()
    return self.state == 'running'
  end

  function session:prompt(text)
    self.prompted[#self.prompted + 1] = text
    local done = async.Future.new()
    done:set_result({})
    return done
  end

  return session
end

return fake
