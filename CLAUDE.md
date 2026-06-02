# Gaelic Football — Architecture & Conventions

A 2D Gaelic football game built in **Godot 4** with **GDScript**. Two career modes
sit on top of one shared simulation core.

> **Status: early development.** Structure, autoloads, input map, menu flow,
> and the playable match scene exist. Career modes are stubbed (push_warning).
> Quick Play is the current entry point for testing the match. Stubs are marked
> with `TODO` and emit a `push_warning` so unfinished paths are obvious at runtime.

---

## Game modes

0. **Quick Play** — development shortcut. Drops straight into a match with no
   career context. Career mode is `NONE`; no `CareerManager` data is used.
   Press **Esc** to return to the main menu. Remove or hide this button once
   career modes are implemented.
1. **Manager Career** — Football-Manager-style. Run a club or county team:
   tactics, squad, fixtures, transfers. Play matches yourself or simulate them.
2. **Player Career** — control one player across their whole career: club
   championship, with county call-ups if they're good enough.

Career modes (1 & 2) read from the **same** career save (`Career` resource). The
mode only changes which slice the UI exposes — not the underlying data model.
This is deliberate: it keeps systems shared and makes multiplayer feasible later.

---

## Folder structure

```
res://
├── project.godot          # Config, autoloads, input map
├── icon.svg
├── CLAUDE.md
├── autoloads/             # Global singletons (registered in project.godot)
│   ├── game_manager.gd    #   top-level state + scene routing
│   ├── career_manager.gd  #   owns the active career save & career systems
│   └── match_engine.gd    #   match results: simulate() or play()
├── scenes/                # Gameplay scenes (visual, interactive)
│   └── match/             #   the playable 2D match (presentation only)
├── ui/                    # Menus & HUD
│   ├── main_menu/
│   └── settings/
├── systems/               # Career/data systems — NON-visual logic & data
│   ├── career/            #   Career root save object
│   └── data/              #   data resources: PlayerData, ClubData, FixtureData
└── assets/                # Art, audio, fonts
```

**Rule of thumb for where code goes:**
- Draws to screen or takes input → `scenes/` or `ui/`.
- Pure logic or data, no nodes → `systems/`.
- Global, single-instance, reachable everywhere → `autoloads/`.

---

## Scene structure

Scenes are grouped by purpose, not by feature:

```
scenes/match/       — the playable 2D match (CharacterBody2D players, ball, pitch)
ui/main_menu/       — main menu
ui/settings/        — settings screen
ui/[feature]/       — one subfolder per screen or reusable HUD widget
```

**Within a scene folder**, always keep `.tscn` and `.gd` together and named
identically (`match.tscn` + `match.gd`). One script per scene root — if a child
node needs significant logic, extract it to its own sub-scene rather than
attaching a second script to the same tree.

**Scene responsibilities:**
- Read career data from `CareerManager` (via passed references or signals).
- Render, animate, play sound.
- Translate player input into calls on `CareerManager` or `MatchEngine`.
- Never own persistent state — destroy cleanly on `queue_free()`.

**Adding a new scene:**
1. Create `ui/[name]/[name].tscn` (menu) or `scenes/[name]/[name].tscn` (gameplay).
2. Add a `const SCENE_[NAME]` path constant in `game_manager.gd` and a routing
   method (`open_[name]()`). Do not call `change_scene_to_file()` directly.
3. Wire navigation: the scene that opens it calls `GameManager.open_[name]()`;
   the scene itself calls `GameManager.return_to_*()` to exit.
4. Register any persistent data the scene needs in `systems/data/` first.

---

## Data layer

All persistent game state lives in **Resource subclasses** under `systems/`:

| Class          | File                            | Contains                               |
|----------------|---------------------------------|----------------------------------------|
| `Career`       | `systems/career/career.gd`      | Root save object — owns everything below |
| `ClubData`     | `systems/data/club_data.gd`     | Club/county identity + squad           |
| `PlayerData`   | `systems/data/player_data.gd`   | Player attributes                      |
| `FixtureData`  | `systems/data/fixture_data.gd`  | Scheduled match + result               |

**How scripts access data:**
- `CareerManager.active_career` is the single live instance.
- Scenes receive data via method arguments or by connecting to `CareerManager`
  signals — they do not reach into `CareerManager` directly (no
  `CareerManager.active_career.clubs[0].squad`-style chains in scene scripts).
- `MatchEngine` receives `ClubData` objects passed to it; it does not look up
  clubs itself.

**Where data does NOT live:**
- Not in autoload member variables (except `CareerManager.active_career`).
- Not in scene `@export` vars that aren't wired through `CareerManager`.
- Not in a `Dictionary` or `Array` with loose string keys — use typed `Resource`
  fields so the schema is visible and serialisation is guaranteed.

---

## Autoloads (the three pillars)

