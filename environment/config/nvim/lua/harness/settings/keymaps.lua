local Config = require('core.Config')

return Config({
  transcript = {
    write = { 'i', 'a', 'o', 'I', 'A', 'O' },
    interrupt = '<C-c>',
    activate = '<CR>',
    open = 'gf',
    yank = 'gy',
    next_turn = ']]',
    previous_turn = '[[',
    cycle_mode = '<S-Tab>',
    options = 'go',
    plan = 'gp',
  },
  composer = {
    send = '<CR>',
    steer = '<C-s>',
    interrupt = '<C-c>',
    cycle_mode = '<S-Tab>',
    slash = '/',
    close = 'q',
  },
})
