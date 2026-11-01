local Config = require('core.Config')

return Config({
  height = 10,
  -- how long the composer waits before deciding that focus left it for good, so
  -- a surface that takes focus and gives it back does not close it
  leave_ms = 50,
  -- how long the composer takes to grow to its height when it opens; 0 opens it at once
  ease_ms = 120,
})
