# Implementation Notes

How the [game design document](GAME_DESIGN.md) maps onto the Godot 4
prototype, plus the interpretation calls made where the GDD leaves room.
All numbers quoted here live in `src/balance.gd` — that file is the single
tuning surface.

## GDD → code map

| GDD system | Where | Status |
|---|---|---|
| Core loop state machine | `src/main.gd` | ✅ title → combat → dropper (5/10) → upgrade → … → boss (15) → victory/defeat → meta |
| Single-screen arena, no scrolling | `src/combat/arena.gd` | ✅ fixed 480×854 playfield |
| Left move / right aim / auto-aim / auto-fire | `src/ui/joystick.gd`, `src/combat/hero.gd` | ✅ dynamic twin sticks, auto-aim + auto-fire when right thumb idle, keyboard fallback |
| Player stats (HP/dmg/fire rate/speed/crit) | `src/run_state.gd` | ✅ plus pierce, projectiles, crit damage, damage taken, regen |
| Peons (swarm, no drops) | `src/combat/enemy.gd` | ✅ separation-steered chasers |
| Elites drop wave-scaled balls | `src/combat/enemy.gd` (`brute`, `spitter`) | ✅ charger + ranged kiter archetypes, gold carrier ring |
| Instant ball award, no pickup | `src/combat/arena.gd` `on_enemy_died` | ✅ bank += drop, floater + sfx |
| Ball scaling dozens → hundreds → thousands | `Balance.elite_ball_drop` | ✅ `(8+2w)·w^1.15`; asserted in smoke tests |
| Boss wave 15: phases + hazards | `src/combat/boss.gd`, `hazard.gd` | ✅ 3 HP-gated phases: rings/fans → charges + summons → spiral + burn zones |
| Dropper every 5 waves | `src/main.gd` | ✅ after waves 5 and 10 |
| Choose exact drop position (tap/drag) | `src/dropper/dropper.gd` | ✅ also re-aimable mid-stream |
| Multiplier gates x1–x10, rare highs | `src/dropper/board_gen.gd` | ✅ weight table; x1 kept as a dud; high gates get "guard" deflector lines (riskier to reach) |
| Subtractor gates -1..-15 with counters | `board_gen.gd` + `dropper.gd` | ✅ deletes *real* balls one by one, deactivates at 0 |
| Bounceback gate, once per ball | `dropper.gd` `_apply_bounce` | ✅ random upward launch, clears the ball's gate-trigger memory so it can re-enter gates (GDD), single use prevents loops |
| ??? gate, rare, random effects | `dropper.gd` `_apply_mystery` | ✅ all five GDD effects: random mult / random subtract / split / teleport / balls→gold / temporary +1 to all multiplier gates |
| Guiding physics lines, no pegs | `board_gen.gd` | ✅ 4–6 random angled bars + guards; never intersect gates |
| Fairness: never block exits, validate before play | `board_gen.gd` `validate` | ✅ phantom-ball sim must reach exit from ≥3 of 9 drop positions; 6 retries then a safe sparse fallback; anti-stuck nudges guarantee resolution in play |
| Upgrade phase: 3 offered, pick 1 | `src/upgrades.gd`, `src/ui/screens.gd` | ✅ 35 upgrades across the 5 GDD categories ("Wider Choice" unlock makes it 4), plus 16 hidden positive/negative synergy pairs (`UpgradePool.SYNERGIES`) revealed only after committing |
| New biomes (GDD future idea) | `Balance.BIOMES`, `Balance.ENEMY_KINDS`, `arena.gd` | ✅ 3 biomes shuffled per run (one per 5-wave segment): arena tint + per-biome rosters over 15 data-driven enemy kinds with 11 behavior archetypes |
| Reroll costs balls, escalating | `Balance.reroll_cost` | ✅ 30 (wave 5) / 150 (wave 10) base, ×2 per reroll within a phase |
| 15 waves, difficulty per wave | `Balance` wave formulas | ✅ counts + HP + speed scale per wave |
| Victory rewards: gold, materials, performance | `src/main.gd` `_on_boss_defeated` | ✅ waves + boss + 10% ball conversion + HP-based performance bonus; 3 materials (+1 for keeping HP ≥50% through the boss) |
| Meta: gold upgrades / material unlocks | `src/autoload/meta.gd` | ✅ 6 stat tracks; unlocks: guaranteed ??? gate, 4th upgrade option, character BLITZ |
| New playable characters | `Balance.CHARACTERS` | ✅ RANGER default; BLITZ, BASTION, JINX, VOLT unlockable, each with an innate perk |
| Strong audio/visual feedback | `src/autoload/sfx.gd`, `src/fx/fx.gd` | ✅ procedural SFX, floaters, bursts, shake, gate flashes |
| Daily seeds / leaderboards / biomes | — | ⏳ future; all RNG already flows through seedable `RandomNumberGenerator`s |

