local lazy = require('core.lazy')

local agent = lazy('sn.agent')
local follow = lazy('sn.follow')
local hub = lazy('sn.session.hub')
local store = lazy('sn.session.store')
local EditLog = lazy('sn.edits.EditLog')
local permissions = lazy('sn.permissions')
local TurnIndex = lazy('sn.session.TurnIndex')
local Subagents = lazy('sn.session.Subagents')
local permission_rules = lazy('sn.permission_rules')

local client = {}

function client.dir()
  return hub.dir()
end

function client.start(opts)
  return hub.start(opts)
end

function client.load(opts)
  return hub.load(opts)
end

function client.fork(session, message_id)
  return hub.fork(session, message_id)
end

function client.list(dir, agent_name)
  return hub.list(dir, agent_name)
end

function client.delete(opts)
  return hub.delete(opts)
end

function client.close(key)
  return hub.close(key)
end

function client.send(session, text, context, opts)
  return hub.send(session, text, context, opts)
end

function client.session(key)
  return hub.session(key)
end

function client.sessions(dir)
  return hub.sessions(dir)
end

function client.notify(session, update)
  return session:_notify(update)
end

function client.on(names, callback)
  return store.on(names, callback)
end

function client.events()
  return store.EVENT
end

function client.agent(name)
  return agent.get(name)
end

function client.agents()
  return agent.names()
end

function client.follow(session, opts)
  return follow.start(session, opts)
end

function client.unfollow(session)
  return follow.stop(session)
end

function client.following(session)
  return follow.is_following(session)
end

function client.describe_permission(request)
  return permissions.describe(request)
end

function client.permission_choices(request)
  return permissions.choices(request)
end

function client.rules_supported(agent_spec)
  return permission_rules.supported(agent_spec)
end

function client.rules(agent_spec, dir)
  return permission_rules.load(agent_spec, dir)
end

function client.remove_rule(rule)
  return permission_rules.remove(rule)
end

function client.edit_log(lines_of)
  return EditLog(lines_of)
end

function client.edit_tools(history, from, to)
  return EditLog.tools(history, from, to)
end

function client.turns(history, index)
  return TurnIndex.of(history, index)
end

function client.active_subagent_states()
  return Subagents.ACTIVE
end

return client