| Singleton        | Responsibility                                              | Must NOT do                          |
|------------------|-------------------------------------------------------------|--------------------------------------|
| `GameManager`    | High-level state machine, scene routing, chosen career mode | Domain logic (squads, match maths)   |
| `CareerManager`  | Owns the active `Career`; save/load; calendar; transfers    | Render anything                      |
| `MatchEngine`    | Produce match results (headless sim **or** hand off to play)| Render or read input (lives in scene)|

Keep autoloads thin and few. They are global state — every one added is a
dependency everything can reach into. Prefer plain `Resource`/`Node` classes in
`systems/` and pass them around explicitly.

---

## Design principles

1. **Simulation ≠ presentation.** `MatchEngine.simulate()` is deterministic and
   headless; `MatchEngine.play()` hands off to the match *scene*. Both return the
   **same result shape** (`{home_score, away_score, events}`, where a score is
   `{goals, points}`). Leagues, stats and multiplayer never care which path ran.
2. **Data is Resources.** Everything persistent (`PlayerData`, `ClubData`,
   `FixtureData`, `Career`) is a `Resource` with `@export`ed fields and no
   behaviour. Free serialisation → easy saves and network transfer.
3. **One shared career model.** Manager and Player modes are views over the same
   `Career`. Don't fork the data model per mode.
4. **Route through GameManager.** Scene changes go through
   `GameManager.change_scene()`, not scattered `change_scene_to_file()` calls, so
   transitions/loading/sync have a single home.
5. **Controller-first input.** Use named input actions only — never hard-code
   keys or buttons in gameplay code. Adding a new action means adding it to the
   input map, not branching on raw events.

---

## Multiplayer design principle

Network careers — multiple users running parallel careers simultaneously, like
FM network mode — are a planned feature. Every decision below is made with that
in mind.

**Rules that must hold now, before multiplayer exists:**

1. **All career state is JSON-serialisable and owned by a named profile.**
   `Career` (and everything it references) must round-trip cleanly through
   `JSON.stringify` / `JSON.parse`. This means: no Node references, no
   `Callable`s, no GDScript objects with hidden state stored in `Career` fields.
   When multiplayer lands, each peer's career is identified by a player profile
   name; the server is the authority; peers replicate from it.

2. **No career state in scenes.** Scenes are created and destroyed. Any state
   that matters beyond a scene's lifetime belongs in `CareerManager.active_career`,
   not in a node's member variable.

3. **Deterministic simulation.** `MatchEngine.simulate(home, away, seed)` must
   produce identical output for the same inputs on every peer. No `randf()` or
   `Time.get_unix_time_from_system()` — use the seeded `RandomNumberGenerator`
   from `systems/` passed explicitly.

4. **Single authority per career.** `CareerManager` owns and mutates the
   `Career`. Scenes read from it (via signals or passed references) but never
   write to it directly. This is the invariant that makes a future server/client
   split straightforward.

Avoid anything that fights this: global mutable state in scene scripts,
non-deterministic match logic, or business logic that assumes a single local user.

---

## Coding conventions (GDScript)

- **Typed GDScript everywhere**: `var x: int`, `func f(a: String) -> void:`.
- **Naming**: files & vars/functions `snake_case`; classes & nodes `PascalCase`;
  constants & enum members `CONSTANT_CASE`; private members prefixed `_`.
- **`class_name`** for data/system types so they're usable as `@export` types.
- **Signals over polling**: managers emit (`state_changed`, `day_advanced`,
  `match_finished`); UI connects. Don't reach up into managers' internals.
- **Unique node names** (`%NodeName`) for nodes a script touches; wire button
  presses via scene `[connection]`s to `_on_*` handler methods.
- **Doc comments** with `##` on every script and public member.
- **Tabs** for indentation (Godot default). Two blank lines between funcs.

