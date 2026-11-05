local AnswerDestination = require('harness.ui.AnswerDestination')

local eq = assert.are.same

local function prompt(opts)
  opts = opts or {}

  local fake = { stopped = false, submitted = {} }

  function fake:is_open()
    return opts.open ~= false
  end

  function fake:writing()
    return opts.writing ~= false and { name = 'Which database?' } or nil
  end

  function fake:writing_label()
    return 'Which database?'
  end

  function fake:stop_writing()
    self.stopped = true
  end

  function fake:submit_text(text)
    self.submitted[#self.submitted + 1] = text

    return opts.accepts ~= false, opts.accepts == false and 'not a number' or nil
  end

  return fake
end

local function destination(fake)
  return AnswerDestination({ key = 'h1', dir = '/w', can = function() end }, {}, nil, fake)
end

describe('harness.ui.AnswerDestination:', function()
  it('answers the prompt it was given, keeps no draft, and shows the question as its label', function()
    local fake = prompt()
    local answering = destination(fake)

    eq(fake, answering:answers())
    eq('Which database?', answering:label())
    eq(false, answering:keeps_draft())
    eq(false, answering:history_hint())
    eq('write your answer', answering:placeholder())
  end)

  it('hints at answering while a field is being written, and like a prompt once it is not', function()
    local shown = { keys = { steer = '<C-s>', interrupt = '<C-c>' }, send = '<CR>', inserting = false }
    local labels = {}
    local function add(lhs, label)
      labels[#labels + 1] = lhs .. ' ' .. label
    end

    destination(prompt()):hints(add, shown)
    eq({ '<CR> answer' }, labels)

    local session_running = {
      running = function()
        return false
      end,
      can = function() end,
    }
    local idle = AnswerDestination(session_running, {}, nil, prompt({ writing = false }))

    labels = {}
    idle:hints(add, shown)
    eq({ '<CR> send' }, labels)
  end)

  it('submits the text to the prompt, and says why when it cannot', function()
    local accepting = prompt()
    local ok, how = destination(accepting):submit('postgres')

    eq({ true, 'answered' }, { ok, how })
    eq({ 'postgres' }, accepting.submitted)

    local refusing = prompt({ accepts = false })
    local refused, why = destination(refusing):submit('x')

    eq({ false, 'not a number' }, { refused, why })
    eq({ false, AnswerDestination.EMPTY }, { destination(prompt()):submit('') })
    eq({ false, AnswerDestination.GONE }, { destination(prompt({ open = false })):submit('x') })
  end)

  it('stops the prompt from waiting for text when it closes', function()
    local fake = prompt()

    destination(fake):closing()

    eq(true, fake.stopped)
  end)
end)
