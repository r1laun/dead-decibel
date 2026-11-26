# ОБЪЕКТ-07 · Design Direction v4 ("НИИ-07 / Field Instrument")

The old look (generic dark SaaS cards, rounded pills, pink mannequin monster, flat grey rooms)
is the anti-reference. Everything below replaces it.

## World (the fiction everything is drawn from)
A sealed late-1980s Soviet underground medical research institute, "НИИ-07". Institutional
two-tone paint (dark teal-green lower wall panel up to ~1.4 m, dirty cream above, a thin
dark separating stripe), terrazzo/tile floors with drain grates, exposed ceiling pipes and
cable trays, stencilled Cyrillic signage (room names, numbers, arrows, "ВЫХОД"), sodium
amber work lamps vs cold fluorescent tubes, red emergency beacons near the airlock.
Decay: water stains, rust drips, scattered papers, blood drag marks leading somewhere.

## Palette (tokens — use these names in code, never ad-hoc colours)
| Token | Hex | Use |
|---|---|---|
| INK | #0A0C0B | deepest UI background, scrim base |
| PANEL | #111513 | instrument/panel surfaces (alpha 0.88–0.94) |
| PANEL_HI | #1A201D | hovered/selected surface |
| RULE | #D9D2C1 @ 12% | hairline rules/borders |
| PAPER | #DDD6C4 | primary text (aged paper) |
| PAPER_DIM | #9C978A | secondary text |
| PAPER_MUTE | #625F57 | tertiary / disabled |
| SODIUM | #E3A23B | interact, focus, selection, accent (the "lamp") |
| SIGNAL | #CC3A2E | danger, monster, wounds |
| PHOSPHOR | #8EDC9E | radar trace, allies, success/cleared |
| COLD | #7FB8C8 | breath / cold fluorescent / vents |
| WALL_TEAL | #2E4743 | world: lower wall paint |
| WALL_CREAM | #B9B09A | world: upper wall paint |

Contrast: PAPER on PANEL ≥ 10:1, PAPER_DIM on PANEL ≥ 5:1. Never put grey text on coloured fills.

## Type (fonts in res://assets/fonts, all have Cyrillic)
- Display / stencil headings: **Oswald** (variable, use weight 500–700), UPPERCASE,
  letter spacing +1…+3 px. Titles, room names, section headers, big status words.
- Body / UI copy: **IBM Plex Sans** Regular & SemiBold. 15–17 px body, never < 12 px.
- Data / measurement only: **IBM Plex Mono** (codes, timers, %, coordinates, slot numbers).
Scale: 12 / 14 / 16 / 20 / 28 / 44 / 64.

## Shape & depth
- Square-ish instrument geometry: corner radius 2–4 px on panels, 0 on rules. No pills,
  no 12 px "SaaS cards", no cards-inside-cards.
- Elevation = one hairline border OR a soft offset shadow, never both.
- Corner tick marks (small L-brackets) are the signature frame for focusable/important panels.
- No emoji / unicode glyph icons — use the PNG icons in res://assets/icons or draw vectors.
- No eyebrow/kicker labels above headings; no 01/02/03 numbering for decoration.

## Motion
- One authored moment per screen; exponential ease-out (Tween TRANS_EXPO / EASE_OUT),
  150–350 ms for UI, never animate from invisible-on-load for gameplay-critical info.
- Danger states pulse (sine), calm states are still. Respect a "reduce motion" setting
  (SaveState.reduce_motion) by disabling pulses/shake.

## HUD principles (Operate mode: scanability over expression)
- Diegetic & quiet: the screen is mostly the world. Info appears when it matters.
- Corners: top-left = objectives (collapsible "dossier"), top-centre = threat whisper,
  top-right = radar instrument, bottom-centre = inventory + held item, centre = reticle +
  contextual prompt with key/button glyph.
- Touch targets ≥ 56 px (primary 88 px), 8 px+ gaps, thumb zones; floating joystick.
- Every control shows its binding (keyboard / gamepad / touch) in the prompt.
