local widgets = require('ui.widgets')

local eq = assert.are.same

describe('ui.widgets:', function()
  it('draws a bar from a percentage and a width', function()
    eq('[added]██████[/][muted]░░░░[/]', widgets.expand('{bar:60:10}'))
    eq('[added][/][muted]░░░░[/]', widgets.expand('{bar:0:4}'))
    eq('[added]████[/][muted][/]', widgets.expand('{bar:900:4}'))
  end)

  it('fills a bar over a cycle of ticks when the percentage is @', function()
    eq('[added][/][muted]░░░░░░░░░░[/]', widgets.expand('{bar:@:10}', 0))
    eq('[added]█████[/][muted]░░░░░[/]', widgets.expand('{bar:@:10}', 10))
    eq('[added]██████████[/][muted][/]', widgets.expand('{bar:@:10}', 20))
    eq('[added][/][muted]░░░░░░░░░░[/]', widgets.expand('{bar:@:10}', 21))
  end)

  it('scales a sparkline to its tallest value', function()
    eq('▃▅█', widgets.expand('{spark:3,5,8}'))
    eq('▁▁', widgets.expand('{spark:0,0}'))
  end)

  it('repeats a character, and draws a rule', function()
    eq('▓▓▓', widgets.expand('{rep:▓:3}'))
    eq('────', widgets.expand('{rule:4}'))
    eq('════', widgets.expand('{rule:4:═}'))
  end)

  it('turns a spinner a frame a tick, through the busy loader frames', function()
    local frames = require('ui.pixel.indicators').GLYPHS.busy

    eq('⠋', widgets.expand('{spin}', 0))
    eq('⠙', widgets.expand('{spin}', 1))
    eq(frames[6], widgets.expand('{spin}', 5))
    eq('⠋', widgets.expand('{spin}', #frames))
  end)

  it('expands inside a line, and leaves what it does not know alone', function()
    eq('a ⠋ b [x] {y}', widgets.expand('a {spin} b [x] {y}', 0))
    eq('{spinner}', widgets.expand('{spinner}'))
    eq('{Bar:1}', widgets.expand('{Bar:1}'))
  end)
end)
