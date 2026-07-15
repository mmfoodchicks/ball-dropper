# Orbfall Arena — Game Design Document

> Working title: **Orbfall Arena** (placeholder)

| | |
|---|---|
| **Platform** | Mobile (iOS / Android) |
| **Orientation** | Portrait or Landscape (recommended: Portrait for one-hand play) |
| **Genre** | Top-Down Roguelite · Wave-Based Arena Combat · Physics-Based Dropper / Multiplier System |
| **Target session length** | 3–5 minutes per run, designed for fast repeatable sessions |

## Core Fantasy

Fight through escalating enemy waves, collect large quantities of balls as currency, then strategically drop them into a physics-based multiplier board to exponentially increase rewards before choosing powerful upgrades and pushing deeper into harder encounters.

## Core Game Loop

1. Combat Phase (Waves)
2. Ball Dropper Phase (Every 5 Waves)
3. Upgrade Selection Phase
4. Repeat with Increased Difficulty
5. Boss Fight (Wave 15)
6. Meta Progression & Restart

---

## Combat Phase

### Arena

- Single-screen top-down arena
- No scrolling
- Enemy density increases over time

### Player Controls (Mobile)

- **Left thumb:** movement joystick
- **Right thumb:** aim direction or auto-aim
- Optional auto-fire for accessibility

### Player Stats

- Health
- Damage
- Fire Rate
- Movement Speed
- Critical Chance / Effects

### Enemy Types

**Peons**

- Spawn in large numbers
- Low health
- Do not drop balls
- Provide pressure and crowd-control challenges

**Elites**

- Fewer per wave
- Higher health and threat
- Drop balls on death
- Ball drop amount scales with wave number

**Boss (Wave 15)**

- High health
- Multiple attack phases
- Arena hazards
- Drops large rewards on defeat

---

## Ball Economy

### Ball Collection

- Balls are awarded instantly when elite enemies die
- Balls are automatically added to a **Ball Bank**
- No manual pickup, to keep pacing fast

### Scaling

- Early waves: dozens of balls
- Mid waves: hundreds
- Late waves: thousands+

---

## Dropper Phase (Every 5 Waves)

### Player Interaction

- Player chooses exact drop position
- Tap or drag horizontally to aim
- Balls drop from the top of the board
- No pegs; only gates and guiding physics lines

### Gate Types

**Multiplier Gates**

- Values range from ×1 to ×10
- Instantly multiply ball count when passed through
- Higher multipliers are rarer and riskier to reach

**Subtractor Gates**

- Values range from −1 to −15
- Each subtractor has a counter
- Deletes balls one by one until the counter reaches zero
- Gate becomes inactive afterward

**Bounceback Gate**

- Launches balls upward in random directions
- Balls can pass through gates again after bouncing
- Each ball can only be bounced once
- Prevents infinite loops and exploits

**??? Gate**

- Rare spawn per board
- Randomized effect on activation, such as:
  - Acts as a random multiplier or subtractor
  - Splits balls into multiple paths
  - Teleports balls to another area of the board
  - Converts some balls into bonus currency
  - Temporarily alters other gate values

### Guiding Physics Lines

- Randomly generated angled physics bars
- Redirect balls toward or away from gates
- Create soft funnels and risk/reward paths

### Fairness Rules

- Never block all exits
- Always at least one valid resolution path
- Board generation validates solvability before play

---

## Upgrade Phase

### Upgrade Selection

- Player is offered 3 random upgrades
- Player chooses 1 upgrade

### Reroll System

- Rerolling costs balls
- Cost increases per reroll
- Rerolls are optional and strategic

### Upgrade Categories

- Weapon modifications
- Passive stat boosts
- Utility abilities
- Dropper modifiers
- Synergy-based upgrades

---

## Progression Structure

### Waves

- 15 waves per run
- Difficulty increases every wave
- Dropper phase after waves 5 and 10
- Boss encounter at wave 15

---

## Boss Phase

### Boss Design

- Large health pool
- Multiple mechanics
- Forces movement mastery and positioning

### Victory Rewards

- Gold
- Upgrade materials
- Performance-based bonuses

---

## Meta Progression

### Persistent Currencies

- **Gold:** core permanent upgrades
- **Materials:** high-tier unlocks

### Permanent Upgrades

- Base stat increases
- Starting bonuses
- New dropper mechanics
- New gate types
- New playable characters

---

## Retention & Scale

### Why the System Works

- Extremely high numbers feel satisfying
- Player agency in drop placement
- Risk vs reward decisions every run
- Short sessions encourage replay
- Strong visual and audio feedback

### Future Expansion Ideas

- New biomes with unique dropper rules
- Boss-specific dropper boards
- Daily seeded runs
- Challenge modifiers
- Leaderboards or async competition