### Adding a feature — the pattern
1. New persistent data? Add/extend a `Resource` in `systems/data/`.
2. New logic? Plain class in `systems/`, or extend the relevant autoload (only if
   it's genuinely global). Emit a signal for results.
3. New screen? A scene under `ui/` (menu) or `scenes/` (gameplay); reach it via
   `GameManager`.
4. New control? Add a named action to the input map; read it by name.

---

## What NOT to do

These are the failure modes most likely to make the codebase hard to extend or
break multiplayer later. Treat them as hard rules.

**1. Do not hardcode career state in scenes.**
```gdscript
# BAD — state lives on the node; lost when the scene reloads or another player
#        loads their career
var current_club: ClubData

# GOOD — read from the authority; the scene is stateless
var current_club: ClubData:
    get: return CareerManager.active_career.managed_club
```

**2. Do not use autoloads for gameplay logic.**
Autoloads are global state. Logic that belongs to one match, one career, or one
screen should live in a system class or scene script and be passed around
explicitly. If you find yourself adding a `var current_ball_holder: PlayerData`
to `GameManager`, stop — it belongs in the match scene or a match-state object.

**3. Do not call `change_scene_to_file()` outside `GameManager`.**
Scattered scene changes make transitions, loading screens, and network sync
impossible to retrofit. Always route through `GameManager.change_scene()`.

**4. Do not store non-serialisable values in `Career` or its children.**
Node references, `Callable`s, and engine objects that don't survive
`ResourceSaver` / `JSON` will silently break saves and future network sync. Keep
`Career` and its Resource tree pure data: primitives, typed arrays, and other
Resources only.

**5. Do not use `randf()` or wall-clock time in simulation paths.**
`MatchEngine.simulate()` must be deterministic. Use a `RandomNumberGenerator`
initialised with the fixture seed and pass it explicitly through the call chain.

---

## Input map

Actions are defined in `project.godot` and edited via *Project Settings → Input
Map*. Gameplay must reference these names, never raw keys/buttons.

| Action      | Keyboard         | Controller                     | Notes                                      |
|-------------|------------------|--------------------------------|--------------------------------------------|
| `move_*`    | WASD             | Left stick + D-pad             |                                            |
| `pass`      | Left click       | A button                       | Tap = hand pass; double-tap+hold = kick pass (power from hold) |
| `shoot`     | Right click      | B button                       | Hold = point attempt; double-tap+hold 2nd = goal attempt (power from hold). Power bar fills fast with a sweet spot (green marker on the HUD bar); overcharging — holding to the very top — sprays the shot, so release a touch early for accuracy. Score type is decided by the ball's actual arc height where it crosses the goal line (over the crossbar = point, under = goal), not by the attempt intent |
| `sprint`    | Shift            | Right trigger                  | Dash burst (any player), then a cooldown. The cooldown is per-player and recovers in the background regardless of who you're controlling; it starts full and is topped up when you take control of a player, so a switched-to player's dash is always ready. Availability shown by the ring around the controlled player |
| `solo`      | C                | X button                       | Resets carry step counter (unlimited)      |
| `bounce`    | V                | Y button                       | Resets carry step counter (once/possession)|
| `tackle`    | F                | Right bumper                   | Must first shadow the carrier within a close radius for a moment to engage — a ring around the controlled defender fills as you close, then goes solid when a tackle can land — pressing then starts the timing-contest tackle. Does not gate charging down a shot from the front (a separate front-on block) |
| `jockey`    | E (hold)         | Left trigger (hold)            | Defender only: shadow the carrier at a contain speed, staying square to set up a tackle |
| `switch_player` | Q            | Button 9                       | On defence: take the player nearest the ball |
| `pause`     | Esc              | Start                          |                                            |
| aim dir     | Mouse position   | Player's facing direction      | No named action — read directly. Gamepad aims where the player faces; mouse aims at the cursor. |
| menu nav    | Arrows / WASD    | Left stick / D-pad (`ui_*`)    |                                            |
| menu accept | Enter / Space    | A button (`ui_accept`)         |                                            |
| menu back   | Esc              | B button (`ui_cancel`)         |                                            |

---

## Match feel & timing

The playable match (`scenes/match/`) is tuned for a few key feels. The relevant
tunables, with their home file:

- **Match length.** The clock counts a fixed game-minute span; the real:game
  ratio is `CLOCK_SPEED` in `match_scene.gd` (lower = longer real matches). Do
  not shorten the game clock to change match length — slow the ratio instead.
- **Scoring is accurate and slightly generous.** `_check_scoring()` sweeps the
  ball path between frames (interpolating where it crosses the goal line) so fast
  or just-landed shots can't slip through, with `SCORE_MARGIN` px of leeway
  outside the posts. Point vs goal is the interpolated arc height at the crossing
  vs `Ball.CROSSBAR_HEIGHT`. Passes never score (the ball's `shooter` is cleared
  on release).
- **Shooting is a skill with a sweet spot.** Power-bar fill speed is
  `SHOOT_MAX_HOLD` in `ai_player.gd`; `OVERCHARGE_KNEE`/`OVERCHARGE_SPREAD` add
  spray when held past the sweet spot. `MAX_SHOT_SPREAD` is the base difficulty
  spread.
- **Carry steps.** `STEP_DISTANCE` in `ai_player.gd` controls how fast the carry
  step counter fills (lower = fills faster, forcing a solo/bounce sooner).
- **Set pieces & kickouts.** No countdown for a human taker — the set piece arms
  immediately. The AI waits `AI_SET_PIECE_DELAY` (`match_scene.gd`) before kicking
  so the player gets a beat to react.
- **Visual reads.** The crossbar is drawn in a warm colour (`pitch.gd`); the ball
  gains a ring when it's above crossbar height (`ball.gd`).

---

## Running

Open the folder in Godot 4.6+. Main scene is `ui/main_menu/main_menu.tscn`.
The menu routes to Manager Career / Player Career / Settings; career buttons
currently just set state and warn (scaffold).