## Interpretation calls (flagged in README too)

- **"Multiply ball count when passed through"** is implemented per-ball: each
  ball carries a value and a gate multiplies that value. Chained gates
  compound, which is what makes drop placement matter.
- **Upgrades happen after each dropper only** (waves 5 and 10) — a strict
  reading of the GDD core loop. Meta progression carries power growth
  elsewhere.
- **Defeat still pays out** (`wave×12 + 5%` of bank) so first sessions
  progress the meta; victory pays roughly 10× more.
- **Boss balls skip a third dropper** and convert at victory; boss-specific
  boards are listed as future expansion in the GDD.
- **Elites exist from wave 1** so the first board always has a bank to drop.

## The chunking model (thousands of balls, mobile-safe)

Simulating 20k rigid bodies isn't viable on phones. The dropper streams at
most `MAX_SIM_BALLS = 420` physical balls; each carries
`chunk = ceil(bank / 420)` real balls as its value.

- Multiplier gates multiply the ball's value — visually identical, numerically exact.
- Subtractor counters bite in units of *real* balls: a `-15` gate eats 15
  units across however many physical balls that takes, then deactivates.
- The ??? split effect splits a ball's value across two physical balls.

So the numbers scale unboundedly while the sim cost stays constant. Physics
is a bespoke circle-vs-segment integrator (`board_gen.gd`) rather than Godot
physics: deterministic, headless-testable, and ~100× cheaper than RigidBody2D
for this shape of problem.

## Economy reference (defaults)

| Knob | Value |
|---|---|
| Elite drop | `(8 + 2w) · w^1.15 · bounty` → w1 ≈ 10, w5 ≈ 114, w10 ≈ 396, w14 ≈ 750 |
| Elites per wave | `1 + floor((w-1)/3)`, cap 6 |
| Boss ball drop | 6 000 |
| Reroll | 30 / 150 base, ×2 each |
| Victory gold | `180 + 300 + 10%·bank·(1+golden touch) + up to 200 performance` |
| Defeat gold | `12·wave + 5%·bank` |
| Meta costs | 80–120 gold base, ×1.5–1.6 per level; unlocks 3/5/8 materials |

A won run banks ~20–35k balls → ~2.5–4k gold, i.e. several meta levels.
Numbers are first-pass: tuned by simulation and arithmetic, not by hands-on
device play yet — expect a balancing pass.

## Verification story

- `tests/smoke.gd` (headless, no rendering): balance scaling targets, 40
  generated boards × option combos hold every invariant + pass solvability
  validation, seed determinism, wall containment, V-trap escape, upgrade
  pool integrity, meta save roundtrip.
- `--autoplay --god --turbo --quit-on-end` plays a real full run through the
  actual game scenes with a kiting bot and exits 0 only after victory flow +
  meta rewards complete.
- `gdparse`/`gdlint`/`gdformat` clean (config in `.gdlintrc`).
- CI: `.github/workflows/verify.yml` runs all of the above on every push.

Known gaps for a production pass: real art/audio, haptics, tutorial/FTUE,
difficulty tuning on device, object pooling if enemy counts grow, and the
GDD future list (biomes, boss boards, daily seeds, challenge modifiers,
leaderboards).
