local Config = require('core.Config')

return Config({
  -- Wake the agent with a new turn when work it left running finishes after the
  -- turn ended. A wake is a paid turn, so they are capped per idle period.
  enabled = true,
  max = 3,
  max_items = 5,
  preview = 200,
  -- how long to wait for more completions before waking, so work that finishes
  -- together becomes one turn
  settle_ms = 400,
  -- Tool calls are watched too, so a background command that reports its exit
  -- after the turn ended wakes the agent. Off until an adapter is seen to send
  -- those updates after the turn, so the watch is not fiction.
  tools = false,
})
