local elicitation = require('harness.types.elicitation')

local eq = assert.are.same

local REQUEST = elicitation.Request({
  mode = 'form',
  message = 'Set up',
  fields = {
    elicitation.Field({
      key = 'db',
      kind = 'choice',
      title = 'Database',
      other = 'db_custom',
      options = { elicitation.Option({ value = 'pg', label = 'Postgres' }) },
    }),
    elicitation.Field({ key = 'db_custom', kind = 'text', title = 'Other' }),
    elicitation.Field({ key = 'ok', kind = 'boolean', description = 'Proceed?' }),
    elicitation.Field({ key = 'tags', kind = 'multi', title = 'Tags', options = {} }),
  },
})

describe('harness.types.elicitation:', function()
  it('sums up what was answered by the label of each question, folding in written answers', function()
    eq(
      {
        { label = 'Database', value = 'Postgres; v16' },
        { label = 'Proceed?', value = 'no' },
        { label = 'Tags', value = 'a, b' },
      },
      elicitation.summary(
        REQUEST,
        elicitation.accept({ db = 'pg', db_custom = 'v16', ok = false, tags = { 'a', 'b' } })
      )
    )

    eq(
      { { label = 'Database', value = 'mysql' } },
      elicitation.summary(REQUEST, elicitation.accept({ db_custom = 'mysql' }))
    )
  end)

  it('sums up nothing for a declined or cancelled question', function()
    eq({}, elicitation.summary(REQUEST, elicitation.decline()))
    eq({}, elicitation.summary(REQUEST, elicitation.cancel()))
  end)

  it('reads an answer from a plain table, and declines anything else', function()
    eq(elicitation.accept({ a = 1 }), elicitation.answer_of({ action = 'accept', content = { a = 1 } }))
    eq(elicitation.cancel(), elicitation.answer_of({ action = 'cancel' }))
    eq(elicitation.decline(), elicitation.answer_of('allow_once'))
    eq(elicitation.decline(), elicitation.answer_of({ action = 'maybe' }))
  end)

  it('labels a field by its title and question, or whichever it has', function()
    eq('Database', elicitation.label(REQUEST.fields[1]))
    eq('Proceed?', elicitation.label(REQUEST.fields[3]))
    eq('T: Q', elicitation.label(elicitation.Field({ key = 'k', kind = 'text', title = 'T', description = 'Q' })))
    eq('k', elicitation.label(elicitation.Field({ key = 'k', kind = 'text' })))
  end)
end)
