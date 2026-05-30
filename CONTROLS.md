# Controls

## Match

| Action       | Keyboard          | Controller                  | Notes                                        |
|--------------|-------------------|-----------------------------|----------------------------------------------|
| Move         | WASD              | Left stick / D-pad          |                                              |
| Dash         | Shift             | Right trigger               | Short burst, **ball carrier only**, then a long cooldown |
| Aim          | Mouse position    | Right stick                 | No named action — read directly from axis    |
| Pass (hand)  | Z (tap)           | A (tap)                     | Quick punch pass in aim direction            |
| Pass (kick)  | Z (hold)          | A (hold)                    | Charged kick pass; longer hold = more power  |
| Shoot (point)| X (tap or hold)   | B (tap or hold)             | Over the bar; longer hold = more power       |
| Shoot (goal) | X (double-tap, hold 2nd) | B (double-tap, hold 2nd) | Drive at the goal; power from the second hold |
| Solo         | C                 | X                           | Toe-tap — resets 4-step counter (unlimited)  |
| Bounce       | V                 | Y                           | Bounce — resets 4-step counter (once/possession) |
| Tackle       | F                 | Right bumper                | Near a carrier — starts the timing contest (see below) |
| Jockey       | E (hold)          | Left trigger (hold)         | **Defender only** — shadow the carrier at a controlled speed to line up a tackle |
| Pause / Menu | Esc               | Start                       | Returns to main menu in Quick Play           |

Switching player on defence is on **Q / controller button 9** (`switch_player`) — hands
you the teammate nearest the ball, which is usually already in tackle range.

### Jockeying (contain)
You don't have to chase a carrier flat-out. **Hold Jockey** (defender, no ball) to move
at a slower, controlled speed while automatically staying **square to the carrier** — a
short blue arc shows who you're containing. Shepherd them away from goal and onto their
weak side, then strike with **Tackle** from the front (a front/side tackle is legal; from
behind is a foul). Defending is about position, not pace.

### Tap vs hold threshold
`pass` and `shoot` use a **0.20 s** threshold: release before 0.20 s = tap, after = hold.
Power scales from 0 to 1.5 s.

### Dash
Only the player **carrying the ball** can dash — a short speed burst followed by a long
cooldown. The ring around the controlled carrier shows availability: solid **green** =
ready, a **blue arc filling** = recovering. A dash also spends **stamina** (shown on the
bottom-left bar) and can't be started once your reserve runs low — sustained sprinting
drains it, walking/idling recovers it.

### Tackling (timing contest)
You can't take the ball just by touching a carrier — you have to tackle:

1. Get within range of the ball carrier and press **Tackle**.
2. A meter appears with a sweeping cursor, a wide **good** zone and a narrow **perfect**
   zone in the centre. Press **Tackle** again to strike (you have ~2 s).
   - **Perfect** → clean dispossession; the carrier is stunned briefly.
   - **Good** → the ball is knocked loose for either side to chase; carrier stunned briefly.
   - **Miss / out of time** → *you* are stunned and the tackle goes on a longer cooldown.
3. Tackling a carrier **from behind** is a foul (free kick, or penalty in the large square).

The contest difficulty (zone widths) will later scale with player stats.

### GAA carry rules (enforced)
- **4 steps** maximum before a foul is called (step = ~1.5 m of movement).
- **Solo** resets the step counter with no limit on uses.
- **Bounce** resets the step counter but may only be used **once per possession**.
- Violating the 4-step rule gives away a free kick to the opposition at the spot.

---

## Menus

| Action       | Keyboard          | Controller        |
|--------------|-------------------|-------------------|
| Navigate     | Arrow keys / WASD | Left stick / D-pad|
| Confirm      | Enter / Space     | A button          |
| Back         | Esc               | B button          |

---

## Adding or changing controls

All actions are defined in `project.godot` under **Project Settings → Input Map**.
Gameplay code must reference action names (e.g. `"pass"`, `"sprint"`) — never raw
keys or button indices. Add new actions there first, then read them by name in GDScript.
