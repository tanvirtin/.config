local session = require('harness.types.session')

local eq = assert.are.same

describe('harness.types.session:', function()
  describe('title', function()
    it('keeps a plain title, without a closing period or extra spaces', function()
      eq('Crate tour and CLI dispatch', session.title('  Crate tour  and CLI dispatch. '))
      eq('Use Node.JS for the build', session.title('Use Node.JS for the build'))
      eq('Bump to v1.2', session.title('Bump to v1.2'))
    end)

    it('drops reasoning a model wrote ahead of its title', function()
      eq(
        'Crate tour and CLI command dispatch in `main.rs`',
        session.title(
          'We need title only. User asks tour crate and dispatch.Crate tour and CLI command dispatch in `main.rs`'
        )
      )
    end)

    it('is nothing for an empty or missing title', function()
      eq(nil, session.title(''))
      eq(nil, session.title(nil))
    end)
  end)
end)
