# Design system

One look across the harness: flat, chunky, stepped, and built from TV static.
Every colour, timing, density, layer and glyph comes from this folder. Modules
above it (`ui/`, `harness/`, `surfaces/`) compose these tokens and never invent
their own values. `ui/design/usage_spec.lua` fails the build when they do.

```lua
local design = require('ui.design')

design.layer.of('effect')
design.static.density('whisper')
design.motion.DURATION.slow
design.glyph.join({ 'claude', '12s' })
design.color.source('text.muted')
```

## Principles

- **One state, one look.** A state draws the same way everywhere it appears.
- **Signal over decoration.** Lines and bars mark structure, not ornament.
  Prefer space and tint to borders.
- **Static is the motion language.** Things arrive by tuning in, finish by
  breaking into noise, fail by glitching and leave by dissolving.
- **Reduced motion is first class.** Every effect holds still, or falls back to
  its first frame, when `motion.reduced` is set.
- **Degrade to text.** Pixel components fall back to glyphs when the terminal
  cannot draw images.

## Tokens

### Colour (`color.lua`)

Semantic roles named after Zed's theme schema. Each role points at a group from
the colour scheme the user runs, so the harness follows their theme.

| Role | Source | Ui groups |
|---|---|---|
| `text` | Normal | UiMarkdownTableCell |
| `text.muted` | Comment | UiMuted, UiMarkdownQuote |
| `text.accent` | Special | UiAccent, UiMarkdownBullet |
| `text.title` | Title | UiTitle |
| `text.path` | Directory | UiPath |
| `text.link` | Underlined | UiMarkdownLink |
| `surface.background` | NormalFloat | UiNormal |
| `element.selected` | CursorLine | UiSelected |
| `border` | FloatBorder | UiBorder |
| `success` `error` `warning` `info` `hint` | Diagnostic* | UiToolDone, UiError, UiWarn, UiInfo, UiHint |
| `created` `deleted` | Added, Removed | UiAdded, UiRemoved |

Derived colours mix the text colour into the background by a named strength
(`color.MIX`): `surface` 0.05, `elevated` 0.09, `tint` 0.1, `code` 0.12,
`border` 0.16, `flash` 0.24, `rule` 0.3, `fade` 0.45, `glint` 0.6,
`thought` 0.62. Any role colour below a 3:1 contrast ratio (`color.CONTRAST`,
WCAG large text) is lifted toward the text until it reads.

### Motion (`motion.lua`)

| Token | Value | Used for |
|---|---|---|
| `STEP_MS` | 100 | the stepped clock: loaders, mascot, ambient static |
| `FRAME_MS` | 33 | the animator frame: transient effects |
| `DURATION.fast` | 150 | text fade-in, toast in |
| `DURATION.moderate` | 250 | selection tune-in, toast out, listing floor |
| `DURATION.slow` | 450 | finish static, tune-in on open, closing card, loader finish |
| `DURATION.deliberate` | 800 | mascot wane, recent-failure window |
| `EASING.standard` | out_cubic | most transitions |
| `EASING.emphasized` | in_out | squashes and collapses |

### Static (`static.lua`)

Four presets, used as the density of glitched characters or pixel blocks.

| Preset | Density | Used for |
|---|---|---|
| `whisper` | 0.3 | live thought top line, picker listing, a clean finish, faint rules |
| `light` | 0.45 | a failed finish, plan step done, a loading row |
| `medium` | 0.6 | selection tune-in, streamed thought tune-in, the picker band, turn rules |
| `heavy` | 0.85 | tune-in on open, closing card squash |

Transient static reseeds every frame (`static.seed(now)`); ambient static
reseeds every step (`static.seed(now, true)`).

### Layers (`layer.lua`)

Extmark priorities, lowest first. Draw at a named layer, never a number.

`gutter` 10, `decoration` 20, `surface` 50, `body` 90, `highlight` 100,
`output` 120, `link` 190, `syntax` 200, `line` 250, `mark` 300, `emphasis` 350,
`effect` 400, `animation` 4000.

Static overlays always sit on `effect`, so no effect can be hidden by text
styling.

### Glyphs (`glyph.lua`)

| Group | Glyphs |
|---|---|
| `STATUS` | done ✓, failed ✗, pending ○, partial ◐, running ⠶, attention ◆, selected ◉, current ●, more ⋯, info ℹ, hint ◇, warning ! |
| `TREE` | gutter │, branch ├, branch_end └ |
| `LINE` | rule ─, heavy ━, dashed ┄, dotted ┈, rail ▎, bar │ |
| `BOX`, `GRID` | rounded card corners, square table borders |
| `SEPARATOR` | ` · `, joined with `glyph.join(parts)` |

## Components

| Component | Where | Notes |
|---|---|---|
| Loader | `ui/pixel/indicators.lua`, `theme.loader` | busy ring, thinking, waiting, loading, idle, rail; one per state |
| Mascot | `harness/transcript/mascot.lua` | the hollow: working line, five acts, moods work/wait/fail |
| Static | `ui/glitch.lua`, `ui/pixel/static.lua` | scramble, overlay cells and snow for text; blocks and noise for pixels |
| Rule | `harness/transcript/rule.lua` | `static` for turns, `faint` for artifacts |
| Surface | `ui/pixel/surface.lua` | elevations `surface`, `raised`, `modal` |
| Ring, Badge, Card, Bar | `ui/pixel/components/` | catalog components for `ui_draw` |

## Patterns

| State | Look |
|---|---|
| running | busy ring in `text.accent` |
| thinking | drifting static in the thought tint |
| waiting on you | scanline in `warning`, rail on the card |
| loading | sweeping column, snow under the replay line |
| idle | still block in `text.muted` |
| failed | `error`, eyes shut, glitching row |

| Moment | Transition |
|---|---|
| a view opens a session | tune in out of `heavy` static over `DURATION.slow` |
| text streams in | fade from `fade` strength over `DURATION.fast` |
| a tool or turn finishes | its row breaks into `whisper` static that clears |
| something fails | `light` static in `error` |
| a card closes | flash, scramble, squash to a line, a dot |
| the selection moves | the label tunes in out of `medium` static |

## Adding to the system

1. Need a value? Use a token. If none fits, add it here first and say what it is
   for in the tables above.
2. Need a new look for a state? Reuse the state's existing look. A new state
   gets a row in Patterns before it gets code.
3. Run `make test`; `usage_spec.lua` names any raw priority, density, separator
   or glyph that slipped in.
