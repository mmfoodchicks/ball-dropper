# Orbfall Arena

Playable Godot 4 prototype of the **Orbfall Arena** design: a portrait-mode,
top-down roguelite where you fight 15 escalating waves, bank balls from elite
kills, and multiply the bank on physics-based dropper boards before picking
upgrades — boss on wave 15, persistent gold/material meta between runs.

- Design document: [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md)
- Design → code mapping and tuning notes: [`docs/IMPLEMENTATION_NOTES.md`](docs/IMPLEMENTATION_NOTES.md)

## Engine choice

The brief asked for Epic's engine *or another reputable phone game engine*.
This prototype uses **Godot 4** (4.3+, tested config targets 4.4):

- First-class 2D renderer and tooling — this game is entirely 2D (top-down
  arena + a physics dropper board), which is Unreal's weakest fit and Godot's
  strongest.
- Ships to **iOS and Android** out of the box via official export templates.
- Text-based scenes/scripts keep the whole project reviewable in git, and the
  engine runs headless, so the game loop is CI-verifiable (see below).
- MIT-licensed, no revenue share, small runtime (~40 MB APKs vs. 150 MB+).

Everything gameplay-relevant lives in engine-agnostic terms (state machines,
plain math, data tables), so a port to Unity or Unreal later is a translation
job, not a redesign. If you'd rather have this on Unreal or Unity anyway, say
so and the same design maps over.

## Running it

1. Install [Godot 4.4+](https://godotengine.org/download) (standard build).
2. Open this folder in the editor (`project.godot`) and press **F5**, or run
   `godot --path .` from a terminal.

The window is the phone-shaped 480×854 design resolution. Everything is
procedurally drawn and generated — there are no binary assets at all.

### Controls

| Input | Combat | Dropper |
|---|---|---|
| Left thumb / WASD·arrows | move | — |
| Right thumb | manual aim + fire | — |
| No aim input | auto-aim + auto-fire | — |
| Tap / drag anywhere | — | set drop position (also mid-drop) |
| DROP button | — | release the whole ball bank |

Mouse emulates touch, so everything is playable on desktop for testing.

## Verification

Two headless checks (also run in CI, `.github/workflows/verify.yml`):

```sh
# Pure-logic suite: balance formulas, board generation + fairness
# validation, ball physics termination, upgrade pool, save roundtrip.
godot --headless --path . --script res://tests/smoke.gd

# Full end-to-end run: a bot plays title -> waves 1-15 -> both dropper
# boards -> upgrades -> boss -> victory at 8x speed and exits 0 on success.
godot --headless --path . -- --autoplay --god --turbo --quit-on-end
```

Static checks: `pip install "gdtoolkit==4.*"` then `gdlint src tests` and
`gdformat --check src tests` (a `.gdlintrc` is included).

## Mobile export

Portrait orientation, touch emulation and the mobile renderer are already set
in `project.godot`. To ship a device build: Editor → Export → add the Android
(or iOS) preset, install the official export templates, and export — no code
changes needed. Keystore/signing follows the standard Godot docs.

## Project layout

```
project.godot          # portrait 480x854, canvas_items stretch, autoloads
main.tscn              # single minimal scene; everything is built from code
src/
  main.gd              # core-loop state machine + autoplay/turbo harness
  balance.gd           # EVERY tuning knob and scaling formula
  run_state.gd         # one run's stats, bank, flags
  upgrades.gd          # in-run upgrade pool (5 GDD categories) + offers
  autoload/meta.gd     # gold, materials, permanent upgrades, unlocks (JSON save)
  autoload/sfx.gd      # procedural sound effects (generated WAVs, no assets)
  combat/              # arena controller, hero, enemies, boss, bullets, hazards
  dropper/             # board generation + validation, ball physics, gates
  ui/                  # HUD, virtual joysticks, all screens (built in code)
  fx/                  # floating numbers, particles, screen shake
tests/smoke.gd         # headless logic test suite
docs/                  # design doc + implementation notes
```

## Open design questions

Parked decisions where the GDD allows more than one reading — current
prototype behavior noted; see `docs/IMPLEMENTATION_NOTES.md` for detail:

1. **Upgrade cadence** — upgrades only follow dropper boards (waves 5/10), so
   2 picks per run. Intended, or add lighter per-wave picks?
2. **Post-boss dropper** — the GDD lists boss-specific boards under future
   ideas; currently the boss bank converts straight to gold on victory.
3. **Defeat consolation** — dying still pays `wave×12 + 5%` of the bank in
   gold so early runs progress the meta. Keep?
4. **Reroll pricing** — 30 balls at wave 5, 150 at wave 10, doubling per
   reroll. Cheap enough to be tempting, expensive enough to sting?
5. **Orientation** — portrait-locked per the GDD recommendation; landscape
   would need a HUD relayout only.
