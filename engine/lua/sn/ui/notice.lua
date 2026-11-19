local lazy = require('core.lazy')

local console = lazy('core.console')

local notice = {}

notice.PREFIX = 'Harness: '

function notice.warn(message)
  console.notify(notice.PREFIX .. message, 'warn')
end

function notice.info(message)
  console.notify_now(notice.PREFIX .. message, 'info')
end

return notice
