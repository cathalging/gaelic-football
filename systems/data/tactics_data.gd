extends Resource
class_name TacticsData
## A team's behaviour profile — the tunable knobs that shape how its AI plays.
## Pure data, no behaviour (see CLAUDE.md "Data is Resources").
##
## Today these defaults reproduce the hand-tuned constants that used to live in
## `ai_player.gd`, so a freshly constructed `TacticsData` plays exactly as before.
## Career mode will later hand each club its own profile (high press vs sit deep,
## direct vs patient, etc.); the match scene assigns one per team on spawn and the
## AI reads every tactical decision from it instead of from baked-in constants.
##
## Kept JSON-serialisable (primitives only) so it round-trips through a career save
## and, eventually, network sync.

# ── Defensive shape & pressing ────────────────────────────────────────────────
## An opponent closer to the carrier than this (px) counts as pressure — the
## carrier then looks for a pass. Lower = the team lets you carry before reacting.
@export var press_trigger_distance: float = 150.0
## How far goalside of his man a marker stands (px). Higher = tighter, riskier
## marking that follows the man further from goal.
@export var mark_goalside: float = 42.0
## Defensive line height, −1 (sit very deep) … 0 (as drawn) … +1 (push right up).
## Shifts the whole defending block up or down the pitch. Reserved for the runs
## pass; harmless at 0.
@export_range(-1.0, 1.0, 0.05) var defensive_line_height: float = 0.0

# ── Attacking shape & off-the-ball runs ───────────────────────────────────────
## How far forwards push toward goal off the ball (px) when the team has it.
@export var support_distance: float = 70.0
## How far a pass leads a running forward toward goal (px) — the through-ball bias.
@export var pass_lead: float = 46.0
## Lateral spread multiplier for the attacking block (1 = as drawn). Reserved for
## the runs pass.
@export_range(0.5, 1.5, 0.05) var attacking_width: float = 1.0
## How many attackers commit to active off-the-ball runs at once. Reserved for the
## runs pass.
@export_range(0, 4, 1) var runner_count: int = 2
## Directness, 0 (patient — keep the ball, recycle) … 1 (direct — early ball
## forward, back the carry). Reserved for the runs pass.
@export_range(0.0, 1.0, 0.05) var directness: float = 0.5

# ── Movement / steering ───────────────────────────────────────────────────────
## How hard players steer around bodies in their path (1 = baseline). Higher
## arcs players further around traffic; 0 disables avoidance (they barge through).
@export_range(0.0, 2.0, 0.05) var avoidance_strength: float = 1.0
